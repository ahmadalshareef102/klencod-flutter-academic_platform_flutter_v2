-- المنصة الأكاديمية الرقمية: مخطط تأسيسي لـ Supabase
-- نفّذ هذا الملف من SQL Editor في مشروع Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role text not null check (role in ('student','teacher','head','admin')),
  student_number text,
  department text default 'قسم معلم حاسوب',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  teacher_id uuid references public.profiles(id),
  semester text,
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.course_enrollments (
  course_id uuid references public.courses(id) on delete cascade,
  student_id uuid references public.profiles(id) on delete cascade,
  enrolled_at timestamptz not null default now(),
  primary key(course_id, student_id)
);
create table if not exists public.lectures (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  description text,
  file_path text,
  published_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  instructions text,
  due_at timestamptz,
  max_score numeric(6,2) not null default 100 check (max_score >= 0),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  answer_text text,
  file_path text,
  submitted_at timestamptz not null default now(),
  score numeric(6,2),
  feedback text,
  graded_by uuid references public.profiles(id),
  unique(assignment_id, student_id)
);
create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  session_date date not null,
  status text not null check (status in ('present','absent','late','excused')),
  recorded_by uuid references public.profiles(id),
  notes text,
  created_at timestamptz not null default now(),
  unique(course_id, student_id, session_date)
);
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  course_id uuid references public.courses(id) on delete cascade,
  audience text not null default 'all' check (audience in ('all','students','teachers','department')),
  published_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);
create table if not exists public.complaints (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid not null references public.profiles(id),
  subject text not null,
  body text not null,
  status text not null default 'new' check (status in ('new','in_review','resolved','closed')),
  response text,
  handled_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.course_progress (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id),
  topic text not null,
  completion_percent integer not null default 0 check (completion_percent between 0 and 100),
  notes text,
  updated_at timestamptz not null default now()
);

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and is_active = true limit 1 $$;

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.course_enrollments enable row level security;
alter table public.lectures enable row level security;
alter table public.assignments enable row level security;
alter table public.submissions enable row level security;
alter table public.attendance enable row level security;
alter table public.announcements enable row level security;
alter table public.complaints enable row level security;
alter table public.course_progress enable row level security;

drop policy if exists profiles_read_self_or_staff on public.profiles;
create policy profiles_read_self_or_staff on public.profiles for select to authenticated
using (id = auth.uid() or public.current_role() in ('admin','head','teacher'));
drop policy if exists profiles_admin_manage on public.profiles;
create policy profiles_admin_manage on public.profiles for all to authenticated
using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
drop policy if exists courses_read_signed_in on public.courses;
create policy courses_read_signed_in on public.courses for select to authenticated
using (is_published = true or public.current_role() in ('admin','head') or teacher_id = auth.uid());
drop policy if exists courses_admin_manage on public.courses;
create policy courses_admin_manage on public.courses for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));
drop policy if exists enrollments_read_own_or_staff on public.course_enrollments;
create policy enrollments_read_own_or_staff on public.course_enrollments for select to authenticated
using (student_id = auth.uid() or public.current_role() in ('admin','head','teacher'));
drop policy if exists enrollments_admin_manage on public.course_enrollments;
create policy enrollments_admin_manage on public.course_enrollments for all to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));
drop policy if exists lectures_read_related on public.lectures;
create policy lectures_read_related on public.lectures for select to authenticated using (
 public.current_role() in ('admin','head') or created_by = auth.uid() or exists (
  select 1 from public.course_enrollments e where e.course_id = lectures.course_id and e.student_id = auth.uid())) ;
drop policy if exists lectures_staff_manage on public.lectures;
create policy lectures_staff_manage on public.lectures for all to authenticated
using (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and created_by = auth.uid()))
with check (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and created_by = auth.uid()));
drop policy if exists assignments_read_related on public.assignments;
create policy assignments_read_related on public.assignments for select to authenticated using (
 public.current_role() in ('admin','head','teacher') or exists (select 1 from public.course_enrollments e where e.course_id = assignments.course_id and e.student_id = auth.uid()));
drop policy if exists assignments_staff_manage on public.assignments;
create policy assignments_staff_manage on public.assignments for all to authenticated
using (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and created_by = auth.uid()))
with check (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and created_by = auth.uid()));
drop policy if exists submissions_read_own_or_staff on public.submissions;
create policy submissions_read_own_or_staff on public.submissions for select to authenticated
using (student_id = auth.uid() or public.current_role() in ('admin','head','teacher'));
drop policy if exists submissions_student_insert on public.submissions;
create policy submissions_student_insert on public.submissions for insert to authenticated
with check (student_id = auth.uid() and public.current_role() = 'student');
drop policy if exists submissions_staff_update on public.submissions;
create policy submissions_staff_update on public.submissions for update to authenticated
using (public.current_role() in ('admin','head','teacher')) with check (public.current_role() in ('admin','head','teacher'));
drop policy if exists attendance_read_related on public.attendance;
create policy attendance_read_related on public.attendance for select to authenticated
using (student_id = auth.uid() or public.current_role() in ('admin','head','teacher'));
drop policy if exists attendance_staff_manage on public.attendance;
create policy attendance_staff_manage on public.attendance for all to authenticated
using (public.current_role() in ('admin','head','teacher')) with check (public.current_role() in ('admin','head','teacher'));
drop policy if exists announcements_read_signed_in on public.announcements;
create policy announcements_read_signed_in on public.announcements for select to authenticated using (true);
drop policy if exists announcements_staff_manage on public.announcements;
create policy announcements_staff_manage on public.announcements for all to authenticated
using (public.current_role() in ('admin','head','teacher')) with check (public.current_role() in ('admin','head','teacher'));
drop policy if exists complaints_read_own_or_staff on public.complaints;
create policy complaints_read_own_or_staff on public.complaints for select to authenticated
using (submitted_by = auth.uid() or public.current_role() in ('admin','head'));
drop policy if exists complaints_insert_own on public.complaints;
create policy complaints_insert_own on public.complaints for insert to authenticated with check (submitted_by = auth.uid());
drop policy if exists complaints_staff_update on public.complaints;
create policy complaints_staff_update on public.complaints for update to authenticated
using (public.current_role() in ('admin','head')) with check (public.current_role() in ('admin','head'));
drop policy if exists progress_read_staff on public.course_progress;
create policy progress_read_staff on public.course_progress for select to authenticated
using (public.current_role() in ('admin','head') or teacher_id = auth.uid());
drop policy if exists progress_teacher_manage on public.course_progress;
create policy progress_teacher_manage on public.course_progress for all to authenticated
using (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and teacher_id = auth.uid()))
with check (public.current_role() in ('admin','head') or (public.current_role() = 'teacher' and teacher_id = auth.uid()));

-- إنشاء أول حساب إدارة:
-- 1) أنشئ مستخدمًا من Authentication > Users في لوحة Supabase.
-- 2) انسخ UUID والبريد والاسم، ثم نفّذ بعد تعديل القيم:
-- insert into public.profiles(id, full_name, email, role) values ('UUID-HERE','مدير المنصة','admin@example.com','admin');
