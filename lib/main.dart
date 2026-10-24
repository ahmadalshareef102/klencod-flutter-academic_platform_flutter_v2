import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'broadcast.dart';
import 'grades.dart';
import 'services.dart';

const supabaseUrl = 'https://lpitsicjlqimkpgjiggd.supabase.co';
const supabaseAnonKey = 'sb_publishable_30Y5FaUnInQRoGsDOflRvQ_pKqAg8jS';
bool get isSupabaseConfigured => supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isSupabaseConfigured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const AcademicPlatformApp());
}

const navy = Color(0xFF102A43);
const blue = Color(0xFF1976D2);
const paleBlue = Color(0xFFEAF3FF);
const pageBg = Color(0xFFF5F7FB);
const muted = Color(0xFF718096);
const palette = <Color>[Color(0xFF1976D2), Color(0xFF0F9D8A), Color(0xFF8B5CF6), Color(0xFFF59E0B), Color(0xFFE11D48), Color(0xFF0EA5E9)];

class AcademicPlatformApp extends StatelessWidget {
  const AcademicPlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المنصة الأكاديمية الرقمية',
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
        scaffoldBackgroundColor: pageBg,
        fontFamily: 'Cairo',
        appBarTheme: const AppBarTheme(backgroundColor: pageBg, surfaceTintColor: Colors.transparent, foregroundColor: navy, centerTitle: false, elevation: 0, scrolledUnderElevation: 0),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3EAF2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: blue, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ───────────────────────── الأدوار والمستخدم ─────────────────────────

enum UserRole { student, teacher, head, admin }

extension RoleDetails on UserRole {
  String get label => switch (this) {
        UserRole.student => 'طالب',
        UserRole.teacher => 'مدرس',
        UserRole.head => 'رئيس القسم',
        UserRole.admin => 'إدارة الكلية',
      };
  String get key => switch (this) {
        UserRole.student => 'student',
        UserRole.teacher => 'teacher',
        UserRole.head => 'head',
        UserRole.admin => 'admin',
      };
  String get greeting => switch (this) {
        UserRole.student => 'مرحباً بك في رحلتك التعليمية',
        UserRole.teacher => 'إدارة مقرراتك ومتابعة طلابك',
        UserRole.head => 'متابعة أداء القسم والمقررات',
        UserRole.admin => 'نظرة شاملة على العملية التعليمية',
      };
  IconData get icon => switch (this) {
        UserRole.student => Icons.school_rounded,
        UserRole.teacher => Icons.cast_for_education_rounded,
        UserRole.head => Icons.account_tree_rounded,
        UserRole.admin => Icons.admin_panel_settings_rounded,
      };
  bool get isStaff => this != UserRole.student;
  bool get isManager => this == UserRole.admin || this == UserRole.head;
}

UserRole? parseRole(String? v) {
  for (final r in UserRole.values) {
    if (r.key == v) return r;
  }
  return null;
}

String roleLabel(String? v) => parseRole(v)?.label ?? (v ?? '—');

class AppUser {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? studentNumber;
  const AppUser({required this.id, required this.name, required this.email, required this.role, this.studentNumber});
}

Future<AppUser> loadAppUser(User user) async {
  final p = await db.from('profiles').select('full_name, email, role, is_active, student_number').eq('id', user.id).maybeSingle();
  if (p == null) {
    await db.auth.signOut();
    throw const AuthException('الحساب غير مضاف إلى ملفات المنصة. راجع إدارة الكلية.');
  }
  if (p['is_active'] == false) {
    await db.auth.signOut();
    throw const AuthException('هذا الحساب موقوف. راجع إدارة الكلية.');
  }
  final role = parseRole(p['role'] as String?);
  if (role == null) {
    await db.auth.signOut();
    throw const AuthException('صلاحية الحساب غير صحيحة؛ راجع إدارة المنصة.');
  }
  final fullName = (p['full_name'] as String?)?.trim() ?? '';
  return AppUser(
    id: user.id,
    name: fullName.isNotEmpty ? fullName : (user.email ?? ''),
    email: (p['email'] as String?) ?? (user.email ?? ''),
    role: role,
    studentNumber: p['student_number'] as String?,
  );
}

// ───────────────────────── أدوات قاعدة البيانات ─────────────────────────

typedef Rec = Map<String, dynamic>;

SupabaseClient get db => Supabase.instance.client;

Future<List<Rec>> fetch(String table, {String cols = '*', String? orderBy, bool asc = true, Map<String, Object>? eq}) async {
  dynamic q = db.from(table).select(cols);
  if (eq != null) {
    for (final e in eq.entries) {
      q = q.eq(e.key, e.value);
    }
  }
  if (orderBy != null) q = q.order(orderBy, ascending: asc);
  final res = await q;
  return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Future<Map<String, Rec>> profileMap() async {
  final rows = await fetch('profiles', cols: 'id, full_name, email, role, student_number, is_active, department');
  return {for (final r in rows) r['id'] as String: r};
}

String pname(Map<String, Rec> people, dynamic id) => (people[id]?['full_name'] as String?) ?? '—';

String errText(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('schema cache') || m.contains('does not exist')) {
      return '$m\nنفّذ ملف supabase/grades_patch.sql في Supabase (SQL Editor) ثم أعد المحاولة.';
    }
    return m;
  }
  if (e is AuthException) return e.message;
  return e.toString();
}

String two(int n) => n.toString().padLeft(2, '0');
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String fmtDate(dynamic iso) {
  final d = iso == null ? null : DateTime.tryParse(iso.toString());
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.year}/${two(l.month)}/${two(l.day)}';
}

String fmtDateTime(dynamic iso) {
  final d = iso == null ? null : DateTime.tryParse(iso.toString());
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.year}/${two(l.month)}/${two(l.day)}  ${two(l.hour)}:${two(l.minute)}';
}

const attendanceAr = {'present': 'حاضر', 'absent': 'غائب', 'late': 'متأخر', 'excused': 'بعذر'};
const complaintAr = {'new': 'جديدة', 'in_review': 'قيد المراجعة', 'resolved': 'تم الحل', 'closed': 'مغلقة'};
const audienceAr = {'all': 'الجميع', 'students': 'الطلاب', 'teachers': 'المدرسون', 'department': 'القسم'};

void snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// ينفذ عملية ويعرض رسالة نجاح أو خطأ. يعيد true عند النجاح.
Future<bool> guarded(BuildContext context, Future<void> Function() job, {String? ok}) async {
  try {
    await job();
    if (ok != null) snack(context, ok);
    return true;
  } catch (e) {
    snack(context, 'تعذر تنفيذ العملية: ${errText(e)}');
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
      ],
    ),
  );
  return r == true;
}

// ───────────────────────── نموذج إدخال عام ─────────────────────────

enum FK { text, multiline, number, date, dropdown, password }

class FormSpec {
  final String key;
  final String label;
  final FK kind;
  final bool required;
  final Map<String, String>? options;
  final String? initial;
  const FormSpec(this.key, this.label, {this.kind = FK.text, this.required = true, this.options, this.initial});
}

Future<Map<String, String>?> formDialog(BuildContext context, String title, List<FormSpec> specs, {String okLabel = 'حفظ', String? intro}) {
  return showDialog<Map<String, String>>(context: context, builder: (_) => _FormDialog(title: title, specs: specs, okLabel: okLabel, intro: intro));
}

String? nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

class _FormDialog extends StatefulWidget {
  final String title;
  final List<FormSpec> specs;
  final String okLabel;
  final String? intro;
  const _FormDialog({required this.title, required this.specs, required this.okLabel, this.intro});
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _c = <String, TextEditingController>{};
  final _sel = <String, String>{};
  String? _err;

  @override
  void initState() {
    super.initState();
    for (final s in widget.specs) {
      _c[s.key] = TextEditingController(text: s.initial ?? '');
      if (s.kind == FK.dropdown) {
        final opts = s.options ?? const <String, String>{};
        _sel[s.key] = (s.initial != null && opts.containsKey(s.initial)) ? s.initial! : (opts.isNotEmpty ? opts.keys.first : '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final out = <String, String>{};
    for (final s in widget.specs) {
      final v = s.kind == FK.dropdown ? (_sel[s.key] ?? '') : _c[s.key]!.text.trim();
      if (s.required && v.isEmpty) {
        setState(() => _err = 'الحقل مطلوب: ${s.label}');
        return;
      }
      if (s.kind == FK.number && v.isNotEmpty && num.tryParse(v) == null) {
        setState(() => _err = 'أدخل رقماً صحيحاً في: ${s.label}');
        return;
      }
      out[s.key] = v;
    }
    Navigator.pop(context, out);
  }

  Widget _field(FormSpec s) {
    switch (s.kind) {
      case FK.dropdown:
        final opts = s.options ?? const <String, String>{};
        if (opts.isEmpty) return const Text('لا توجد خيارات متاحة بعد', style: TextStyle(color: muted));
        return DropdownButtonFormField<String>(
          value: _sel[s.key],
          isExpanded: true,
          items: opts.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _sel[s.key] = v ?? ''),
        );
      case FK.date:
        return TextField(
          controller: _c[s.key],
          readOnly: true,
          decoration: const InputDecoration(hintText: 'اضغط لاختيار التاريخ', suffixIcon: Icon(Icons.calendar_month_outlined)),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) setState(() => _c[s.key]!.text = dayKey(d));
          },
        );
      case FK.multiline:
        return TextField(controller: _c[s.key], maxLines: 4, minLines: 3);
      case FK.number:
        return TextField(controller: _c[s.key], keyboardType: const TextInputType.numberWithOptions(decimal: true));
      case FK.password:
        return TextField(controller: _c[s.key], obscureText: true);
      case FK.text:
        return TextField(controller: _c[s.key]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.intro != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.intro!, style: const TextStyle(height: 1.6, color: muted, fontSize: 13))),
            for (final s in widget.specs) ...[
              Padding(padding: const EdgeInsets.only(bottom: 6, top: 6), child: Text(s.required ? s.label : '${s.label} (اختياري)', style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 13))),
              _field(s),
            ],
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: Text(widget.okLabel)),
      ],
    );
  }
}

// ───────────────────────── عناصر واجهة مشتركة ─────────────────────────

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 14)));
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const SectionHeading({super.key, required this.title, this.subtitle = ''});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
        if (subtitle.isNotEmpty) ...[const SizedBox(height: 4), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF7B8798)))],
      ]);
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  const StatCard({super.key, required this.icon, required this.title, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 20)),
            Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: navy)),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7A8D))),
          ]),
        ),
      );
}

class ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const ActionTile({super.key, required this.icon, required this.title, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: paleBlue, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: blue, size: 23)),
              const SizedBox(height: 9),
              Text(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.35, fontWeight: FontWeight.w700, color: navy)),
            ]),
          ),
        ),
      );
}

class NoticeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String time;
  final VoidCallback? onLongPress;
  const NoticeTile({super.key, required this.icon, required this.title, required this.body, required this.time, this.onLongPress});
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: paleBlue, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: blue)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
                  const SizedBox(height: 5),
                  Text(body, style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF6B7A8D))),
                  const SizedBox(height: 7),
                  Text(time, style: const TextStyle(fontSize: 10, color: blue, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FeatureRow({super.key, required this.icon, required this.title, required this.subtitle, this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: paleBlue, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: blue)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 13)),
          subtitle: subtitle.isEmpty ? null : Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle, style: const TextStyle(fontSize: 11, height: 1.5, color: muted))),
          trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8))),
        ),
      );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = blue});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class EmptyBox extends StatelessWidget {
  final String text;
  const EmptyBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(children: [
          const Icon(Icons.inbox_outlined, size: 44, color: Color(0xFFB6C2D1)),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.6)),
        ]),
      );
}

