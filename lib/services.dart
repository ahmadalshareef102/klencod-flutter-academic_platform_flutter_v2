import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

// ───────────────────────── أدوات مشتركة ─────────────────────────

const dayNames = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة'];

Map<String, String> dayOptions() => {for (var i = 0; i < 7; i++) '$i': dayNames[i]};

String latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '：') {
      b.write(':');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// يوحّد الوقت إلى HH:MM أو يعيد null إن كان غير صالح.
String? normTime(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(latinDigits(s.trim()));
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return '${two(h)}:${two(mi)}';
}

String shortTime(Object? t) {
  final s = '${t ?? ''}';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

int? timeMinutes(Object? t) {
  final p = shortTime(t).split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

CourseInfo? courseById(List<CourseInfo> list, Object? id) {
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
}

String courseLabel(CourseInfo? c) => c == null ? 'مقرر' : '${c.code} · ${c.name}';

/// يجلب كل الصفوف على دفعات (تجاوز حد 1000 صف).
Future<List<Rec>> fetchAllRows(String table, String cols) async {
  final out = <Rec>[];
  var from = 0;
  while (true) {
    final page = await db.from(table).select(cols).order('id').range(from, from + 999);
    final list = (page as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    out.addAll(list);
    if (list.length < 1000) break;
    from += 1000;
  }
  return out;
}

Future<void> changePasswordFlow(BuildContext context) async {
  final r = await formDialog(
    context,
    'تغيير كلمة المرور',
    const [
      FormSpec('p1', 'كلمة المرور الجديدة', kind: FK.password),
      FormSpec('p2', 'تأكيد كلمة المرور', kind: FK.password),
    ],
    okLabel: 'تغيير',
  );
  if (r == null || !context.mounted) return;
  final p1 = r['p1'] ?? '';
  if (p1 != r['p2']) {
    snack(context, 'كلمتا المرور غير متطابقتين');
    return;
  }
  if (p1.length < 6) {
    snack(context, 'كلمة المرور يجب ألا تقل عن 6 أحرف');
    return;
  }
  await guarded(context, () async {
    await db.auth.updateUser(UserAttributes(password: p1));
  }, ok: 'تم تغيير كلمة المرور');
}

// ───────────────────────── الجدول الدراسي والتقويم ─────────────────────────

const eventKindAr = {'start': 'بداية الفصل', 'exam': 'اختبارات', 'holiday': 'إجازة', 'deadline': 'موعد نهائي', 'event': 'فعالية'};

Color eventKindColor(Object? k) {
  switch (k) {
    case 'start':
      return const Color(0xFF0F9D8A);
    case 'exam':
      return const Color(0xFFF59E0B);
    case 'holiday':
      return const Color(0xFF6D4AFF);
    case 'deadline':
      return const Color(0xFFE11D48);
    default:
      return blue;
  }
}

Rec? nextLecture(List<Rec> lectures) {
  final now = DateTime.now();
  final today = (now.weekday + 1) % 7;
  final nowMin = now.hour * 60 + now.minute;
  Rec? best;
  var bestDelta = 1 << 30;
  for (final l in lectures) {
    final d = l['day_of_week'];
    final st = timeMinutes(l['start_time']);
    if (d is! num || st == null) continue;
    var delta = ((d.toInt() - today) % 7) * 1440 + st - nowMin;
    if (delta < 0) delta += 7 * 1440;
    if (delta < bestDelta) {
      best = l;
      bestDelta = delta;
    }
  }
  return best;
}

class _TtData {
  final List<CourseInfo> courses;
  final List<Rec> rows;
  final List<Rec> events;
  const _TtData(this.courses, this.rows, this.events);
}

class TimetablePage extends StatefulWidget {
  final AppUser user;
  const TimetablePage({super.key, required this.user});
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  int _v = 0;
  List<CourseInfo> _courses = [];
  bool get _manage => widget.user.role.isManager;

  Future<_TtData> _load() async {
    final courses = await loadCourses(widget.user);
    _courses = courses;
    final rows = await fetch('timetable');
    final events = await fetch('academic_events', orderBy: 'start_date');
    final ids = courses.map((c) => c.id).toSet();
    return _TtData(courses, _manage ? rows : rows.where((r) => ids.contains(r['course_id'])).toList(), events);
  }

  Future<void> _chooseAdd() async {
    final c = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.schedule_rounded), title: const Text('إضافة محاضرة إلى الجدول'), onTap: () => Navigator.pop(ctx, 'lecture')),
          ListTile(leading: const Icon(Icons.quiz_outlined), title: const Text('إضافة موعد اختبار'), onTap: () => Navigator.pop(ctx, 'exam')),
          ListTile(leading: const Icon(Icons.event_rounded), title: const Text('إضافة حدث للتقويم الأكاديمي'), onTap: () => Navigator.pop(ctx, 'event')),
        ]),
      ),
    );
    if (c == null || !mounted) return;
    if (c == 'lecture') await _addLecture();
    if (c == 'exam') await _addExam();
    if (c == 'event') await _addEvent();
  }

  Future<void> _addLecture() async {
    final r = await formDialog(context, 'إضافة محاضرة', [
      FormSpec('course', 'المقرر', kind: FK.dropdown, options: courseOptions(_courses)),
      FormSpec('day', 'اليوم', kind: FK.dropdown, options: dayOptions()),
      const FormSpec('start', 'وقت البدء (مثال 08:00)'),
      const FormSpec('end', 'وقت الانتهاء (مثال 09:30)'),
      const FormSpec('room', 'القاعة', required: false),
    ]);
    if (r == null || !mounted) return;
    final st = normTime(r['start']!);
    final en = normTime(r['end']!);
    if (st == null || en == null) {
      snack(context, 'اكتب الوقت بصيغة 08:00');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('timetable').insert({'course_id': r['course']!, 'kind': 'lecture', 'day_of_week': int.parse(r['day']!), 'start_time': st, 'end_time': en, 'room': nz(r['room']), 'created_by': widget.user.id});
    }, ok: 'تمت إضافة المحاضرة');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _addExam() async {
    final r = await formDialog(context, 'إضافة موعد اختبار', [
      FormSpec('course', 'المقرر', kind: FK.dropdown, options: courseOptions(_courses)),
      const FormSpec('date', 'تاريخ الاختبار', kind: FK.date),
      const FormSpec('start', 'وقت البدء (مثال 09:00)'),
      const FormSpec('room', 'القاعة', required: false),
      const FormSpec('notes', 'ملاحظات (نصفي، نهائي…)', required: false),
    ]);
    if (r == null || !mounted) return;
    final st = normTime(r['start']!);
    if (st == null) {
      snack(context, 'اكتب الوقت بصيغة 09:00');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('timetable').insert({'course_id': r['course']!, 'kind': 'exam', 'exam_date': r['date']!, 'start_time': st, 'room': nz(r['room']), 'notes': nz(r['notes']), 'created_by': widget.user.id});
    }, ok: 'تمت إضافة موعد الاختبار');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _addEvent() async {
    final r = await formDialog(context, 'حدث في التقويم الأكاديمي', const [
      FormSpec('title', 'العنوان'),
      FormSpec('kind', 'النوع', kind: FK.dropdown, options: eventKindAr),
      FormSpec('start', 'من تاريخ', kind: FK.date),
      FormSpec('end', 'إلى تاريخ', kind: FK.date, required: false),
      FormSpec('notes', 'ملاحظات', required: false),
    ]);
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('academic_events').insert({'title': r['title']!, 'kind': r['kind']!, 'start_date': r['start']!, 'end_date': nz(r['end']), 'notes': nz(r['notes']), 'created_by': widget.user.id});
    }, ok: 'تمت الإضافة');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(String table, Rec r, String what) async {
    if (!await confirmDialog(context, 'حذف $what؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from(table).delete().eq('id', r['id']);
    }, ok: 'تم الحذف');
    if (ok && mounted) setState(() => _v++);
  }

  Widget _row(String table, Rec r, IconData icon, String title, String sub, Widget? tag) {
    final row = FeatureRow(icon: icon, title: title, subtitle: sub, trailing: tag);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _manage ? GestureDetector(onLongPress: () => _delete(table, r, title), child: row) : row,
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: navy)),
      );

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'الجدول والتقويم',
        fab: _manage ? FloatingActionButton.extended(onPressed: _chooseAdd, icon: const Icon(Icons.add_rounded), label: const Text('إضافة')) : null,
        body: FutureBody<_TtData>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) {
            final lectures = d.rows.where((r) => r['kind'] == 'lecture').toList();
            final today = dayKey(DateTime.now());
            final exams = d.rows.where((r) => r['kind'] == 'exam' && '${r['exam_date']}'.compareTo(today) >= 0).toList();
            exams.sort((a, b) => '${a['exam_date']} ${a['start_time']}'.compareTo('${b['exam_date']} ${b['start_time']}'));
            final events = d.events.where((e) => '${e['end_date'] ?? e['start_date']}'.compareTo(today) >= 0).toList();
            final next = nextLecture(lectures);
            final empty = lectures.isEmpty && exams.isEmpty && events.isEmpty;
            return refreshList(reload, [
              if (next != null)
                Card(
                  color: navy,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.alarm_rounded, color: Colors.white, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('أقرب محاضرة', style: TextStyle(color: Color(0xFFB6C7E0), fontSize: 11)),
                          const SizedBox(height: 3),
                          Text(courseLabel(courseById(d.courses, next['course_id'])), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text('${dayNames[(next['day_of_week'] as num).toInt() % 7]} · ${shortTime(next['start_time'])}${(next['room'] ?? '').toString().isEmpty ? '' : ' · قاعة ${next['room']}'}', style: const TextStyle(color: Color(0xFFDCE6F5), fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              if (empty) const Card(child: EmptyBox('لم تُنشر جداول أو أحداث بعد')),
              if (events.isNotEmpty) ...[
                _header('التقويم الأكاديمي'),
                for (final e in events)
                  _row('academic_events', e, Icons.event_rounded, '${e['title']}', '${fmtDate(e['start_date'])}${e['end_date'] == null ? '' : ' → ${fmtDate(e['end_date'])}'}${(e['notes'] ?? '').toString().isEmpty ? '' : '\n${e['notes']}'}', Tag(eventKindAr[e['kind']] ?? '', color: eventKindColor(e['kind']))),
              ],
              if (exams.isNotEmpty) ...[
                _header('مواعيد الاختبارات'),
                for (final x in exams)
                  _row('timetable', x, Icons.quiz_outlined, courseLabel(courseById(d.courses, x['course_id'])), '${fmtDate(x['exam_date'])} · ${shortTime(x['start_time'])}${(x['room'] ?? '').toString().isEmpty ? '' : ' · قاعة ${x['room']}'}${(x['notes'] ?? '').toString().isEmpty ? '' : '\n${x['notes']}'}', null),
              ],
              if (lectures.isNotEmpty) ...[
                _header('جدول المحاضرات الأسبوعي'),
                for (var i = 0; i < 7; i++) ..._dayWidgets(i, lectures, d.courses),
              ],
              if (_manage && !empty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('اضغط مطولاً على أي عنصر لحذفه', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: muted))),
            ]);
          },
        ),
      );

  List<Widget> _dayWidgets(int i, List<Rec> lectures, List<CourseInfo> courses) {
    final day = lectures.where((l) => l['day_of_week'] == i).toList();
    if (day.isEmpty) return <Widget>[];
    day.sort((a, b) => (timeMinutes(a['start_time']) ?? 0).compareTo(timeMinutes(b['start_time']) ?? 0));
    return [
      Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Tag(dayNames[i], color: blue)),
      for (final l in day)
        _row('timetable', l, Icons.schedule_rounded, courseLabel(courseById(courses, l['course_id'])), '${shortTime(l['start_time'])} – ${shortTime(l['end_time'])}${(l['room'] ?? '').toString().isEmpty ? '' : ' · قاعة ${l['room']}'}', null),
    ];
  }
}

