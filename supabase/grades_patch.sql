-- نظام رصد الدرجات والتحكم بالنتائج وإرسالها للطلاب
-- نفّذ هذا الملف مرة واحدة من SQL Editor في Supabase بعد schema.sql و schema_patch.sql
-- (آمن للتنفيذ أكثر من مرة).

-- 1) الدرجات العظمى لكل مقرر (تُعدَّل من شاشة «التحكم بالنتائج»)
alter table public.courses add column if not exists max_coursework numeric(5,2) not null default 20;
alter table public.courses add column if not exists max_midterm numeric(5,2) not null default 20;
alter table public.courses add column if not exists max_final numeric(5,2) not null default 60;

-- 2) درجات الطلاب في المقرر (يرصدها المدرس)
create table if not exists public.course_grades (
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  coursework numeric(5,2) check (coursework is null or coursework >= 0),
  midterm numeric(5,2) check (midterm is null or midterm >= 0),
  final_exam numeric(5,2) check (final_exam is null or final_exam >= 0),
  notes text,
  entered_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (course_id, student_id)
);

-- 3) تحكم الإدارة: فتح/إغلاق الرصد، ونشر النتائج للطلاب
create table if not exists public.grade_control (
  course_id uuid primary key references public.courses(id) on delete cascade,
  entry_open boolean not null default true,
  is_published boolean not null default false,
  published_at timestamptz,
  updated_by uuid references public.profiles(id)
);

-- 4) الإشعارات الشخصية (نتيجة كل طالب تصله هنا)
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  course_id uuid references public.courses(id) on delete set null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

alter table public.course_grades enable row level security;
alter table public.grade_control enable row level security;
alter table public.notifications enable row level security;

-- دوال مساعدة (security definer لتفادي تعقيد سياسات RLS المتداخلة)
create or replace function public.is_course_teacher(p_course uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select public.current_role() = 'teacher'
        and exists (select 1 from public.courses c where c.id = p_course and c.teacher_id = auth.uid()) $$;

create or replace function public.grades_published(p_course uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select is_published from public.grade_control where course_id = p_course), false) $$;

create or replace function public.grades_entry_open(p_course uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select entry_open and not is_published from public.grade_control where course_id = p_course), true) $$;

create or replace function public.grade_label(p_pct numeric)
returns text language sql immutable
as $$ select case when p_pct >= 85 then 'ممتاز' when p_pct >= 75 then 'جيد جداً'
                  when p_pct >= 65 then 'جيد' when p_pct >= 50 then 'مقبول' else 'راسب' end $$;

-- سياسات course_grades
drop policy if exists grades_read on public.course_grades;
create policy grades_read on public.course_grades for select to authenticated using (
  public.current_role() in ('admin','head')
  or public.is_course_teacher(course_id)
  or (student_id = auth.uid() and public.grades_published(course_id))
);
drop policy if exists grades_teacher_write on public.course_grades;
create policy grades_teacher_write on public.course_grades for insert to authenticated
with check (public.is_course_teacher(course_id) and public.grades_entry_open(course_id));
drop policy if exists grades_teacher_update on public.course_grades;
create policy grades_teacher_update on public.course_grades for update to authenticated
using (public.is_course_teacher(course_id) and public.grades_entry_open(course_id))
with check (public.is_course_teacher(course_id) and public.grades_entry_open(course_id));
drop policy if exists grades_manager_all on public.course_grades;
create policy grades_manager_all on public.course_grades for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));

-- سياسات grade_control: القراءة للجميع (حالة فقط)، والكتابة للإدارة ورئيس القسم
drop policy if exists control_read on public.grade_control;
create policy control_read on public.grade_control for select to authenticated using (true);
drop policy if exists control_manage on public.grade_control;
create policy control_manage on public.grade_control for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));

-- سياسات notifications: كل مستخدم يرى ويحدّث إشعاراته فقط، والإدراج عبر الدالة فقط
drop policy if exists notif_read_own on public.notifications;
create policy notif_read_own on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists notif_update_own on public.notifications;
create policy notif_update_own on public.notifications for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

-- مشغّل التحقق: الطالب مسجل في المقرر، والدرجة لا تتجاوز الحد الأعلى
create or replace function public.course_grades_guard()
returns trigger language plpgsql security definer set search_path = public
as $$
declare c record;
begin
  select max_coursework, max_midterm, max_final into c from public.courses where id = new.course_id;
  if not exists (select 1 from public.course_enrollments e where e.course_id = new.course_id and e.student_id = new.student_id) then
    raise exception 'الطالب غير مسجل في هذا المقرر';
  end if;
  if new.coursework is not null and new.coursework > c.max_coursework then
    raise exception 'درجة أعمال السنة تتجاوز الحد الأعلى (%)', c.max_coursework;
  end if;
  if new.midterm is not null and new.midterm > c.max_midterm then
    raise exception 'درجة الاختبار النصفي تتجاوز الحد الأعلى (%)', c.max_midterm;
  end if;
  if new.final_exam is not null and new.final_exam > c.max_final then
    raise exception 'درجة الاختبار النهائي تتجاوز الحد الأعلى (%)', c.max_final;
  end if;
  new.entered_by := auth.uid();
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists course_grades_guard_trg on public.course_grades;
create trigger course_grades_guard_trg before insert or update on public.course_grades
for each row execute function public.course_grades_guard();

-- نشر النتائج (أو إلغاء النشر) وإرسال نتيجة كل طالب في إشعار شخصي.
-- تعيد عدد الإشعارات المرسلة. مسموحة لإدارة الكلية ورئيس القسم فقط.
create or replace function public.set_results_published(p_course uuid, p_publish boolean)
returns integer language plpgsql security definer set search_path = public
as $$
declare
  c record; g record; total numeric; mx numeric; sent integer := 0;
begin
  if public.current_role() not in ('admin','head') then
    raise exception 'غير مصرح لك بهذه العملية';
  end if;
  select name, max_coursework, max_midterm, max_final into c from public.courses where id = p_course;
  if not found then raise exception 'المقرر غير موجود'; end if;
  mx := c.max_coursework + c.max_midterm + c.max_final;

  insert into public.grade_control(course_id, entry_open, is_published, published_at, updated_by)
  values (p_course, not p_publish, p_publish, case when p_publish then now() else null end, auth.uid())
  on conflict (course_id) do update
    set entry_open = excluded.entry_open, is_published = excluded.is_published,
        published_at = excluded.published_at, updated_by = excluded.updated_by;

  delete from public.notifications where kind = 'result' and course_id = p_course;

  if p_publish then
    for g in select * from public.course_grades where course_id = p_course loop
      total := coalesce(g.coursework,0) + coalesce(g.midterm,0) + coalesce(g.final_exam,0);
      insert into public.notifications(user_id, title, body, kind, course_id)
      values (
        g.student_id,
        'نتيجة مقرر ' || c.name,
        'أعمال السنة: ' || coalesce(g.coursework::text,'—') || ' من ' || c.max_coursework
          || E'\nالاختبار النصفي: ' || coalesce(g.midterm::text,'—') || ' من ' || c.max_midterm
          || E'\nالاختبار النهائي: ' || coalesce(g.final_exam::text,'—') || ' من ' || c.max_final
          || E'\nالمجموع: ' || total || ' من ' || mx
          || E'\nالتقدير: ' || public.grade_label(case when mx > 0 then total * 100 / mx else 0 end),
        'result', p_course);
      sent := sent + 1;
    end loop;
  end if;
  return sent;
end $$;
revoke all on function public.set_results_published(uuid, boolean) from public, anon;
grant execute on function public.set_results_published(uuid, boolean) to authenticated;