/// خلفية التطبيق: شعار جامعة الحديدة · كلية التربية زبيد كعلامة مائية هادئة.
class Watermark extends StatelessWidget {
  final Widget child;
  final double opacity;
  final double alignY;
  const Watermark({super.key, required this.child, this.opacity = .07, this.alignY = .1});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: pageBg),
        child: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment(0, alignY),
                child: FractionallySizedBox(
                  widthFactor: .9,
                  child: Opacity(
                    opacity: opacity,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                      child: Image.asset('assets/images/university_logo.png', fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ]),
      );
}

class PageScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? fab;
  final List<Widget>? actions;
  const PageScaffold({super.key, required this.title, required this.body, this.fab, this.actions});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title), actions: actions), body: Watermark(child: body), floatingActionButton: fab);
}

Widget refreshList(Future<void> Function() reload, List<Widget> children) => RefreshIndicator(
      onRefresh: reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 90), physics: const AlwaysScrollableScrollPhysics(), children: children),
    );

class FutureBody<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  const FutureBody({super.key, required this.load, required this.builder});
  @override
  State<FutureBody<T>> createState() => _FutureBodyState<T>();
}

class _FutureBodyState<T> extends State<FutureBody<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 44, color: Color(0xFFB6C2D1)),
                  const SizedBox(height: 10),
                  Text('تعذر تحميل البيانات\n${errText(snap.error!)}', textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.6)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
                ]),
              ),
            );
          }
          return widget.builder(context, snap.data as T, _reload);
        },
      );
}

// ───────────────────────── المقررات (نموذج مشترك) ─────────────────────────

class CourseInfo {
  final String id;
  final String code;
  final String name;
  final String description;
  final String semester;
  final String? teacherId;
  final String teacherName;
  final bool published;
  final double? progress;
  final int enrolled;
  const CourseInfo({required this.id, required this.code, required this.name, required this.description, required this.semester, required this.teacherId, required this.teacherName, required this.published, required this.progress, required this.enrolled});
  Color get color => palette[code.hashCode.abs() % palette.length];
}

/// المقررات المتاحة للمستخدم حسب صلاحيته: الطالب = المسجل بها، المدرس = مقرراته، الإدارة/الرئيس = الكل.
Future<List<CourseInfo>> loadCourses(AppUser u) async {
  final rows = await fetch('courses', orderBy: 'code');
  final people = await profileMap();
  final prog = await fetch('course_progress', cols: 'course_id, completion_percent');
  final enr = await fetch('course_enrollments', cols: 'course_id, student_id');
  final mine = u.role == UserRole.student ? enr.where((e) => e['student_id'] == u.id).map((e) => e['course_id'] as String).toSet() : <String>{};
  final out = <CourseInfo>[];
  for (final c in rows) {
    final id = c['id'] as String;
    if (u.role == UserRole.student && !mine.contains(id)) continue;
    if (u.role == UserRole.teacher && c['teacher_id'] != u.id) continue;
    final ps = prog.where((p) => p['course_id'] == id).map((p) => (p['completion_percent'] as num).toDouble()).toList();
    out.add(CourseInfo(
      id: id,
      code: (c['code'] as String?) ?? '',
      name: (c['name'] as String?) ?? '',
      description: (c['description'] as String?) ?? '',
      semester: (c['semester'] as String?) ?? '',
      teacherId: c['teacher_id'] as String?,
      teacherName: c['teacher_id'] == null ? 'لم يُحدد المدرس' : pname(people, c['teacher_id']),
      published: c['is_published'] == true,
      progress: ps.isEmpty ? null : ps.reduce((a, b) => a + b) / ps.length / 100,
      enrolled: u.role == UserRole.student ? -1 : enr.where((e) => e['course_id'] == id).length,
    ));
  }
  return out;
}

Map<String, String> courseOptions(List<CourseInfo> list, {bool allowNone = false}) => {
      if (allowNone) '': '— بدون مقرر —',
      for (final c in list) c.id: '${c.code} · ${c.name}',
    };

// ───────────────────────── تسجيل الدخول ─────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hidePassword = true;
  bool _busy = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    var hasSession = false;
    try {
      hasSession = isSupabaseConfigured && db.auth.currentUser != null;
    } catch (_) {
      hasSession = false;
    }
    if (hasSession) {
      _restoring = true;
      _restore();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final u = await loadAppUser(db.auth.currentUser!);
      if (!mounted) return;
      _enter(u);
    } catch (_) {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _enter(AppUser u) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(user: u)));
  }

  Future<void> _login() async {
    if (!isSupabaseConfigured) {
      _message('لم يتم إعداد Supabase بعد.');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _message('أدخل البريد الإلكتروني وكلمة المرور');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await db.auth.signInWithPassword(email: email, password: password);
      final user = response.user;
      if (user == null) throw const AuthException('تعذر التحقق من الحساب');
      final u = await loadAppUser(user);
      if (!mounted) return;
      _enter(u);
    } on AuthException catch (e) {
      _message(e.message);
    } on PostgrestException catch (e) {
      _message('تعذر تحميل ملف الحساب: ${e.message}');
    } catch (e) {
      _message('تعذر تسجيل الدخول: ${errText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) => snack(context, text);

  @override
  Widget build(BuildContext context) {
    if (_restoring) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: Watermark(
        opacity: .10,
        alignY: .2,
        child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Image.asset('assets/images/university_logo.png', width: 128, height: 128, fit: BoxFit.contain),
              ),
              const SizedBox(height: 22),
              const Text('المنصة الأكاديمية الرقمية', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 8),
              const Text('إدارة ومتابعة العملية التعليمية', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              const Text('جامعة الحديدة · كلية التربية – زبيد', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF8291A5))),
              const SizedBox(height: 34),
              const Text('تسجيل الدخول', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: navy)),
              const SizedBox(height: 6),
              const Text('استخدم بيانات الحساب الذي أنشأته إدارة الكلية', style: TextStyle(color: Color(0xFF64748B))),
              const SizedBox(height: 22),
              const FieldLabel('البريد الإلكتروني'),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.username, AutofillHints.email], decoration: const InputDecoration(hintText: 'name@example.com', prefixIcon: Icon(Icons.email_outlined))),
              const SizedBox(height: 16),
              const FieldLabel('كلمة المرور'),
              TextField(
                controller: _passwordController,
                obscureText: _hidePassword,
                onSubmitted: (_) => _login(),
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(hintText: 'أدخل كلمة المرور', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => _hidePassword = !_hidePassword), icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login_rounded),
                label: Padding(padding: const EdgeInsets.symmetric(vertical: 15), child: Text(_busy ? 'جارٍ التحقق...' : 'دخول إلى المنصة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                style: FilledButton.styleFrom(backgroundColor: navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: paleBlue, borderRadius: BorderRadius.circular(14)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.security_rounded, color: blue),
                  SizedBox(width: 10),
                  Expanded(child: Text('تسجيل الدخول مرتبط بخدمة Supabase. صلاحية المستخدم تُقرأ من قاعدة البيانات ولا يختارها المستخدم بنفسه.', style: TextStyle(fontSize: 12, height: 1.6, color: navy))),
                ]),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ───────────────────────── الشاشة الرئيسية ─────────────────────────

Widget featurePage(AppUser u, String f) {
  switch (f) {
    case 'ملفات المحاضرات':
    case 'إدارة المحاضرات':
      return LecturesPage(user: u);
    case 'الواجبات والتكليفات':
    case 'إدارة التكليفات':
      return AssignmentsPage(user: u);
    case 'الحضور والغياب':
      return MyAttendancePage(user: u);
    case 'درجاتي':
      return MyGradesPage(user: u);
    case 'نتائج المقررات':
      return MyResultsPage(user: u);
    case 'رصد الدرجات':
      return GradeCoursesPage(user: u);
    case 'التحكم بالنتائج':
      return ResultsControlPage(user: u);
    case 'مركز التعميمات':
      return BroadcastCenterPage(user: u);
    case 'الجدول والتقويم':
      return TimetablePage(user: u);
    case 'نسبة حضوري':
    case 'المعرّضون للحرمان':
      return AttendanceRiskPage(user: u);
    case 'اعتراضات الدرجات':
      return AppealsInboxPage(user: u);
    case 'تقييم المقررات':
      return CourseEvaluationPage(user: u);
    case 'تقييمات مقرراتي':
    case 'نتائج التقييم':
      return EvaluationResultsPage(user: u);
    case 'تسجيل الحضور':
      return AttendanceTakePage(user: u);
    case 'تقدم المقرر':
      return ProgressPage(user: u);
    case 'متابعة الطلاب':
      return StudentsFollowPage(user: u);
    case 'الإعلانات':
      return AnnouncementsPage(user: u);
    case 'الشكاوى والمقترحات':
      return ComplaintsPage(user: u);
    case 'إدارة المستخدمين':
    case 'الصلاحيات':
      return UsersPage(user: u, title: f, canEdit: u.role == UserRole.admin);
    case 'متابعة المدرسين':
      return UsersPage(user: u, title: f, canEdit: false, onlyRole: 'teacher');
    case 'إدارة المقررات':
    case 'متابعة المقررات':
      return CoursesAdminPage(user: u, title: f);
    case 'متابعة الحضور':
      return AttendanceReportPage(user: u);
    default:
      return ReportsPage(user: u, title: f);
  }
}