// ───────────────────────── الحضور الذكي: نسبة الغياب والحرمان ─────────────────────────

const warnAbsencePct = 15.0;
const blockAbsencePct = 25.0;

class _AttStat {
  final String courseId;
  final String studentId;
  int total = 0;
  int absent = 0;
  int late = 0;
  _AttStat(this.courseId, this.studentId);
  double get pct => total == 0 ? 0 : absent * 100 / total;
}

Color absenceColor(double pct) {
  if (pct >= blockAbsencePct) return const Color(0xFFE11D48);
  if (pct >= warnAbsencePct) return const Color(0xFFF59E0B);
  return const Color(0xFF0F9D8A);
}

String absenceLabel(double pct) {
  if (pct >= blockAbsencePct) return 'معرّض للحرمان';
  if (pct >= warnAbsencePct) return 'تحذير';
  return 'آمن';
}

class AttendanceRiskPage extends StatefulWidget {
  final AppUser user;
  const AttendanceRiskPage({super.key, required this.user});
  @override
  State<AttendanceRiskPage> createState() => _AttendanceRiskPageState();
}

class _AttendanceRiskPageState extends State<AttendanceRiskPage> {
  bool get _student => widget.user.role == UserRole.student;

  Future<(List<_AttStat>, List<CourseInfo>, Map<String, Rec>)> _load() async {
    final courses = await loadCourses(widget.user);
    final att = _student ? await fetch('attendance', cols: 'course_id, student_id, status', eq: {'student_id': widget.user.id}) : await fetchAllRows('attendance', 'id, course_id, student_id, status');
    final people = _student ? <String, Rec>{} : await profileMap();
    final ids = courses.map((c) => c.id).toSet();
    final stats = <String, _AttStat>{};
    for (final a in att) {
      final cid = '${a['course_id']}';
      final sid = '${a['student_id']}';
      if (!ids.contains(cid)) continue;
      final s = stats.putIfAbsent('$cid|$sid', () => _AttStat(cid, sid));
      s.total++;
      if (a['status'] == 'absent') s.absent++;
      if (a['status'] == 'late') s.late++;
    }
    return (stats.values.toList(), courses, people);
  }

