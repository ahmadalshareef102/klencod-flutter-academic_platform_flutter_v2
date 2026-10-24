-- تحديث صلاحيات القراءة للنسخة المرتبطة ببيانات حقيقية.
-- نفّذ هذا الملف مرة واحدة من SQL Editor في Supabase (يمكن تنفيذه أكثر من مرة بأمان).

-- 1) يسمح لكل مستخدم مسجّل برؤية أسماء المدرسين ورؤساء الأقسام (لعرض اسم مدرس المقرر).
drop policy if exists profiles_read_teachers on public.profiles;
create policy profiles_read_teachers on public.profiles for select to authenticated
using (role in ('teacher','head') and is_active = true);

-- 2) يسمح للطالب برؤية تقدم المقررات المسجل بها.
drop policy if exists progress_read_enrolled on public.course_progress;
create policy progress_read_enrolled on public.course_progress for select to authenticated
using (exists (select 1 from public.course_enrollments e where e.course_id = course_progress.course_id and e.student_id = auth.uid()));

-- 3) يسمح للمدرس برؤية محاضرات مقرراته حتى لو أضافها غيره (الإدارة مثلاً).
drop policy if exists lectures_read_course_teacher on public.lectures;
create policy lectures_read_course_teacher on public.lectures for select to authenticated
using (exists (select 1 from public.courses c where c.id = lectures.course_id and c.teacher_id = auth.uid()));

-- 4) يسمح للطالب برؤية مقرراته المسجلة حتى لو كانت مخفية.
drop policy if exists courses_read_enrolled on public.courses;
create policy courses_read_enrolled on public.courses for select to authenticated
using (exists (select 1 from public.course_enrollments e where e.course_id = courses.id and e.student_id = auth.uid()));