class HomeScreen extends StatefulWidget {
  final AppUser user;
  const HomeScreen({super.key, required this.user});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(user: widget.user, openFeature: _openFeature),
      CoursesPage(user: widget.user),
      NotificationsPage(user: widget.user),
      ProfilePage(user: widget.user, onLogout: _logout),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/images/university_logo.png', width: 38, height: 38, fit: BoxFit.contain),
          const SizedBox(width: 10),
          const Expanded(child: Text('المنصة الأكاديمية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        ]),
        actions: [IconButton(onPressed: () => setState(() => _tab = 2), icon: const Icon(Icons.notifications_none_rounded)), const SizedBox(width: 6)],
      ),
      body: Watermark(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        backgroundColor: Colors.white,
        indicatorColor: paleBlue,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.menu_book_rounded), label: 'المقررات'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), label: 'الإشعارات'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'حسابي'),
        ],
      ),
    );
  }

  void _openFeature(String feature) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => featurePage(widget.user, feature)));
  }

  Future<void> _logout() async {
    await db.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

// ───────────────────────── الرئيسية (بيانات حقيقية) ─────────────────────────

Future<List<Rec>> loadAnnouncements(AppUser u) async {
  final rows = await fetch('announcements', orderBy: 'published_at', asc: false);
  var mine = <String>{};
  if (u.role == UserRole.student) {
    final enr = await fetch('course_enrollments', cols: 'course_id', eq: {'student_id': u.id});
    mine = enr.map((e) => e['course_id'] as String).toSet();
  }
  return rows.where((a) {
    final aud = a['audience'];
    if (!u.role.isManager) {
      if (aud == 'students' && u.role != UserRole.student) return false;
      if (aud == 'teachers' && u.role != UserRole.teacher) return false;
    }
    final cid = a['course_id'];
    if (cid != null && u.role == UserRole.student && !mine.contains(cid)) return false;
    return true;
  }).toList();
}

typedef StatItem = (IconData, String, String, Color);

class DashData {
  final List<StatItem> stats;
  final List<Rec> notices;
  const DashData(this.stats, this.notices);
}

Future<DashData> loadDash(AppUser u) async {
  const c1 = Color(0xFF1976D2);
  const c2 = Color(0xFF0F9D8A);
  const c3 = Color(0xFFF59E0B);
  const c4 = Color(0xFF8B5CF6);
  final stats = <StatItem>[];
  switch (u.role) {
    case UserRole.student:
      {
        final enr = await fetch('course_enrollments', cols: 'course_id', eq: {'student_id': u.id});
        final att = await fetch('attendance', cols: 'status', eq: {'student_id': u.id});
        final asg = await fetch('assignments', cols: 'id, due_at');
        final subs = await fetch('submissions', cols: 'assignment_id', eq: {'student_id': u.id});
        final done = subs.map((s) => s['assignment_id']).toSet();
        final now = DateTime.now();
        final upcoming = asg.where((a) {
          final d = a['due_at'] == null ? null : DateTime.tryParse(a['due_at'].toString());
          return !done.contains(a['id']) && d != null && d.isAfter(now);
        }).length;
        final good = att.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
        stats.addAll([
          (Icons.menu_book_rounded, 'المقررات', '${enr.length}', c1),
          (Icons.fact_check_outlined, 'نسبة الحضور', att.isEmpty ? '—' : '${(good * 100 / att.length).round()}%', c2),
          (Icons.assignment_outlined, 'تكليفات قادمة', '$upcoming', c3),
          (Icons.task_alt_rounded, 'تكليفات مسلّمة', '${subs.length}', c4),
        ]);
      }
    case UserRole.teacher:
      {
        final courses = await fetch('courses', cols: 'id', eq: {'teacher_id': u.id});
        final ids = courses.map((c) => c['id']).toSet();
        final enr = await fetch('course_enrollments', cols: 'course_id, student_id');
        final att = await fetch('attendance', cols: 'course_id, session_date');
        final asg = await fetch('assignments', cols: 'course_id');
        final students = enr.where((e) => ids.contains(e['course_id'])).map((e) => e['student_id']).toSet().length;
        final sessions = att.where((a) => ids.contains(a['course_id'])).map((a) => '${a['course_id']}|${a['session_date']}').toSet().length;
        final myAsg = asg.where((a) => ids.contains(a['course_id'])).length;
        stats.addAll([
          (Icons.menu_book_rounded, 'مقرراتي', '${courses.length}', c1),
          (Icons.groups_2_outlined, 'الطلاب', '$students', c2),
          (Icons.fact_check_outlined, 'جلسات الحضور', '$sessions', c3),
          (Icons.assignment_outlined, 'التكليفات', '$myAsg', c4),
        ]);
      }
    case UserRole.head:
      {
        final courses = await fetch('courses', cols: 'id');
        final people = await fetch('profiles', cols: 'id, role, is_active');
        final att = await fetch('attendance', cols: 'course_id, session_date');
        final comp = await fetch('complaints', cols: 'status');
        final sessions = att.map((a) => '${a['course_id']}|${a['session_date']}').toSet().length;
        final open = comp.where((c) => c['status'] == 'new' || c['status'] == 'in_review').length;
        stats.addAll([
          (Icons.menu_book_rounded, 'المقررات', '${courses.length}', c1),
          (Icons.groups_2_outlined, 'المدرسون', '${people.where((p) => p['role'] == 'teacher' && p['is_active'] == true).length}', c2),
          (Icons.fact_check_outlined, 'جلسات الحضور', '$sessions', c3),
          (Icons.report_gmailerrorred_rounded, 'شكاوى مفتوحة', '$open', c4),
        ]);
      }
    case UserRole.admin:
      {
        final courses = await fetch('courses', cols: 'id');
        final people = await fetch('profiles', cols: 'id, role');
        final comp = await fetch('complaints', cols: 'status');
        stats.addAll([
          (Icons.menu_book_rounded, 'المقررات', '${courses.length}', c1),
          (Icons.groups_2_outlined, 'المستخدمون', '${people.length}', c2),
          (Icons.school_outlined, 'الطلاب', '${people.where((p) => p['role'] == 'student').length}', c3),
          (Icons.pending_actions_rounded, 'شكاوى جديدة', '${comp.where((c) => c['status'] == 'new').length}', c4),
        ]);
      }
  }
  final notices = (await loadAnnouncements(u)).take(3).toList();
  return DashData(stats, notices);
}

List<(IconData, String)> dashActions(UserRole role) => switch (role) {
      UserRole.student => const [(Icons.library_books_outlined, 'ملفات المحاضرات'), (Icons.assignment_outlined, 'الواجبات والتكليفات'), (Icons.fact_check_outlined, 'الحضور والغياب'), (Icons.grade_outlined, 'درجاتي'), (Icons.workspace_premium_outlined, 'نتائج المقررات'), (Icons.calendar_month_outlined, 'الجدول والتقويم'), (Icons.pie_chart_outline_rounded, 'نسبة حضوري'), (Icons.rate_review_outlined, 'تقييم المقررات'), (Icons.support_agent_rounded, 'الشكاوى والمقترحات'), (Icons.campaign_outlined, 'الإعلانات')],
      UserRole.teacher => const [(Icons.library_books_outlined, 'إدارة المحاضرات'), (Icons.assignment_outlined, 'إدارة التكليفات'), (Icons.fact_check_outlined, 'تسجيل الحضور'), (Icons.edit_note_rounded, 'رصد الدرجات'), (Icons.calendar_month_outlined, 'الجدول والتقويم'), (Icons.warning_amber_rounded, 'المعرّضون للحرمان'), (Icons.gavel_rounded, 'اعتراضات الدرجات'), (Icons.star_outline_rounded, 'تقييمات مقرراتي'), (Icons.trending_up_rounded, 'تقدم المقرر'), (Icons.groups_2_outlined, 'متابعة الطلاب'), (Icons.campaign_outlined, 'الإعلانات')],
      UserRole.head => const [(Icons.menu_book_rounded, 'متابعة المقررات'), (Icons.groups_2_outlined, 'متابعة المدرسين'), (Icons.assessment_outlined, 'تقارير القسم'), (Icons.fact_check_outlined, 'متابعة الحضور'), (Icons.rule_folder_outlined, 'التحكم بالنتائج'), (Icons.send_rounded, 'مركز التعميمات'), (Icons.calendar_month_outlined, 'الجدول والتقويم'), (Icons.warning_amber_rounded, 'المعرّضون للحرمان'), (Icons.gavel_rounded, 'اعتراضات الدرجات'), (Icons.star_outline_rounded, 'نتائج التقييم'), (Icons.support_agent_rounded, 'الشكاوى والمقترحات'), (Icons.campaign_outlined, 'الإعلانات')],
      UserRole.admin => const [(Icons.manage_accounts_outlined, 'إدارة المستخدمين'), (Icons.admin_panel_settings_outlined, 'الصلاحيات'), (Icons.assessment_outlined, 'التقارير العامة'), (Icons.menu_book_rounded, 'إدارة المقررات'), (Icons.rule_folder_outlined, 'التحكم بالنتائج'), (Icons.send_rounded, 'مركز التعميمات'), (Icons.calendar_month_outlined, 'الجدول والتقويم'), (Icons.warning_amber_rounded, 'المعرّضون للحرمان'), (Icons.gavel_rounded, 'اعتراضات الدرجات'), (Icons.star_outline_rounded, 'نتائج التقييم'), (Icons.support_agent_rounded, 'الشكاوى والمقترحات'), (Icons.insights_rounded, 'الإحصائيات')],
    };

class DashboardPage extends StatelessWidget {
  final AppUser user;
  final ValueChanged<String> openFeature;
  const DashboardPage({super.key, required this.user, required this.openFeature});

  @override
  Widget build(BuildContext context) {
    final actions = dashActions(user.role);
    return FutureBody<DashData>(
      load: () => loadDash(user),
      builder: (context, data, reload) => refreshList(reload, [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [navy, Color(0xFF1D4E89)], begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('أهلاً، ${user.name}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)), child: Text(user.role.label, style: const TextStyle(color: Colors.white, fontSize: 12))),
            ]),
            const SizedBox(height: 10),
            Text(user.role.greeting, style: const TextStyle(color: Color(0xFFD8E8FA), fontSize: 14)),
          ]),
        ),
        const SizedBox(height: 24),
        const SectionHeading(title: 'ملخص سريع', subtitle: 'أرقام محدّثة من قاعدة البيانات'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: data.stats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.55),
          itemBuilder: (_, i) => StatCard(icon: data.stats[i].$1, title: data.stats[i].$2, value: data.stats[i].$3, color: data.stats[i].$4),
        ),
        const SizedBox(height: 24),
        const SectionHeading(title: 'الخدمات الأكاديمية', subtitle: 'اختر الخدمة التي تريدها'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .95),
          itemBuilder: (_, i) => ActionTile(icon: actions[i].$1, title: actions[i].$2, onTap: () => openFeature(actions[i].$2)),
        ),
        const SizedBox(height: 24),
        const SectionHeading(title: 'آخر الإعلانات', subtitle: 'مستجدات الكلية والمقررات'),
        const SizedBox(height: 12),
        if (data.notices.isEmpty) const Card(child: EmptyBox('لا توجد إعلانات حتى الآن')),
        for (final a in data.notices) Padding(padding: const EdgeInsets.only(bottom: 10), child: NoticeTile(icon: Icons.campaign_rounded, title: '${a['title']}', body: '${a['body']}', time: fmtDateTime(a['published_at']))),
      ]),
    );
  }
}

// ───────────────────────── المقررات ─────────────────────────

class CoursesPage extends StatelessWidget {
  final AppUser user;
  const CoursesPage({super.key, required this.user});
  @override
  Widget build(BuildContext context) => FutureBody<List<CourseInfo>>(
        load: () => loadCourses(user),
        builder: (context, courses, reload) => refreshList(reload, [
          const SizedBox(height: 10),
          const Text('المقررات الدراسية', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: navy)),
          const SizedBox(height: 7),
          Text(user.role == UserRole.student ? 'المقررات المسجل بها' : user.role == UserRole.teacher ? 'المقررات المسندة إليك' : 'جميع مقررات القسم', style: const TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (courses.isEmpty) Card(child: EmptyBox(user.role == UserRole.student ? 'لم يتم تسجيلك في أي مقرر بعد. تتولى الإدارة تسجيل الطلاب في المقررات.' : 'لا توجد مقررات بعد.')),
          for (final c in courses) Padding(padding: const EdgeInsets.only(bottom: 12), child: CourseCard(course: c, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseDetailsPage(course: c, user: user))))),
        ]),
      );
}

class CourseCard extends StatelessWidget {
  final CourseInfo course;
  final VoidCallback onTap;
  const CourseCard({super.key, required this.course, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = course.progress;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: course.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.menu_book_rounded, color: course.color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(course.name, style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${course.code}  ·  ${course.teacherName}', style: const TextStyle(fontSize: 11, color: muted)),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
            ]),
            const SizedBox(height: 17),
            Row(children: [
              const Expanded(child: Text('إنجاز المقرر', style: TextStyle(fontSize: 12, color: muted))),
              Text(p == null ? 'لم يبدأ التسجيل' : '${(p * 100).round()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: course.color)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: p ?? 0, minHeight: 7, backgroundColor: const Color(0xFFEDF1F6), color: course.color)),
          ]),
        ),
      ),
    );
  }
}

class CourseDetail {
  final List<Rec> lectures;
  final List<Rec> assignments;
  final List<Rec> topics;
  const CourseDetail(this.lectures, this.assignments, this.topics);
}

class CourseDetailsPage extends StatelessWidget {
  final CourseInfo course;
  final AppUser user;
  const CourseDetailsPage({super.key, required this.course, required this.user});

  Future<CourseDetail> _load() async {
    final l = await fetch('lectures', eq: {'course_id': course.id}, orderBy: 'created_at', asc: false);
    final a = await fetch('assignments', eq: {'course_id': course.id}, orderBy: 'created_at', asc: false);
    final t = await fetch('course_progress', eq: {'course_id': course.id}, orderBy: 'updated_at', asc: false);
    return CourseDetail(l, a, t);
  }