  Future<void> _warn(_AttStat s, CourseInfo? c, Rec? person) async {
    final msg = 'نسبة غيابك في ${c?.name ?? 'المقرر'} بلغت ${s.pct.round()}% والحد المسموح ${blockAbsencePct.round()}%. يرجى الالتزام بالحضور.';
    if (!await confirmDialog(context, 'إرسال تنبيه غياب إلى ${person?['full_name'] ?? 'الطالب'}؟')) return;
    if (!mounted) return;
    await guarded(context, () async {
      await db.rpc('send_notice', params: {'p_user': s.studentId, 'p_title': 'تنبيه غياب', 'p_body': msg, 'p_course': s.courseId});
    }, ok: 'تم إرسال التنبيه');
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: _student ? 'نسبة حضوري' : 'المعرّضون للحرمان',
        body: FutureBody<(List<_AttStat>, List<CourseInfo>, Map<String, Rec>)>(
          load: _load,
          builder: (context, d, reload) {
            final stats = [...d.$1];
            if (_student) {
              stats.sort((a, b) => b.pct.compareTo(a.pct));
            } else {
              stats.removeWhere((s) => s.pct < warnAbsencePct);
              stats.sort((a, b) => b.pct.compareTo(a.pct));
            }
            final risk = stats.where((s) => s.pct >= blockAbsencePct).length;
            return refreshList(reload, [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _student
                        ? 'يُحسب الغياب بدون عذر من إجمالي المحاضرات المسجّلة. تحذير عند ${warnAbsencePct.round()}% والحرمان عند ${blockAbsencePct.round()}% فأكثر.'
                        : 'طلاب تجاوز غيابهم ${warnAbsencePct.round()}% (تحذير) أو ${blockAbsencePct.round()}% (حرمان). عدد المعرّضين للحرمان: $risk',
                    style: const TextStyle(color: muted, height: 1.6, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (stats.isEmpty) Card(child: EmptyBox(_student ? 'لا توجد سجلات حضور بعد' : 'لا يوجد طلاب تجاوزوا حد التحذير 👏')),
              for (final s in stats)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_student ? courseLabel(courseById(d.$2, s.courseId)) : '${d.$3[s.studentId]?['full_name'] ?? 'طالب'}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                          Tag(absenceLabel(s.pct), color: absenceColor(s.pct)),
                        ]),
                        if (!_student) Padding(padding: const EdgeInsets.only(top: 3), child: Text(courseLabel(courseById(d.$2, s.courseId)), style: const TextStyle(fontSize: 12, color: muted))),
                        const SizedBox(height: 10),
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (s.pct / blockAbsencePct).clamp(0.0, 1.0), minHeight: 8, color: absenceColor(s.pct), backgroundColor: const Color(0xFFE5ECF5))),
                        const SizedBox(height: 8),
                        Text('الغياب ${s.absent} من ${s.total} محاضرة (${s.pct.round()}%) · تأخر ${s.late}', style: const TextStyle(fontSize: 12, color: muted)),
                        if (!_student)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(onPressed: () => _warn(s, courseById(d.$2, s.courseId), d.$3[s.studentId]), icon: const Icon(Icons.notifications_active_outlined, size: 18), label: const Text('إرسال تنبيه للطالب')),
                          ),
                      ]),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}

