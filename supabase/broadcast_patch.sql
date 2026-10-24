-- مركز التعميمات والإعلانات: أنواع (إعلان، تعميم، جدول، اختبارات، عاجل، فعالية)، تثبيت، رابط ملف، وإشعار شخصي لكل مستلم.
-- نفّذه مرة واحدة بعد grades_patch.sql (آمن للتكرار).

alter table public.announcements add column if not exists category text not null default 'announcement';
alter table public.announcements add column if not exists is_pinned boolean not null default false;
alter table public.announcements add column if not exists link_url text;
alter table public.notifications add column if not exists ref_id uuid;

do $$ begin
  alter table public.announcements add constraint announcements_category_check
    check (category in ('announcement','circular','schedule','exam','urgent','event'));
exception when duplicate_object then null; end $$;

create or replace function public.broadcast_announcement(
  p_title text, p_body text, p_category text, p_audience text,
  p_course uuid, p_link text, p_pinned boolean)
returns integer language plpgsql security definer set search_path = public
as $$
declare
  r text := public.current_role();
  a_id uuid; n integer := 0; label text; cat text := coalesce(p_category, 'announcement');
  aud text := coalesce(p_audience, 'all');
begin
  if r not in ('admin','head','teacher') then raise exception 'غير مصرح لك بالإرسال'; end if;
  if r = 'teacher' and (p_course is null or not public.is_course_teacher(p_course)) then
    raise exception 'يمكن للمدرس الإرسال لطلاب مقرراته فقط';
  end if;
  if coalesce(trim(p_title), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'العنوان والنص مطلوبان';
  end if;

  insert into public.announcements(title, body, category, audience, course_id, link_url, is_pinned, created_by)
  values (trim(p_title), trim(p_body), cat, aud, p_course,
          nullif(trim(coalesce(p_link, '')), ''), coalesce(p_pinned, false), auth.uid())
  returning id into a_id;

  label := case cat when 'circular' then 'تعميم' when 'schedule' then 'جدول' when 'exam' then 'اختبارات'
                    when 'urgent' then 'عاجل' when 'event' then 'فعالية' else 'إعلان' end;

  insert into public.notifications(user_id, title, body, kind, course_id, ref_id)
  select p.id, label || ': ' || trim(p_title),
         trim(p_body) || case when nullif(trim(coalesce(p_link, '')), '') is null then '' else E'\n' || trim(p_link) end,
         'announcement', p_course, a_id
  from public.profiles p
  where p.is_active and p.id <> auth.uid() and (
    case
      when p_course is not null then
        p.id in (select e.student_id from public.course_enrollments e where e.course_id = p_course)
        or p.id = (select c.teacher_id from public.courses c where c.id = p_course)
      when aud = 'students' then p.role = 'student'
      when aud = 'teachers' then p.role = 'teacher'
      when aud = 'department' then p.role in ('teacher', 'head')
      else true
    end);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.broadcast_announcement(text, text, text, text, uuid, text, boolean) from public, anon;
grant execute on function public.broadcast_announcement(text, text, text, text, uuid, text, boolean) to authenticated;

notify pgrst, 'reload schema';