  @override
  Widget build(BuildContext context) {
    final p = course.progress;
    return PageScaffold(
      title: 'تفاصيل المقرر',
      body: FutureBody<CourseDetail>(
        load: _load,
        builder: (context, d, reload) => refreshList(reload, [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.code, style: const TextStyle(color: Color(0xFFB9D9FF))),
              const SizedBox(height: 8),
              Text(course.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(course.teacherName, style: const TextStyle(color: Colors.white70)),
              if (course.semester.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('الفصل: ${course.semester}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
              if (course.enrolled >= 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('عدد الطلاب المسجلين: ${course.enrolled}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
              const SizedBox(height: 20),
              LinearProgressIndicator(value: p ?? 0, color: Colors.lightBlueAccent, backgroundColor: Colors.white24, minHeight: 8),
              const SizedBox(height: 8),
              Text(p == null ? 'لم يسجل المدرس تقدم المقرر بعد' : 'نسبة الإنجاز ${(p * 100).round()}%', style: const TextStyle(color: Colors.white)),
            ]),
          ),
          if (course.description.isNotEmpty) ...[const SizedBox(height: 16), Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(course.description, style: const TextStyle(height: 1.7, color: navy))))],
          const SizedBox(height: 22),
          const SectionHeading(title: 'المحاضرات', subtitle: 'المواد التعليمية المنشورة'),
          const SizedBox(height: 12),
          if (d.lectures.isEmpty) const Card(child: EmptyBox('لا توجد محاضرات بعد')),
          for (final l in d.lectures) Padding(padding: const EdgeInsets.only(bottom: 10), child: FeatureRow(icon: Icons.picture_as_pdf_outlined, title: '${l['title']}', subtitle: fmtDate(l['created_at']), onTap: () => showLectureDialog(context, l))),
          const SizedBox(height: 14),
          const SectionHeading(title: 'التكليفات', subtitle: 'الواجبات ومواعيد التسليم'),
          const SizedBox(height: 12),
          if (d.assignments.isEmpty) const Card(child: EmptyBox('لا توجد تكليفات بعد')),
          for (final a in d.assignments) Padding(padding: const EdgeInsets.only(bottom: 10), child: FeatureRow(icon: Icons.assignment_outlined, title: '${a['title']}', subtitle: 'التسليم: ${fmtDate(a['due_at'])} · الدرجة العظمى ${a['max_score']}')),
          const SizedBox(height: 14),
          const SectionHeading(title: 'تقدم المقرر', subtitle: 'الموضوعات التي أنجزها المدرس'),
          const SizedBox(height: 12),
          if (d.topics.isEmpty) const Card(child: EmptyBox('لا توجد موضوعات مسجلة')),
          for (final t in d.topics) Padding(padding: const EdgeInsets.only(bottom: 10), child: FeatureRow(icon: Icons.trending_up_rounded, title: '${t['topic']}', subtitle: '${t['completion_percent']}%${(t['notes'] ?? '').toString().isEmpty ? '' : ' · ${t['notes']}'}')),
        ]),
      ),
    );
  }
}

// ───────────────────────── الإشعارات والحساب ─────────────────────────

class NotificationsPage extends StatelessWidget {
  final AppUser user;
  const NotificationsPage({super.key, required this.user});

  /// إشعارات شخصية (مثل نتيجة الطالب) + إعلانات الكلية، مرتبة من الأحدث.
  Future<List<Rec>> _load() async {
    var personal = <Rec>[];
    try {
      personal = await fetch('notifications', eq: {'user_id': user.id}, orderBy: 'created_at', asc: false);
    } catch (_) {
      personal = <Rec>[];
    }
    final ann = await loadAnnouncements(user);
    final delivered = personal.map((n) => n['ref_id']).where((x) => x != null).toSet();
    final all = <Rec>[
      for (final n in personal) {...n, '_type': 'personal', '_time': n['created_at']},
      for (final a in ann) if (!delivered.contains(a['id'])) {...a, '_type': 'announcement', '_time': a['published_at']},
    ];
    all.sort((a, b) => '${b['_time']}'.compareTo('${a['_time']}'));
    if (personal.any((n) => n['is_read'] == false)) {
      Future<void>(() async {
        try {
          await db.from('notifications').update({'is_read': true}).eq('user_id', user.id).eq('is_read', false);
        } catch (_) {}
      });
    }
    return all;
  }

  @override
  Widget build(BuildContext context) => FutureBody<List<Rec>>(
        load: _load,
        builder: (context, list, reload) => refreshList(reload, [
          const SizedBox(height: 10),
          const Text('الإشعارات', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: navy)),
          const SizedBox(height: 7),
          const Text('إشعاراتك الشخصية وآخر الإعلانات الأكاديمية', style: TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (list.isEmpty) const Card(child: EmptyBox('لا توجد إشعارات حتى الآن')),
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: a['_type'] == 'personal'
                  ? NoticeTile(
                      icon: a['kind'] == 'result' ? Icons.workspace_premium_rounded : (a['kind'] == 'announcement' ? Icons.campaign_rounded : Icons.notifications_active_rounded),
                      title: '${a['title']}${a['is_read'] == false ? '  ●' : ''}',
                      body: '${a['body']}',
                      time: fmtDateTime(a['created_at']),
                    )
                  : NoticeTile(icon: Icons.campaign_rounded, title: '${a['title']}', body: '${a['body']}', time: '${fmtDateTime(a['published_at'])} · ${audienceAr[a['audience']] ?? ''}'),
            ),
        ]),
      );
}

class ProfilePage extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const ProfilePage({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
        const Text('حسابي', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              CircleAvatar(radius: 38, backgroundColor: paleBlue, child: Icon(user.role.icon, color: blue, size: 38)),
              const SizedBox(height: 14),
              Text(user.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 5),
              Text(user.role.label, style: const TextStyle(color: muted)),
              const SizedBox(height: 18),
              const Divider(),
              ProfileInfoRow(label: 'البريد الإلكتروني', value: user.email),
              if ((user.studentNumber ?? '').isNotEmpty) ProfileInfoRow(label: 'الرقم الجامعي', value: user.studentNumber!),
              const ProfileInfoRow(label: 'الجهة التعليمية', value: 'كلية التربية – زبيد'),
              ProfileInfoRow(label: 'نوع الحساب', value: user.role.label),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FeatureRow(icon: Icons.support_agent_rounded, title: 'المساعدة والدعم', subtitle: 'الشكاوى والمقترحات', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintsPage(user: user)))),
        const SizedBox(height: 10),
        FeatureRow(icon: Icons.lock_reset_rounded, title: 'تغيير كلمة المرور', subtitle: 'حدّث كلمة مرور حسابك', onTap: () => changePasswordFlow(context)),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: const Padding(padding: EdgeInsets.all(13), child: Text('تسجيل الخروج')),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB42318), side: const BorderSide(color: Color(0xFFF0C7C4), width: 1.2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ]);
}

class ProfileInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const ProfileInfoRow({super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 13))),
        ]),
      );
}

// ───────────────────────── المحاضرات ─────────────────────────

void showLectureDialog(BuildContext context, Rec l) {
  final link = (l['file_path'] ?? '').toString();
  final desc = (l['description'] ?? '').toString();
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('${l['title']}'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (desc.isNotEmpty) Text(desc, style: const TextStyle(height: 1.7)),
          if (desc.isNotEmpty) const SizedBox(height: 12),
          Text('تاريخ النشر: ${fmtDate(l['created_at'])}', style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 12),
          if (link.isEmpty) const Text('لا يوجد ملف مرفق بهذه المحاضرة.', style: TextStyle(color: muted)) else ...[const Text('رابط الملف:', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), SelectableText(link, style: const TextStyle(color: blue))],
        ]),
      ),
      actions: [
        if (link.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (c.mounted) {
                Navigator.pop(c);
                snack(context, 'تم نسخ الرابط');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('نسخ الرابط'),
          ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
      ],
    ),
  );
}

class LecturesPage extends StatefulWidget {
  final AppUser user;
  const LecturesPage({super.key, required this.user});
  @override
  State<LecturesPage> createState() => _LecturesPageState();
}

class _LecturesPageState extends State<LecturesPage> {
  int _v = 0;
  List<CourseInfo> _courses = [];

  Future<(List<CourseInfo>, List<Rec>)> _load() async {
    final courses = await loadCourses(widget.user);
    _courses = courses;
    final ids = courses.map((c) => c.id).toSet();
    final lec = (await fetch('lectures', orderBy: 'created_at', asc: false)).where((l) => ids.contains(l['course_id'])).toList();
    return (courses, lec);
  }