// ───────────────────────── اعتراضات الدرجات ─────────────────────────

const appealStatusAr = {'new': 'قيد الانتظار', 'in_review': 'قيد المراجعة', 'accepted': 'مقبول', 'rejected': 'مرفوض'};

Color appealColor(Object? s) {
  switch (s) {
    case 'accepted':
      return const Color(0xFF0F9D8A);
    case 'rejected':
      return const Color(0xFFE11D48);
    case 'in_review':
      return const Color(0xFFF59E0B);
    default:
      return blue;
  }
}

/// زر اعتراض الطالب داخل بطاقة النتيجة؛ يعرض حالة الاعتراض والرد إن وُجد.
class AppealButton extends StatefulWidget {
  final AppUser user;
  final String courseId;
  const AppealButton({super.key, required this.user, required this.courseId});
  @override
  State<AppealButton> createState() => _AppealButtonState();
}

class _AppealButtonState extends State<AppealButton> {
  bool _ready = false;
  bool _hidden = false;
  Rec? _appeal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await fetch('grade_appeals', eq: {'course_id': widget.courseId, 'student_id': widget.user.id});
      if (!mounted) return;
      setState(() {
        _appeal = rows.isEmpty ? null : rows.first;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden = true);
    }
  }

  Future<void> _submit() async {
    final r = await formDialog(context, 'اعتراض على الدرجة', const [FormSpec('reason', 'سبب الاعتراض', kind: FK.multiline)], okLabel: 'إرسال', intro: 'يصل اعتراضك إلى مدرس المقرر والإدارة، وسيصلك الرد في الإشعارات.');
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('grade_appeals').insert({'course_id': widget.courseId, 'student_id': widget.user.id, 'reason': r['reason']!});
    }, ok: 'تم إرسال اعتراضك');
    if (ok && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden || !_ready) return const SizedBox.shrink();
    final a = _appeal;
    if (a == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton.icon(onPressed: _submit, icon: const Icon(Icons.gavel_rounded, size: 18), label: const Text('اعتراض على الدرجة')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('اعتراضك: ', style: TextStyle(fontSize: 12, color: muted)),
          Tag(appealStatusAr[a['status']] ?? '', color: appealColor(a['status'])),
        ]),
        if ((a['response'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('الرد: ${a['response']}', style: const TextStyle(fontSize: 12, height: 1.5, color: navy))),
      ]),
    );
  }
}

