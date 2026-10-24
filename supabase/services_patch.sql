-- الجداول والتقويم، الاعتراض على الدرجات، تقييم المقررات، تنبيهات الغياب.
-- نفّذه بعد grades_patch.sql و broadcast_patch.sql (آمن للتكرار).

-- 1) الجدول الدراسي (محاضرات أسبوعية + مواعيد اختبارات)
create table if not exists public.timetable (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  kind text not null default 'lecture' check (kind in ('lecture','exam')),
  day_of_week smallint check (day_of_week between 0 and 6),   -- 0=السبت … 6=الجمعة
  start_time time not null,
  end_time time,
  exam_date date,
  room text,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- 2) التقويم الأكاديمي
create table if not exists public.academic_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null default 'event' check (kind in ('start','exam','holiday','deadline','event')),
  start_date date not null,
  end_date date,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- 3) اعتراضات الدرجات
create table if not exists public.grade_appeals (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  status text not null default 'new' check (status in ('new','in_review','accepted','rejected')),
  response text,
  responded_by uuid references public.profiles(id),
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (course_id, student_id)
);

-- 4) تقييم المقررات (سري: الإدارة والمدرس يرون المتوسطات والتعليقات دون أسماء)
create table if not exists public.course_evaluations (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  q1 smallint not null check (q1 between 1 and 5),
  q2 smallint not null check (q2 between 1 and 5),
  q3 smallint not null check (q3 between 1 and 5),
  q4 smallint not null check (q4 between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (course_id, student_id)
);

alter table public.timetable enable row level security;
alter table public.academic_events enable row level security;
alter table public.grade_appeals enable row level security;
alter table public.course_evaluations enable row level security;

drop policy if exists tt_read on public.timetable;
create policy tt_read on public.timetable for select to authenticated using (true);
drop policy if exists tt_manage on public.timetable;
create policy tt_manage on public.timetable for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));

drop policy if exists ev_read on public.academic_events;
create policy ev_read on public.academic_events for select to authenticated using (true);
drop policy if exists ev_manage on public.academic_events;
create policy ev_manage on public.academic_events for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));

drop policy if exists appeals_read on public.grade_appeals;
create policy appeals_read on public.grade_appeals for select to authenticated using (
  student_id = auth.uid() or public.current_role() in ('admin','head') or public.is_course_teacher(course_id));
drop policy if exists appeals_insert on public.grade_appeals;
create policy appeals_insert on public.grade_appeals for insert to authenticated with check (
  student_id = auth.uid() and public.grades_published(course_id)
  and exists (select 1 from public.course_enrollments e where e.course_id = grade_appeals.course_id and e.student_id = auth.uid()));

drop policy if exists evals_read_own on public.course_evaluations;
create policy evals_read_own on public.course_evaluations for select to authenticated using (student_id = auth.uid());
drop policy if exists evals_insert_own on public.course_evaluations;
create policy evals_insert_own on public.course_evaluations for insert to authenticated with check (
  student_id = auth.uid()
  and exists (select 1 from public.course_enrollments e where e.course_id = course_evaluations.course_id and e.student_id = auth.uid()));

-- الرد على اعتراض (الإدارة/رئيس القسم/مدرس المقرر) + إشعار للطالب
create or replace function public.respond_appeal(p_id uuid, p_status text, p_response text)
returns void language plpgsql security definer set search_path = public
as $$
declare a record; lbl text;
begin
  select * into a from public.grade_appeals where id = p_id;
  if not found then raise exception 'الاعتراض غير موجود'; end if;
  if not (public.current_role() in ('admin','head') or public.is_course_teacher(a.course_id)) then
    raise exception 'غير مصرح لك بالرد على هذا الاعتراض';
  end if;
  if p_status not in ('in_review','accepted','rejected') then raise exception 'حالة غير صالحة'; end if;
  update public.grade_appeals
     set status = p_status, response = nullif(trim(coalesce(p_response, '')), ''),
         responded_by = auth.uid(), responded_at = now()
   where id = p_id;
  lbl := case p_status when 'accepted' then 'تم قبول اعتراضك' when 'rejected' then 'تم رفض اعتراضك' else 'اعتراضك قيد المراجعة' end;
  insert into public.notifications(user_id, title, body, kind, course_id, ref_id)
  values (a.student_id, 'ردّ على اعتراضك على الدرجة',
          lbl || case when nullif(trim(coalesce(p_response, '')), '') is null then '' else E'\n' || trim(p_response) end,
          'appeal', a.course_id, p_id);
end $$;
revoke all on function public.respond_appeal(uuid, text, text) from public, anon;
grant execute on function public.respond_appeal(uuid, text, text) to authenticated;

-- ملخص التقييم دون أسماء: الإدارة ورئيس القسم يرون الكل، والمدرس مقرراته فقط
create or replace function public.evaluation_summary()
returns jsonb language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x order by x->>'code'), '[]'::jsonb) from (
    select jsonb_build_object(
      'course_id', c.id, 'code', c.code, 'name', c.name, 'responses', count(*),
      'q1', round(avg(e.q1), 2), 'q2', round(avg(e.q2), 2), 'q3', round(avg(e.q3), 2), 'q4', round(avg(e.q4), 2),
      'comments', coalesce(jsonb_agg(e.comment) filter (where coalesce(trim(e.comment), '') <> ''), '[]'::jsonb)
    ) as x
    from public.courses c join public.course_evaluations e on e.course_id = c.id
    where public.current_role() in ('admin','head') or c.teacher_id = auth.uid()
    group by c.id
  ) s
$$;
revoke all on function public.evaluation_summary() from public, anon;
grant execute on function public.evaluation_summary() to authenticated;

-- إرسال تنبيه شخصي لطالب (مثل تنبيه الغياب)؛ المدرس لطلاب مقرراته فقط
create or replace function public.send_notice(p_user uuid, p_title text, p_body text, p_course uuid default null)
returns void language plpgsql security definer set search_path = public
as $$
declare r text := public.current_role();
begin
  if r not in ('admin','head','teacher') then raise exception 'غير مصرح'; end if;
  if r = 'teacher' and not exists (
    select 1 from public.course_enrollments e join public.courses c on c.id = e.course_id
    where e.student_id = p_user and c.teacher_id = auth.uid()) then
    raise exception 'يمكن للمدرس تنبيه طلاب مقرراته فقط';
  end if;
  insert into public.notifications(user_id, title, body, kind, course_id) values (p_user, p_title, p_body, 'notice', p_course);
end $$;
revoke all on function public.send_notice(uuid, text, text, uuid) from public, anon;
grant execute on function public.send_notice(uuid, text, text, uuid) to authenticated;

notify pgrst, 'reload schema';