  Future<void> _add() async {
    if (_courses.isEmpty) {
      snack(context, 'لا توجد مقررات متاحة لإضافة محاضرة إليها');
      return;
    }
    final r = await formDialog(context, 'إضافة محاضرة', [
      FormSpec('course', 'المقرر', kind: FK.dropdown, options: courseOptions(_courses)),
      const FormSpec('title', 'عنوان المحاضرة'),
      const FormSpec('desc', 'الوصف', kind: FK.multiline, required: false),
      const FormSpec('link', 'رابط الملف (Google Drive أو غيره)', required: false),
    ]);
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('lectures').insert({
        'course_id': r['course']!,
        'title': r['title']!,
        'description': nz(r['desc']),
        'file_path': nz(r['link']),
        'published_at': DateTime.now().toUtc().toIso8601String(),
        'created_by': widget.user.id,
      });
    }, ok: 'تمت إضافة المحاضرة');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(Rec l) async {
    if (!await confirmDialog(context, 'حذف المحاضرة "${l['title']}"؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('lectures').delete().eq('id', l['id']);
    }, ok: 'تم حذف المحاضرة');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.role.isStaff;
    return PageScaffold(
      title: staff ? 'إدارة المحاضرات' : 'ملفات المحاضرات',
      fab: staff ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('محاضرة جديدة')) : null,
      body: FutureBody<(List<CourseInfo>, List<Rec>)>(
        key: ValueKey(_v),
        load: _load,
        builder: (context, data, reload) {
          final byId = {for (final c in data.$1) c.id: c};
          return refreshList(reload, [
            if (data.$2.isEmpty) Card(child: EmptyBox(staff ? 'لم تُضف أي محاضرة بعد. اضغط "محاضرة جديدة".' : 'لا توجد محاضرات منشورة في مقرراتك بعد.')),
            for (final l in data.$2)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeatureRow(
                  icon: Icons.picture_as_pdf_outlined,
                  title: '${l['title']}',
                  subtitle: '${byId[l['course_id']]?.code ?? ''} · ${byId[l['course_id']]?.name ?? ''} · ${fmtDate(l['created_at'])}',
                  onTap: () => showLectureDialog(context, l),
                  trailing: staff && (widget.user.role.isManager || l['created_by'] == widget.user.id) ? IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)), onPressed: () => _delete(l)) : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ───────────────────────── التكليفات ─────────────────────────

class AssignmentsPage extends StatefulWidget {
  final AppUser user;
  const AssignmentsPage({super.key, required this.user});
  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AsgData {
  final List<CourseInfo> courses;
  final List<Rec> assignments;
  final List<Rec> submissions;
  const _AsgData(this.courses, this.assignments, this.submissions);
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  int _v = 0;
  List<CourseInfo> _courses = [];

  Future<_AsgData> _load() async {
    final u = widget.user;
    final courses = await loadCourses(u);
    _courses = courses;
    final ids = courses.map((c) => c.id).toSet();
    final asg = (await fetch('assignments', orderBy: 'created_at', asc: false)).where((a) => ids.contains(a['course_id'])).toList();
    final subs = u.role == UserRole.student ? await fetch('submissions', eq: {'student_id': u.id}) : await fetch('submissions', cols: 'id, assignment_id');
    return _AsgData(courses, asg, subs);
  }

  Future<void> _add() async {
    if (_courses.isEmpty) {
      snack(context, 'لا توجد مقررات متاحة لإضافة تكليف إليها');
      return;
    }
    final r = await formDialog(context, 'تكليف جديد', [
      FormSpec('course', 'المقرر', kind: FK.dropdown, options: courseOptions(_courses)),
      const FormSpec('title', 'عنوان التكليف'),
      const FormSpec('instr', 'التعليمات', kind: FK.multiline, required: false),
      const FormSpec('due', 'آخر موعد للتسليم', kind: FK.date, required: false),
      const FormSpec('max', 'الدرجة العظمى', kind: FK.number, initial: '100'),
    ]);
    if (r == null || !mounted) return;
    final due = nz(r['due']);
    final ok = await guarded(context, () async {
      await db.from('assignments').insert({
        'course_id': r['course']!,
        'title': r['title']!,
        'instructions': nz(r['instr']),
        'due_at': due == null ? null : DateTime.parse('${due}T23:59:00').toUtc().toIso8601String(),
        'max_score': num.parse(r['max']!),
        'created_by': widget.user.id,
      });
    }, ok: 'تم إنشاء التكليف');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(Rec a) async {
    if (!await confirmDialog(context, 'حذف التكليف "${a['title']}" مع كل التسليمات المرتبطة به؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('assignments').delete().eq('id', a['id']);
    }, ok: 'تم حذف التكليف');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _openStudent(Rec a, Rec? sub) async {
    if (sub != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${a['title']}'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('تاريخ التسليم: ${fmtDateTime(sub['submitted_at'])}', style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 10),
              const Text('إجابتك:', style: TextStyle(fontWeight: FontWeight.w700)),
              Text((sub['answer_text'] ?? '—').toString(), style: const TextStyle(height: 1.6)),
              if ((sub['file_path'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), SelectableText('الرابط: ${sub['file_path']}', style: const TextStyle(color: blue))],
              const Divider(height: 24),
              Text(sub['score'] == null ? 'لم تُصحح بعد' : 'الدرجة: ${sub['score']} / ${a['max_score']}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
              if ((sub['feedback'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظات المدرس: ${sub['feedback']}', style: const TextStyle(height: 1.6))),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
        ),
      );
      return;
    }
    final r = await formDialog(
      context,
      '${a['title']}',
      const [FormSpec('answer', 'إجابتك', kind: FK.multiline, required: false), FormSpec('link', 'رابط ملف الحل (اختياري)', required: false)],
      okLabel: 'تسليم',
      intro: '${(a['instructions'] ?? 'لا توجد تعليمات إضافية').toString()}\n\nآخر موعد: ${fmtDateTime(a['due_at'])} · الدرجة العظمى: ${a['max_score']}\nلا يمكن تعديل التسليم بعد إرساله.',
    );
    if (r == null || !mounted) return;
    if (nz(r['answer']) == null && nz(r['link']) == null) {
      snack(context, 'اكتب إجابتك أو ضع رابط الحل');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('submissions').insert({'assignment_id': a['id'], 'student_id': widget.user.id, 'answer_text': nz(r['answer']), 'file_path': nz(r['link'])});
    }, ok: 'تم تسليم التكليف');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final staff = u.role.isStaff;
    return PageScaffold(
      title: staff ? 'إدارة التكليفات' : 'الواجبات والتكليفات',
      fab: staff ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('تكليف جديد')) : null,
      body: FutureBody<_AsgData>(
        key: ValueKey(_v),
        load: _load,
        builder: (context, d, reload) {
          final byId = {for (final c in d.courses) c.id: c};
          final now = DateTime.now();
          return refreshList(reload, [
            if (d.assignments.isEmpty) Card(child: EmptyBox(staff ? 'لا توجد تكليفات بعد. اضغط "تكليف جديد".' : 'لا توجد تكليفات في مقرراتك حالياً.')),
            for (final a in d.assignments)
              Builder(builder: (context) {
                final course = byId[a['course_id']];
                final due = a['due_at'] == null ? null : DateTime.tryParse(a['due_at'].toString());
                final sub = d.submissions.where((s) => s['assignment_id'] == a['id']).toList();
                Widget tag;
                if (staff) {
                  tag = Tag('${sub.length} تسليم');
                } else if (sub.isNotEmpty) {
                  tag = Tag(sub.first['score'] == null ? 'تم التسليم' : '${sub.first['score']}/${a['max_score']}', color: const Color(0xFF0F9D8A));
                } else if (due != null && due.isBefore(now)) {
                  tag = const Tag('انتهى الموعد', color: Color(0xFFB42318));
                } else {
                  tag = const Tag('مطلوب', color: Color(0xFFF59E0B));
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FeatureRow(
                    icon: Icons.assignment_outlined,
                    title: '${a['title']}',
                    subtitle: '${course?.code ?? ''} · ${course?.name ?? ''}\nالتسليم: ${fmtDate(a['due_at'])} · الدرجة العظمى ${a['max_score']}',
                    onTap: staff ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SubmissionsPage(user: u, assignment: a))).then((_) => setState(() => _v++)) : () => _openStudent(a, sub.isEmpty ? null : sub.first),
                    trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      tag,
                      if (staff && (u.role.isManager || a['created_by'] == u.id)) InkWell(onTap: () => _delete(a), child: const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFB42318)))),
                    ]),
                  ),
                );
              }),
          ]);
        },
      ),
    );
  }
}

class SubmissionsPage extends StatefulWidget {
  final AppUser user;
  final Rec assignment;
  const SubmissionsPage({super.key, required this.user, required this.assignment});
  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  int _v = 0;

  Future<(List<Rec>, Map<String, Rec>)> _load() async {
    final subs = await fetch('submissions', eq: {'assignment_id': widget.assignment['id'] as Object}, orderBy: 'submitted_at', asc: false);
    return (subs, await profileMap());
  }

  Future<void> _grade(Rec s, String studentName) async {
    final max = widget.assignment['max_score'];
    final r = await formDialog(
      context,
      'تصحيح: $studentName',
      [
        FormSpec('score', 'الدرجة (من $max)', kind: FK.number, initial: s['score']?.toString()),
        FormSpec('feedback', 'ملاحظات للطالب', kind: FK.multiline, required: false, initial: (s['feedback'] ?? '').toString()),
      ],
      intro: 'إجابة الطالب:\n${(s['answer_text'] ?? '—').toString()}${(s['file_path'] ?? '').toString().isEmpty ? '' : '\nالرابط: ${s['file_path']}'}',
    );
    if (r == null || !mounted) return;
    final score = num.parse(r['score']!);
    if (score < 0 || score > (max as num)) {
      snack(context, 'الدرجة يجب أن تكون بين 0 و $max');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('submissions').update({'score': score, 'feedback': nz(r['feedback']), 'graded_by': widget.user.id}).eq('id', s['id']);
    }, ok: 'تم حفظ الدرجة');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: '${widget.assignment['title']}',
        body: FutureBody<(List<Rec>, Map<String, Rec>)>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            if (d.$1.isEmpty) const Card(child: EmptyBox('لم يسلّم أي طالب هذا التكليف بعد')),
            for (final s in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeatureRow(
                  icon: Icons.person_outline_rounded,
                  title: pname(d.$2, s['student_id']),
                  subtitle: 'سُلّم: ${fmtDateTime(s['submitted_at'])}',
                  onTap: () => _grade(s, pname(d.$2, s['student_id'])),
                  trailing: s['score'] == null ? const Tag('بانتظار التصحيح', color: Color(0xFFF59E0B)) : Tag('${s['score']}/${widget.assignment['max_score']}', color: const Color(0xFF0F9D8A)),
                ),
              ),
          ]),
        ),
      );
}

// ───────────────────────── درجاتي ─────────────────────────

class MyGradesPage extends StatelessWidget {
  final AppUser user;
  const MyGradesPage({super.key, required this.user});

  Future<(List<Rec>, List<Rec>)> _load() async {
    final subs = await fetch('submissions', eq: {'student_id': user.id}, orderBy: 'submitted_at', asc: false);
    final asg = await fetch('assignments', cols: 'id, title, max_score');
    return (subs, asg);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'درجاتي',
        body: FutureBody<(List<Rec>, List<Rec>)>(
          load: _load,
          builder: (context, d, reload) {
            final graded = d.$1.where((s) => s['score'] != null).toList();
            double tot = 0, mx = 0;
            for (final s in graded) {
              final a = d.$2.where((x) => x['id'] == s['assignment_id']).toList();
              if (a.isEmpty) continue;
              tot += (s['score'] as num).toDouble();
              mx += (a.first['max_score'] as num).toDouble();
            }
            return refreshList(reload, [
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Icon(Icons.grade_outlined, color: blue), const SizedBox(width: 10), Expanded(child: Text(mx == 0 ? 'لا توجد درجات مصححة بعد' : 'المجموع: ${tot.toStringAsFixed(1)} من ${mx.toStringAsFixed(1)}  (${(tot * 100 / mx).round()}%)', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)))]))),
              const SizedBox(height: 14),
              if (d.$1.isEmpty) const Card(child: EmptyBox('لم تسلّم أي تكليف بعد')),
              for (final s in d.$1)
                Builder(builder: (context) {
                  final a = d.$2.where((x) => x['id'] == s['assignment_id']).toList();
                  final title = a.isEmpty ? 'تكليف' : '${a.first['title']}';
                  final max = a.isEmpty ? '' : ' / ${a.first['max_score']}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FeatureRow(
                      icon: Icons.assignment_turned_in_outlined,
                      title: title,
                      subtitle: '${s['score'] == null ? 'قيد التصحيح' : 'الدرجة: ${s['score']}$max'}${(s['feedback'] ?? '').toString().isEmpty ? '' : '\nملاحظات: ${s['feedback']}'}',
                    ),
                  );
                }),
            ]);
          },
        ),
      );
}

// ───────────────────────── الحضور (للطالب) ─────────────────────────

class MyAttendancePage extends StatelessWidget {
  final AppUser user;
  const MyAttendancePage({super.key, required this.user});

  Future<(List<Rec>, List<CourseInfo>)> _load() async {
    final att = await fetch('attendance', eq: {'student_id': user.id}, orderBy: 'session_date', asc: false);
    return (att, await loadCourses(user));
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'الحضور والغياب',
        body: FutureBody<(List<Rec>, List<CourseInfo>)>(
          load: _load,
          builder: (context, d, reload) {
            final att = d.$1;
            int count(String s) => att.where((a) => a['status'] == s).length;
            final good = count('present') + count('late');
            const colors = {'present': Color(0xFF0F9D8A), 'late': Color(0xFFF59E0B), 'absent': Color(0xFFB42318), 'excused': blue};
            return refreshList(reload, [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(att.isEmpty ? 'لا توجد سجلات حضور بعد' : 'نسبة الحضور: ${(good * 100 / att.length).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 16)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: [for (final k in attendanceAr.keys) Tag('${attendanceAr[k]}: ${count(k)}', color: colors[k]!)]),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              for (final a in att)
                Builder(builder: (context) {
                  final c = d.$2.where((x) => x.id == a['course_id']).toList();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FeatureRow(
                      icon: Icons.event_available_outlined,
                      title: c.isEmpty ? 'مقرر' : c.first.name,
                      subtitle: '${fmtDate(a['session_date'])}${(a['notes'] ?? '').toString().isEmpty ? '' : ' · ${a['notes']}'}',
                      trailing: Tag(attendanceAr[a['status']] ?? '', color: colors[a['status']] ?? blue),
                    ),
                  );
                }),
            ]);
          },
        ),
      );
}

// ───────────────────────── الإعلانات ─────────────────────────

class AnnouncementsPage extends StatefulWidget {
  final AppUser user;
  const AnnouncementsPage({super.key, required this.user});
  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  int _v = 0;