class AppealsInboxPage extends StatefulWidget {
  final AppUser user;
  const AppealsInboxPage({super.key, required this.user});
  @override
  State<AppealsInboxPage> createState() => _AppealsInboxPageState();
}

class _AppealsInboxPageState extends State<AppealsInboxPage> {
  int _v = 0;

  Future<(List<Rec>, List<CourseInfo>, Map<String, Rec>)> _load() async => (await fetch('grade_appeals', orderBy: 'created_at', asc: false), await loadCourses(widget.user), await profileMap());

  Future<void> _respond(Rec a) async {
    final r = await formDialog(context, 'الرد على الاعتراض', [
      const FormSpec('status', 'القرار', kind: FK.dropdown, options: {'in_review': 'قيد المراجعة', 'accepted': 'قبول الاعتراض', 'rejected': 'رفض الاعتراض'}),
      FormSpec('response', 'نص الرد', kind: FK.multiline, required: false, initial: '${a['response'] ?? ''}'),
    ], okLabel: 'إرسال الرد', intro: 'سيصل الرد إلى الطالب كإشعار. إن لزم تعديل الدرجة فالإدارة تعدّلها من «التحكم بالنتائج» ثم تعيد نشرها.');
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.rpc('respond_appeal', params: {'p_id': a['id'], 'p_status': r['status']!, 'p_response': r['response'] ?? ''});
    }, ok: 'تم إرسال الرد');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'اعتراضات الدرجات',
        body: FutureBody<(List<Rec>, List<CourseInfo>, Map<String, Rec>)>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            if (d.$1.isEmpty) const Card(child: EmptyBox('لا توجد اعتراضات')),
            for (final a in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: InkWell(
                    onTap: () => _respond(a),
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${d.$3[a['student_id']]?['full_name'] ?? 'طالب'}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                          Tag(appealStatusAr[a['status']] ?? '', color: appealColor(a['status'])),
                        ]),
                        const SizedBox(height: 3),
                        Text(courseLabel(courseById(d.$2, a['course_id'])), style: const TextStyle(fontSize: 12, color: muted)),
                        const SizedBox(height: 8),
                        Text('${a['reason']}', style: const TextStyle(fontSize: 12, height: 1.6)),
                        if ((a['response'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('الرد: ${a['response']}', style: const TextStyle(fontSize: 12, height: 1.5, color: blue))),
                        const SizedBox(height: 6),
                        Text('${fmtDateTime(a['created_at'])} · اضغط للرد', style: const TextStyle(fontSize: 10, color: muted)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

// ───────────────────────── تقييم المقررات ─────────────────────────

const evalQuestions = ['وضوح الشرح', 'تنظيم المقرر والمحتوى', 'تفاعل المدرس مع الطلاب', 'عدالة التقويم والاختبارات'];
const ratingOptions = {'5': 'ممتاز', '4': 'جيد جداً', '3': 'جيد', '2': 'مقبول', '1': 'ضعيف'};

Color ratingColor(double v) => v >= 4 ? const Color(0xFF0F9D8A) : (v >= 3 ? const Color(0xFFF59E0B) : const Color(0xFFE11D48));

class CourseEvaluationPage extends StatefulWidget {
  final AppUser user;
  const CourseEvaluationPage({super.key, required this.user});
  @override
  State<CourseEvaluationPage> createState() => _CourseEvaluationPageState();
}

class _CourseEvaluationPageState extends State<CourseEvaluationPage> {
  int _v = 0;

  Future<(List<CourseInfo>, Set<String>)> _load() async {
    final courses = await loadCourses(widget.user);
    final done = await fetch('course_evaluations', cols: 'course_id', eq: {'student_id': widget.user.id});
    return (courses, done.map((e) => '${e['course_id']}').toSet());
  }

  Future<void> _evaluate(CourseInfo c) async {
    final r = await formDialog(context, 'تقييم ${c.name}', [
      for (var i = 0; i < 4; i++) FormSpec('q${i + 1}', evalQuestions[i], kind: FK.dropdown, options: ratingOptions, initial: '5'),
      const FormSpec('comment', 'ملاحظاتك', kind: FK.multiline, required: false),
    ], okLabel: 'إرسال', intro: 'تقييمك سري، لا يظهر اسمك للمدرس ولا للإدارة.');
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('course_evaluations').insert({
        'course_id': c.id,
        'student_id': widget.user.id,
        'q1': int.parse(r['q1']!),
        'q2': int.parse(r['q2']!),
        'q3': int.parse(r['q3']!),
        'q4': int.parse(r['q4']!),
        'comment': nz(r['comment']),
      });
    }, ok: 'شكراً، تم إرسال تقييمك');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'تقييم المقررات',
        body: FutureBody<(List<CourseInfo>, Set<String>)>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('رأيك يطوّر المقررات. التقييم سري ولمرة واحدة لكل مقرر.', style: TextStyle(color: muted, height: 1.6, fontSize: 12)))),
            const SizedBox(height: 12),
            if (d.$1.isEmpty) const Card(child: EmptyBox('لا توجد مقررات مسجلة')),
            for (final c in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeatureRow(
                  icon: Icons.rate_review_outlined,
                  title: courseLabel(c),
                  subtitle: c.teacherName,
                  onTap: d.$2.contains(c.id) ? null : () => _evaluate(c),
                  trailing: d.$2.contains(c.id) ? const Tag('تم التقييم', color: Color(0xFF0F9D8A)) : const Tag('قيّم الآن'),
                ),
              ),
          ]),
        ),
      );
}

class EvaluationResultsPage extends StatelessWidget {
  final AppUser user;
  const EvaluationResultsPage({super.key, required this.user});

  Future<List<Rec>> _load() async {
    final res = await db.rpc('evaluation_summary');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: user.role == UserRole.teacher ? 'تقييمات مقرراتي' : 'نتائج التقييم',
        body: FutureBody<List<Rec>>(
          load: _load,
          builder: (context, list, reload) => refreshList(reload, [
            const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('متوسطات تقييم الطلاب (من 5) وملاحظاتهم دون أسماء.', style: TextStyle(color: muted, height: 1.6, fontSize: 12)))),
            const SizedBox(height: 12),
            if (list.isEmpty) const Card(child: EmptyBox('لا توجد تقييمات بعد')),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Builder(builder: (context) {
                      final qs = [for (var i = 1; i <= 4; i++) ((e['q$i'] as num?) ?? 0).toDouble()];
                      final avg = qs.reduce((a, b) => a + b) / qs.length;
                      final comments = ((e['comments'] as List?) ?? const []).map((x) => '$x').toList();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${e['code']} · ${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                          Tag('${avg.toStringAsFixed(1)} / 5', color: ratingColor(avg)),
                        ]),
                        const SizedBox(height: 4),
                        Text('عدد المشاركين: ${e['responses']}', style: const TextStyle(fontSize: 11, color: muted)),
                        const SizedBox(height: 10),
                        for (var i = 0; i < 4; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${evalQuestions[i]}: ${qs[i].toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, color: navy)),
                              const SizedBox(height: 4),
                              ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (qs[i] / 5).clamp(0.0, 1.0), minHeight: 6, color: ratingColor(qs[i]), backgroundColor: const Color(0xFFE5ECF5))),
                            ]),
                          ),
                        if (comments.isNotEmpty) ...[
                          const Divider(),
                          const Text('ملاحظات الطلاب', style: TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 12)),
                          const SizedBox(height: 4),
                          for (final c in comments.take(6)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $c', style: const TextStyle(fontSize: 12, height: 1.5, color: muted))),
                        ],
                      ]);
                    }),
                  ),
                ),
              ),
          ]),
        ),
      );
}