  Future<void> _add() async {
    final ok = await sendBroadcast(context, widget.user);
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(Rec a) async {
    if (!await confirmDialog(context, 'حذف الإعلان "${a['title']}"؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('announcements').delete().eq('id', a['id']);
    }, ok: 'تم حذف الإعلان');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return PageScaffold(
      title: 'الإعلانات',
      fab: u.role.isStaff ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.campaign_outlined), label: const Text('إعلان جديد')) : null,
      body: FutureBody<List<Rec>>(
        key: ValueKey(_v),
        load: () async => sortAnnouncements(await loadAnnouncements(u)),
        builder: (context, list, reload) => refreshList(reload, [
          if (list.isEmpty) const Card(child: EmptyBox('لا توجد إعلانات حتى الآن')),
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: BroadcastCard(
                a: a,
                footer: '${fmtDateTime(a['published_at'])} · ${audienceAr[a['audience']] ?? ''}${u.role.isStaff && (u.role.isManager || a['created_by'] == u.id) ? ' · اضغط مطولاً للحذف' : ''}',
                onLongPress: u.role.isStaff && (u.role.isManager || a['created_by'] == u.id) ? () => _delete(a) : null,
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── الشكاوى والمقترحات ─────────────────────────

class ComplaintsPage extends StatefulWidget {
  final AppUser user;
  const ComplaintsPage({super.key, required this.user});
  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  int _v = 0;
  bool get _manage => widget.user.role.isManager;

  Future<(List<Rec>, Map<String, Rec>)> _load() async {
    final rows = _manage ? await fetch('complaints', orderBy: 'created_at', asc: false) : await fetch('complaints', eq: {'submitted_by': widget.user.id}, orderBy: 'created_at', asc: false);
    return (rows, _manage ? await profileMap() : <String, Rec>{});
  }

  Future<void> _submit() async {
    final r = await formDialog(context, 'شكوى أو مقترح جديد', const [FormSpec('subject', 'الموضوع'), FormSpec('body', 'التفاصيل', kind: FK.multiline)], okLabel: 'إرسال');
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('complaints').insert({'submitted_by': widget.user.id, 'subject': r['subject']!, 'body': r['body']!});
    }, ok: 'تم إرسال شكواك إلى الإدارة');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _open(Rec c, Map<String, Rec> people) async {
    final head = 'من: ${_manage ? pname(people, c['submitted_by']) : 'أنت'}\n${fmtDateTime(c['created_at'])}\n\n${c['body']}';
    if (!_manage) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('${c['subject']}'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(head, style: const TextStyle(height: 1.7)),
              const Divider(height: 24),
              Text('الحالة: ${complaintAr[c['status']] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
              Text((c['response'] ?? '').toString().isEmpty ? 'لم يصل رد بعد' : 'الرد: ${c['response']}', style: const TextStyle(height: 1.7)),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق'))],
        ),
      );
      return;
    }
    final r = await formDialog(
      context,
      '${c['subject']}',
      [
        FormSpec('status', 'الحالة', kind: FK.dropdown, options: complaintAr, initial: c['status'] as String?),
        FormSpec('response', 'الرد على صاحب الشكوى', kind: FK.multiline, required: false, initial: (c['response'] ?? '').toString()),
      ],
      intro: head,
    );
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('complaints').update({'status': r['status']!, 'response': nz(r['response']), 'handled_by': widget.user.id, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', c['id']);
    }, ok: 'تم تحديث الشكوى');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    const colors = {'new': Color(0xFFF59E0B), 'in_review': blue, 'resolved': Color(0xFF0F9D8A), 'closed': muted};
    return PageScaffold(
      title: _manage ? 'إدارة الشكاوى والمقترحات' : 'الشكاوى والمقترحات',
      fab: _manage ? null : FloatingActionButton.extended(onPressed: _submit, icon: const Icon(Icons.add_rounded), label: const Text('شكوى / مقترح')),
      body: FutureBody<(List<Rec>, Map<String, Rec>)>(
        key: ValueKey(_v),
        load: _load,
        builder: (context, d, reload) => refreshList(reload, [
          if (d.$1.isEmpty) Card(child: EmptyBox(_manage ? 'لا توجد شكاوى أو مقترحات واردة' : 'لم ترسل أي شكوى أو مقترح بعد')),
          for (final c in d.$1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FeatureRow(
                icon: Icons.support_agent_rounded,
                title: '${c['subject']}',
                subtitle: '${_manage ? '${pname(d.$2, c['submitted_by'])} · ' : ''}${fmtDate(c['created_at'])}\n${c['body']}',
                onTap: () => _open(c, d.$2),
                trailing: Tag(complaintAr[c['status']] ?? '', color: colors[c['status']] ?? blue),
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── إدارة المستخدمين ─────────────────────────

class UsersPage extends StatefulWidget {
  final AppUser user;
  final String title;
  final bool canEdit;
  final String? onlyRole;
  const UsersPage({super.key, required this.user, required this.title, required this.canEdit, this.onlyRole});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  int _v = 0;
  String _filter = '';
  String _search = '';

  Future<List<Rec>> _load() async {
    final rows = (await profileMap()).values.toList();
    rows.sort((a, b) => '${a['role']}${a['full_name']}'.compareTo('${b['role']}${b['full_name']}'));
    return rows;
  }

  Future<void> _create() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateUserPage()));
    if (mounted) setState(() => _v++);
  }

  Future<void> _changeRole(Rec p) async {
    final r = await formDialog(context, 'تغيير صلاحية ${p['full_name']}', [FormSpec('role', 'الصلاحية', kind: FK.dropdown, options: {for (final x in UserRole.values) x.key: x.label}, initial: p['role'] as String?)]);
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('profiles').update({'role': r['role']!}).eq('id', p['id']);
    }, ok: 'تم تغيير الصلاحية');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _toggle(Rec p) async {
    final active = p['is_active'] == true;
    if (!await confirmDialog(context, active ? 'إيقاف حساب ${p['full_name']}؟ لن يتمكن من الدخول.' : 'إعادة تفعيل حساب ${p['full_name']}؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('profiles').update({'is_active': !active}).eq('id', p['id']);
    }, ok: active ? 'تم إيقاف الحساب' : 'تم تفعيل الحساب');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: widget.title,
        fab: widget.canEdit ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('حساب جديد')) : null,
        body: FutureBody<List<Rec>>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, all, reload) {
            final list = all.where((p) {
              if (widget.onlyRole != null && p['role'] != widget.onlyRole) return false;
              if (_filter.isNotEmpty && p['role'] != _filter) return false;
              if (_search.isNotEmpty) {
                final hay = '${p['full_name']} ${p['email']} ${p['student_number'] ?? ''}'.toLowerCase();
                if (!hay.contains(_search.toLowerCase())) return false;
              }
              return true;
            }).toList();
            return refreshList(reload, [
              TextField(onChanged: (v) => setState(() => _search = v.trim()), decoration: const InputDecoration(hintText: 'بحث بالاسم أو البريد أو الرقم الجامعي', prefixIcon: Icon(Icons.search_rounded))),
              if (widget.onlyRole == null) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text('الكل (${all.length})'), selected: _filter.isEmpty, onSelected: (_) => setState(() => _filter = ''))),
                    for (final r in UserRole.values) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text('${r.label} (${all.where((p) => p['role'] == r.key).length})'), selected: _filter == r.key, onSelected: (_) => setState(() => _filter = r.key))),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              if (list.isEmpty) const Card(child: EmptyBox('لا يوجد مستخدمون مطابقون')),
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FeatureRow(
                    icon: parseRole(p['role'] as String?)?.icon ?? Icons.person_outline_rounded,
                    title: '${p['full_name']}${p['is_active'] == true ? '' : '  (موقوف)'}',
                    subtitle: '${p['email']}${(p['student_number'] ?? '').toString().isEmpty ? '' : ' · ${p['student_number']}'}\n${roleLabel(p['role'] as String?)}',
                    trailing: widget.canEdit && p['id'] != widget.user.id
                        ? PopupMenuButton<String>(
                            onSelected: (v) => v == 'role' ? _changeRole(p) : _toggle(p),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'role', child: Text('تغيير الصلاحية')),
                              PopupMenuItem(value: 'toggle', child: Text(p['is_active'] == true ? 'إيقاف الحساب' : 'تفعيل الحساب')),
                            ],
                          )
                        : (p['id'] == widget.user.id ? const Tag('أنت') : null),
                  ),
                ),
            ]);
          },
        ),
      );
}

class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});
  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _studentNumber = TextEditingController();
  UserRole _role = UserRole.student;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _studentNumber.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.length < 8) {
      snack(context, 'أدخل الاسم والبريد وكلمة مرور لا تقل عن 8 أحرف');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await db.functions.invoke('create-user', body: {
        'full_name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
        'role': _role.key,
        'student_number': _studentNumber.text.trim(),
        'department': 'قسم معلم حاسوب',
      });
      if (response.status < 200 || response.status >= 300) {
        final data = response.data;
        throw Exception(data is Map ? data['error'] ?? 'تعذر إنشاء الحساب' : 'تعذر إنشاء الحساب');
      }
      _name.clear();
      _email.clear();
      _password.clear();
      _studentNumber.clear();
      snack(context, 'تم إنشاء الحساب وإضافته إلى المنصة');
    } on FunctionException catch (e) {
      final d = e.details;
      snack(context, 'تعذر إنشاء الحساب: ${d is Map ? (d['error'] ?? d) : (d ?? e.reasonPhrase ?? 'خطأ بالخدمة')}');
    } catch (e) {
      snack(context, 'تعذر إنشاء الحساب: ${errText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'إنشاء حساب جديد',
        body: ListView(padding: const EdgeInsets.all(18), children: [
          const Text('تنشئ الإدارة حسابات الطلاب والمدرسين ورئيس القسم. الصلاحية تُحفظ في قاعدة البيانات ولا يحددها المستخدم عند تسجيل الدخول.', style: TextStyle(height: 1.6, color: Color(0xFF64748B))),
          const SizedBox(height: 20),
          const FieldLabel('الاسم الكامل'),
          TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline), hintText: 'الاسم كما سيظهر في المنصة')),
          const SizedBox(height: 14),
          const FieldLabel('البريد الإلكتروني'),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(prefixIcon: Icon(Icons.email_outlined), hintText: 'name@example.com')),
          const SizedBox(height: 14),
          const FieldLabel('كلمة المرور الأولية'),
          TextField(controller: _password, obscureText: true, textInputAction: TextInputAction.next, decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline), hintText: '8 أحرف على الأقل')),
          const SizedBox(height: 14),
          const FieldLabel('نوع الحساب'),
          DropdownButtonFormField<UserRole>(value: _role, items: UserRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(), onChanged: _busy ? null : (v) => setState(() => _role = v ?? UserRole.student), decoration: const InputDecoration(prefixIcon: Icon(Icons.badge_outlined))),
          if (_role == UserRole.student) ...[
            const SizedBox(height: 14),
            const FieldLabel('الرقم الجامعي (اختياري)'),
            TextField(controller: _studentNumber, decoration: const InputDecoration(prefixIcon: Icon(Icons.numbers), hintText: 'الرقم الجامعي')),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.person_add_alt_1),
            label: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(_busy ? 'جارٍ إنشاء الحساب...' : 'إنشاء الحساب')),
          ),
        ]),
      );
}

// ───────────────────────── إدارة المقررات ─────────────────────────

class CoursesAdminPage extends StatefulWidget {
  final AppUser user;
  final String title;
  const CoursesAdminPage({super.key, required this.user, required this.title});
  @override
  State<CoursesAdminPage> createState() => _CoursesAdminPageState();
}

class _CoursesAdminPageState extends State<CoursesAdminPage> {
  int _v = 0;
  Map<String, String> _teachers = {'': '— بدون مدرس —'};

  Future<List<CourseInfo>> _load() async {
    final people = (await profileMap()).values.where((p) => p['role'] == 'teacher' && p['is_active'] == true).toList();
    _teachers = {'': '— بدون مدرس —', for (final p in people) p['id'] as String: '${p['full_name']}'};
    return loadCourses(widget.user);
  }

  Future<void> _add() async {
    final r = await formDialog(context, 'مقرر جديد', [
      const FormSpec('code', 'رمز المقرر (فريد)'),
      const FormSpec('name', 'اسم المقرر'),
      const FormSpec('desc', 'الوصف', kind: FK.multiline, required: false),
      const FormSpec('sem', 'الفصل الدراسي', required: false),
      FormSpec('teacher', 'المدرس', kind: FK.dropdown, required: false, options: _teachers, initial: ''),
    ]);
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('courses').insert({'code': r['code']!, 'name': r['name']!, 'description': nz(r['desc']), 'semester': nz(r['sem']), 'teacher_id': nz(r['teacher']), 'is_published': true});
    }, ok: 'تمت إضافة المقرر');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _edit(CourseInfo c) async {
    final r = await formDialog(context, 'تعديل ${c.code}', [
      FormSpec('name', 'اسم المقرر', initial: c.name),
      FormSpec('desc', 'الوصف', kind: FK.multiline, required: false, initial: c.description),
      FormSpec('sem', 'الفصل الدراسي', required: false, initial: c.semester),
      FormSpec('teacher', 'المدرس', kind: FK.dropdown, required: false, options: _teachers, initial: c.teacherId ?? ''),
      FormSpec('pub', 'حالة النشر', kind: FK.dropdown, options: const {'true': 'منشور', 'false': 'مخفي عن الطلاب'}, initial: c.published ? 'true' : 'false'),
    ]);
    if (r == null || !mounted) return;
    final ok = await guarded(context, () async {
      await db.from('courses').update({'name': r['name']!, 'description': nz(r['desc']), 'semester': nz(r['sem']), 'teacher_id': nz(r['teacher']), 'is_published': r['pub'] == 'true'}).eq('id', c.id);
    }, ok: 'تم حفظ التعديلات');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(CourseInfo c) async {
    if (!await confirmDialog(context, 'حذف المقرر "${c.name}" نهائياً مع محاضراته وتكليفاته وسجلات حضوره؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('courses').delete().eq('id', c.id);
    }, ok: 'تم حذف المقرر');
    if (ok && mounted) setState(() => _v++);
  }

  void _menu(CourseInfo c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.visibility_outlined), title: const Text('عرض التفاصيل'), onTap: () { Navigator.pop(sheet); Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseDetailsPage(course: c, user: widget.user))); }),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('تعديل المقرر وتعيين المدرس'), onTap: () { Navigator.pop(sheet); _edit(c); }),
          ListTile(leading: const Icon(Icons.groups_2_outlined), title: const Text('تسجيل الطلاب في المقرر'), onTap: () { Navigator.pop(sheet); Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnrollmentsPage(course: c))).then((_) { if (mounted) setState(() => _v++); }); }),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)), title: const Text('حذف المقرر', style: TextStyle(color: Color(0xFFB42318))), onTap: () { Navigator.pop(sheet); _delete(c); }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: widget.title,
        fab: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('مقرر جديد')),
        body: FutureBody<List<CourseInfo>>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, list, reload) => refreshList(reload, [
            if (list.isEmpty) const Card(child: EmptyBox('لا توجد مقررات بعد. اضغط "مقرر جديد" لإضافة أول مقرر.')),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeatureRow(
                  icon: Icons.menu_book_rounded,
                  title: '${c.code} · ${c.name}',
                  subtitle: '${c.teacherName}\nالطلاب المسجلون: ${c.enrolled}${c.published ? '' : ' · مخفي'}',
                  onTap: () => _menu(c),
                  trailing: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
                ),
              ),
          ]),
        ),
      );
}

class EnrollmentsPage extends StatefulWidget {
  final CourseInfo course;
  const EnrollmentsPage({super.key, required this.course});
  @override
  State<EnrollmentsPage> createState() => _EnrollmentsPageState();
}

class _EnrollmentsPageState extends State<EnrollmentsPage> {
  List<Rec> _students = [];
  Set<String> _enrolled = {};
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await profileMap();
      final enr = await fetch('course_enrollments', cols: 'student_id', eq: {'course_id': widget.course.id});
      final st = people.values.where((p) => p['role'] == 'student' && p['is_active'] == true).toList();
      st.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
      if (!mounted) return;
      setState(() {
        _students = st;
        _enrolled = enr.map((e) => e['student_id'] as String).toSet();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _error = errText(e); _loading = false; });
    }
  }

  Future<void> _toggle(Rec s, bool on) async {
    final id = s['id'] as String;
    final ok = await guarded(context, () async {
      if (on) {
        await db.from('course_enrollments').insert({'course_id': widget.course.id, 'student_id': id});
      } else {
        await db.from('course_enrollments').delete().eq('course_id', widget.course.id).eq('student_id', id);
      }
    });
    if (ok && mounted) setState(() => on ? _enrolled.add(id) : _enrolled.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final list = _students.where((s) => _search.isEmpty || '${s['full_name']} ${s['student_number'] ?? ''}'.toLowerCase().contains(_search.toLowerCase())).toList();
    return PageScaffold(
      title: 'طلاب ${widget.course.code}',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر التحميل\n$_error', textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(18), children: [
                  Text('المسجلون: ${_enrolled.length} من ${_students.length} طالب', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
                  const SizedBox(height: 10),
                  TextField(onChanged: (v) => setState(() => _search = v.trim()), decoration: const InputDecoration(hintText: 'بحث بالاسم أو الرقم الجامعي', prefixIcon: Icon(Icons.search_rounded))),
                  const SizedBox(height: 10),
                  if (_students.isEmpty) const Card(child: EmptyBox('لا يوجد طلاب بعد. أنشئ حسابات الطلاب أولاً من إدارة المستخدمين.')),
                  for (final s in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: CheckboxListTile(
                          value: _enrolled.contains(s['id']),
                          onChanged: (v) => _toggle(s, v == true),
                          title: Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 13)),
                          subtitle: Text((s['student_number'] ?? s['email']).toString(), style: const TextStyle(fontSize: 11, color: muted)),
                        ),
                      ),
                    ),
                ]),
    );
  }
}

// ───────────────────────── تسجيل الحضور (للمدرس) ─────────────────────────

class AttendanceTakePage extends StatefulWidget {
  final AppUser user;
  const AttendanceTakePage({super.key, required this.user});
  @override
  State<AttendanceTakePage> createState() => _AttendanceTakePageState();
}

class _AttendanceTakePageState extends State<AttendanceTakePage> {
  List<CourseInfo> _courses = [];
  String? _courseId;
  DateTime _date = DateTime.now();
  List<Rec> _students = [];
  final Map<String, String> _status = {};
  bool _loading = true;
  bool _saving = false;
  bool _existing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = await loadCourses(widget.user);
      if (!mounted) return;
      setState(() {
        _courses = c;
        _courseId = c.isEmpty ? null : c.first.id;
      });
      await _loadSheet();
    } catch (e) {
      if (mounted) setState(() { _error = errText(e); _loading = false; });
    }
  }

  Future<void> _loadSheet() async {
    if (_courseId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final people = await profileMap();
      final enr = await fetch('course_enrollments', cols: 'student_id', eq: {'course_id': _courseId!});
      final ids = enr.map((e) => e['student_id'] as String).toSet();
      final st = people.values.where((p) => ids.contains(p['id'])).toList();
      st.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
      final old = await fetch('attendance', cols: 'student_id, status', eq: {'course_id': _courseId!, 'session_date': dayKey(_date)});
      if (!mounted) return;
      setState(() {
        _students = st;
        _status.clear();
        for (final s in st) {
          final rec = old.where((o) => o['student_id'] == s['id']).toList();
          _status[s['id'] as String] = rec.isEmpty ? 'present' : rec.first['status'] as String;
        }
        _existing = old.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = errText(e); _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    setState(() => _date = d);
    await _loadSheet();
  }

  Future<void> _save() async {
    if (_students.isEmpty || _courseId == null) return;
    setState(() => _saving = true);
    final rows = [
      for (final s in _students) {'course_id': _courseId, 'student_id': s['id'], 'session_date': dayKey(_date), 'status': _status[s['id']] ?? 'present', 'recorded_by': widget.user.id},
    ];
    final ok = await guarded(context, () async {
      await db.from('attendance').upsert(rows, onConflict: 'course_id,student_id,session_date');
    }, ok: 'تم حفظ سجل الحضور');
    if (mounted) {
      setState(() { _saving = false; if (ok) _existing = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const colors = {'present': Color(0xFF0F9D8A), 'late': Color(0xFFF59E0B), 'absent': Color(0xFFB42318), 'excused': blue};
    return PageScaffold(
      title: 'تسجيل الحضور',
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('تعذر التحميل\n$_error', textAlign: TextAlign.center)))
          : (!_loading && _courses.isEmpty)
              ? const Center(child: EmptyBox('لا توجد مقررات مسندة إليك بعد. تتولى الإدارة إسناد المقررات للمدرسين.'))
              : ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 40), children: [
                  if (_courses.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _courseId,
                      isExpanded: true,
                      items: courseOptions(_courses).entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        setState(() => _courseId = v);
                        _loadSheet();
                      },
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_outlined), label: Padding(padding: const EdgeInsets.all(10), child: Text('تاريخ الجلسة: ${dayKey(_date)}'))),
                  if (_existing) const Padding(padding: EdgeInsets.only(top: 8), child: Text('يوجد سجل محفوظ لهذا اليوم. التعديل سيحدّثه.', style: TextStyle(color: Color(0xFF9A6700), fontSize: 12))),
                  const SizedBox(height: 12),
                  if (_loading) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
                  if (!_loading && _students.isEmpty) const Card(child: EmptyBox('لا يوجد طلاب مسجلون في هذا المقرر بعد')),
                  if (!_loading && _students.isNotEmpty) ...[
                    Row(children: [
                      Expanded(child: Text('${_students.length} طالب', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                      TextButton(onPressed: () => setState(() { for (final s in _students) { _status[s['id'] as String] = 'present'; } }), child: const Text('الكل حاضر')),
                    ]),
                    for (final s in _students)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, children: [
                                for (final k in attendanceAr.keys)
                                  ChoiceChip(
                                    label: Text(attendanceAr[k]!, style: TextStyle(fontSize: 12, color: _status[s['id']] == k ? Colors.white : navy)),
                                    selected: _status[s['id']] == k,
                                    selectedColor: colors[k],
                                    showCheckmark: false,
                                    onSelected: (_) => setState(() => _status[s['id'] as String] = k),
                                  ),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined), label: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ سجل الحضور'))),
                  ],
                ]),
    );
  }
}

// ───────────────────────── متابعة الحضور (رئيس القسم) ─────────────────────────

class AttendanceReportPage extends StatelessWidget {
  final AppUser user;
  const AttendanceReportPage({super.key, required this.user});

  Future<(List<Rec>, List<CourseInfo>, Map<String, Rec>)> _load() async => (await fetch('attendance', cols: 'course_id, student_id, status, session_date'), await loadCourses(user), await profileMap());

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'متابعة الحضور',
        body: FutureBody<(List<Rec>, List<CourseInfo>, Map<String, Rec>)>(
          load: _load,
          builder: (context, d, reload) {
            final att = d.$1;
            final absent = <String, int>{};
            for (final a in att.where((a) => a['status'] == 'absent')) {
              absent[a['student_id'] as String] = (absent[a['student_id']] ?? 0) + 1;
            }
            final top = absent.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            return refreshList(reload, [
              const SectionHeading(title: 'حضور المقررات', subtitle: 'نسبة الحضور = (حاضر + متأخر) ÷ كل السجلات'),
              const SizedBox(height: 12),
              if (d.$2.isEmpty) const Card(child: EmptyBox('لا توجد مقررات')),
              for (final c in d.$2)
                Builder(builder: (context) {
                  final rows = att.where((a) => a['course_id'] == c.id).toList();
                  final sessions = rows.map((a) => a['session_date']).toSet().length;
                  final good = rows.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
                  final rate = rows.isEmpty ? null : good / rows.length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c.code} · ${c.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
                          const SizedBox(height: 4),
                          Text('${c.teacherName} · $sessions جلسة مسجلة', style: const TextStyle(fontSize: 11, color: muted)),
                          const SizedBox(height: 10),
                          Row(children: [const Expanded(child: Text('نسبة الحضور', style: TextStyle(fontSize: 12, color: muted))), Text(rate == null ? 'لا توجد سجلات' : '${(rate * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: c.color))]),
                          const SizedBox(height: 6),
                          ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: rate ?? 0, minHeight: 7, backgroundColor: const Color(0xFFEDF1F6), color: c.color)),
                        ]),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 14),
              const SectionHeading(title: 'الطلاب الأكثر غياباً', subtitle: 'أعلى 10 طلاب بعدد مرات الغياب'),
              const SizedBox(height: 12),
              if (top.isEmpty) const Card(child: EmptyBox('لا توجد غيابات مسجلة')),
              for (final e in top.take(10)) Padding(padding: const EdgeInsets.only(bottom: 8), child: FeatureRow(icon: Icons.person_off_outlined, title: pname(d.$3, e.key), subtitle: '', trailing: Tag('${e.value} غياب', color: const Color(0xFFB42318)))),
            ]);
          },
        ),
      );
}

// ───────────────────────── تقدم المقرر (للمدرس) ─────────────────────────

class ProgressPage extends StatefulWidget {
  final AppUser user;
  const ProgressPage({super.key, required this.user});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  int _v = 0;
  List<CourseInfo> _courses = [];

  Future<(List<CourseInfo>, List<Rec>)> _load() async {
    final courses = await loadCourses(widget.user);
    _courses = courses;
    final ids = courses.map((c) => c.id).toSet();
    final t = (await fetch('course_progress', orderBy: 'updated_at', asc: false)).where((x) => ids.contains(x['course_id'])).toList();
    return (courses, t);
  }

  int? _percent(String s) {
    final n = num.tryParse(s);
    if (n == null || n < 0 || n > 100) return null;
    return n.round();
  }

  Future<void> _add() async {
    if (_courses.isEmpty) {
      snack(context, 'لا توجد مقررات مسندة إليك');
      return;
    }
    final r = await formDialog(context, 'موضوع جديد', [
      FormSpec('course', 'المقرر', kind: FK.dropdown, options: courseOptions(_courses)),
      const FormSpec('topic', 'الموضوع الذي تم شرحه'),
      const FormSpec('pct', 'نسبة الإنجاز (0 - 100)', kind: FK.number, initial: '100'),
      const FormSpec('notes', 'ملاحظات', kind: FK.multiline, required: false),
    ]);
    if (r == null || !mounted) return;
    final pct = _percent(r['pct']!);
    if (pct == null) {
      snack(context, 'النسبة يجب أن تكون بين 0 و 100');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('course_progress').insert({'course_id': r['course']!, 'teacher_id': widget.user.id, 'topic': r['topic']!, 'completion_percent': pct, 'notes': nz(r['notes'])});
    }, ok: 'تم تسجيل الموضوع');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _edit(Rec t) async {
    final r = await formDialog(context, '${t['topic']}', [
      FormSpec('pct', 'نسبة الإنجاز (0 - 100)', kind: FK.number, initial: '${t['completion_percent']}'),
      FormSpec('notes', 'ملاحظات', kind: FK.multiline, required: false, initial: (t['notes'] ?? '').toString()),
    ]);
    if (r == null || !mounted) return;
    final pct = _percent(r['pct']!);
    if (pct == null) {
      snack(context, 'النسبة يجب أن تكون بين 0 و 100');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('course_progress').update({'completion_percent': pct, 'notes': nz(r['notes']), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', t['id']);
    }, ok: 'تم التحديث');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(Rec t) async {
    if (!await confirmDialog(context, 'حذف الموضوع "${t['topic']}"؟')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('course_progress').delete().eq('id', t['id']);
    }, ok: 'تم الحذف');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'تقدم المقرر',
        fab: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('موضوع جديد')),
        body: FutureBody<(List<CourseInfo>, List<Rec>)>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            if (d.$1.isEmpty) const Card(child: EmptyBox('لا توجد مقررات مسندة إليك بعد')),
            for (final c in d.$1) ...[
              Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Row(children: [Expanded(child: SectionHeading(title: '${c.code} · ${c.name}')), Text(c.progress == null ? '—' : '${(c.progress! * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: c.color))])),
              if (d.$2.where((t) => t['course_id'] == c.id).isEmpty) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('لم تسجل أي موضوع بعد', style: TextStyle(color: muted, fontSize: 12))),
              for (final t in d.$2.where((t) => t['course_id'] == c.id))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FeatureRow(
                    icon: Icons.trending_up_rounded,
                    title: '${t['topic']}',
                    subtitle: '${t['completion_percent']}% · ${fmtDate(t['updated_at'])}${(t['notes'] ?? '').toString().isEmpty ? '' : '\n${t['notes']}'}',
                    onTap: () => _edit(t),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB42318)), onPressed: () => _delete(t)),
                  ),
                ),
            ],
          ]),
        ),
      );
}

// ───────────────────────── متابعة الطلاب (للمدرس) ─────────────────────────

class StudentsFollowPage extends StatelessWidget {
  final AppUser user;
  const StudentsFollowPage({super.key, required this.user});

  Future<(List<CourseInfo>, List<Rec>, List<Rec>, Map<String, Rec>)> _load() async => (await loadCourses(user), await fetch('course_enrollments', cols: 'course_id, student_id'), await fetch('attendance', cols: 'course_id, student_id, status'), await profileMap());

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'متابعة الطلاب',
        body: FutureBody<(List<CourseInfo>, List<Rec>, List<Rec>, Map<String, Rec>)>(
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            if (d.$1.isEmpty) const Card(child: EmptyBox('لا توجد مقررات مسندة إليك بعد')),
            for (final c in d.$1)
              Builder(builder: (context) {
                final ids = d.$2.where((e) => e['course_id'] == c.id).map((e) => e['student_id'] as String).toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text('${c.code} · ${c.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 14)),
                      subtitle: Text('${ids.length} طالب', style: const TextStyle(fontSize: 11, color: muted)),
                      children: [
                        if (ids.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('لا يوجد طلاب مسجلون', style: TextStyle(color: muted))),
                        for (final id in ids)
                          Builder(builder: (context) {
                            final rows = d.$3.where((a) => a['course_id'] == c.id && a['student_id'] == id).toList();
                            final good = rows.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
                            final abs = rows.where((a) => a['status'] == 'absent').length;
                            final p = d.$4[id];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline_rounded, color: blue),
                              title: Text(pname(d.$4, id), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              subtitle: Text((p?['student_number'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
                              trailing: Tag(rows.isEmpty ? 'لا سجلات' : 'حضور ${(good * 100 / rows.length).round()}% · غياب $abs', color: rows.isEmpty ? muted : (abs > 2 ? const Color(0xFFB42318) : const Color(0xFF0F9D8A))),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              }),
          ]),
        ),
      );
}

// ───────────────────────── التقارير والإحصائيات ─────────────────────────

class ReportsPage extends StatelessWidget {
  final AppUser user;
  final String title;
  const ReportsPage({super.key, required this.user, required this.title});

  Future<Map<String, List<Rec>>> _load() async => {
        'profiles': await fetch('profiles', cols: 'role, is_active'),
        'courses': await fetch('courses', cols: 'is_published, teacher_id'),
        'enrollments': await fetch('course_enrollments', cols: 'course_id'),
        'lectures': await fetch('lectures', cols: 'id'),
        'assignments': await fetch('assignments', cols: 'id, max_score'),
        'submissions': await fetch('submissions', cols: 'assignment_id, score'),
        'attendance': await fetch('attendance', cols: 'status'),
        'complaints': await fetch('complaints', cols: 'status'),
        'announcements': await fetch('announcements', cols: 'id'),
      };

  Widget _section(String title, List<(String, String)> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(title: title),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                for (final r in rows) ProfileInfoRow(label: r.$1, value: r.$2),
              ]),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: title,
        body: FutureBody<Map<String, List<Rec>>>(
          load: _load,
          builder: (context, d, reload) {
            final people = d['profiles']!;
            int role(String r) => people.where((p) => p['role'] == r).length;
            final courses = d['courses']!;
            final subs = d['submissions']!;
            final asg = d['assignments']!;
            final att = d['attendance']!;
            final comp = d['complaints']!;
            int cnt(List<Rec> l, String k, String v) => l.where((x) => x[k] == v).length;
            double sum = 0;
            int n = 0;
            for (final s in subs.where((s) => s['score'] != null)) {
              final a = asg.where((x) => x['id'] == s['assignment_id']).toList();
              if (a.isEmpty || (a.first['max_score'] as num) == 0) continue;
              sum += (s['score'] as num) / (a.first['max_score'] as num);
              n++;
            }
            final good = cnt(att, 'status', 'present') + cnt(att, 'status', 'late');
            return refreshList(reload, [
              _section('المستخدمون', [
                ('إجمالي الحسابات', '${people.length}'),
                ('الطلاب', '${role('student')}'),
                ('المدرسون', '${role('teacher')}'),
                ('رؤساء الأقسام', '${role('head')}'),
                ('الإدارة', '${role('admin')}'),
                ('حسابات موقوفة', '${people.where((p) => p['is_active'] == false).length}'),
              ]),
              _section('المقررات', [
                ('إجمالي المقررات', '${courses.length}'),
                ('المنشورة', '${courses.where((c) => c['is_published'] == true).length}'),
                ('بدون مدرس', '${courses.where((c) => c['teacher_id'] == null).length}'),
                ('إجمالي تسجيلات الطلاب', '${d['enrollments']!.length}'),
              ]),
              _section('النشاط التعليمي', [
                ('المحاضرات', '${d['lectures']!.length}'),
                ('التكليفات', '${asg.length}'),
                ('التسليمات', '${subs.length}'),
                ('تسليمات مصححة', '${subs.where((s) => s['score'] != null).length}'),
                ('متوسط الدرجات', n == 0 ? '—' : '${(sum * 100 / n).round()}%'),
              ]),
              _section('الحضور', [
                ('إجمالي السجلات', '${att.length}'),
                ('نسبة الحضور العامة', att.isEmpty ? '—' : '${(good * 100 / att.length).round()}%'),
                ('حاضر', '${cnt(att, 'status', 'present')}'),
                ('متأخر', '${cnt(att, 'status', 'late')}'),
                ('غائب', '${cnt(att, 'status', 'absent')}'),
                ('بعذر', '${cnt(att, 'status', 'excused')}'),
              ]),
              _section('الشكاوى والإعلانات', [
                ('شكاوى جديدة', '${cnt(comp, 'status', 'new')}'),
                ('قيد المراجعة', '${cnt(comp, 'status', 'in_review')}'),
                ('تم حلها', '${cnt(comp, 'status', 'resolved')}'),
                ('مغلقة', '${cnt(comp, 'status', 'closed')}'),
                ('الإعلانات المنشورة', '${d['announcements']!.length}'),
              ]),
            ]);
          },
        ),
      );
}