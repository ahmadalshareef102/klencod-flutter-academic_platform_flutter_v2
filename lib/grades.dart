import 'package:flutter/material.dart';

import 'main.dart';

// ───────────────────────── أدوات الدرجات ─────────────────────────

/// يحوّل النص إلى رقم مع دعم الأرقام العربية والفاصلة العربية.
double? parseNum(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in t.split('')) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '٫' || ch == ',' || ch == '،') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString());
}

String fmtNum(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
}

/// التقدير حسب النسبة المئوية (نفس منطق الدالة grade_label في قاعدة البيانات).
String gradeLabel(double pct) {
  if (pct >= 85) return 'ممتاز';
  if (pct >= 75) return 'جيد جداً';
  if (pct >= 65) return 'جيد';
  if (pct >= 50) return 'مقبول';
  return 'راسب';
}

Color gradeColor(double pct) => pct >= 50 ? const Color(0xFF0F9D8A) : const Color(0xFFE11D48);

class GradeMax {
  final double coursework;
  final double midterm;
  final double finalExam;
  const GradeMax(this.coursework, this.midterm, this.finalExam);
  double get total => coursework + midterm + finalExam;
  static GradeMax fromRow(Rec? c) {
    double g(String k, double d) {
      if (c == null) return d;
      final v = c[k];
      return v is num ? v.toDouble() : d;
    }

    return GradeMax(g('max_coursework', 20), g('max_midterm', 20), g('max_final', 60));
  }
}

class GradeControl {
  final bool entryOpen;
  final bool published;
  const GradeControl(this.entryOpen, this.published);
  static GradeControl fromRow(Rec? r) {
    if (r == null) return const GradeControl(true, false);
    return GradeControl(r['entry_open'] != false, r['is_published'] == true);
  }

  static GradeControl forCourse(List<Rec> rows, String courseId) {
    for (final r in rows) {
      if (r['course_id'] == courseId) return fromRow(r);
    }
    return const GradeControl(true, false);
  }
}

double gradeTotal(Rec g) {
  double v(String k) {
    final x = g[k];
    return x is num ? x.toDouble() : 0;
  }

  return v('coursework') + v('midterm') + v('final_exam');
}

bool gradeComplete(Rec g) => g['coursework'] != null && g['midterm'] != null && g['final_exam'] != null;

Widget controlTag(GradeControl c) {
  if (c.published) return const Tag('منشورة للطلاب', color: Color(0xFF0F9D8A));
  if (!c.entryOpen) return const Tag('الرصد مغلق', color: Color(0xFFF59E0B));
  return const Tag('مفتوح للرصد', color: blue);
}

// ───────────────────────── المدرس: قائمة مقررات الرصد ─────────────────────────

class GradeCoursesPage extends StatelessWidget {
  final AppUser user;
  const GradeCoursesPage({super.key, required this.user});

  Future<(List<CourseInfo>, List<Rec>)> _load() async {
    final courses = await loadCourses(user);
    final ctl = await fetch('grade_control');
    return (courses, ctl);
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'رصد الدرجات',
        body: FutureBody<(List<CourseInfo>, List<Rec>)>(
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('اختر المقرر ثم أدخل أعمال السنة والاختبار النصفي والنهائي لكل طالب. تعتمد الإدارة النتائج وتنشرها للطلاب.', style: TextStyle(color: muted, height: 1.6, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 12),
            if (d.$1.isEmpty) const Card(child: EmptyBox('لا توجد مقررات مسندة إليك')),
            for (final c in d.$1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FeatureRow(
                  icon: Icons.edit_note_rounded,
                  title: '${c.code} · ${c.name}',
                  subtitle: 'الطلاب المسجلون: ${c.enrolled}${c.semester.isEmpty ? '' : ' · ${c.semester}'}',
                  trailing: controlTag(GradeControl.forCourse(d.$2, c.id)),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GradeSheetPage(user: user, course: c)));
                    await reload();
                  },
                ),
              ),
          ]),
        ),
      );
}

// ───────────────────────── كشف الرصد (المدرس + الإدارة) ─────────────────────────

class GradeSheetPage extends StatefulWidget {
  final AppUser user;
  final CourseInfo course;
  const GradeSheetPage({super.key, required this.user, required this.course});
  @override
  State<GradeSheetPage> createState() => _GradeSheetPageState();
}

class _GradeSheetPageState extends State<GradeSheetPage> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  List<Rec> _students = [];
  GradeMax _max = const GradeMax(20, 20, 60);
  GradeControl _ctl = const GradeControl(true, false);
  final Map<String, List<TextEditingController>> _c = {};
  final Set<String> _hadRow = {};
  String _q = '';

  bool get _isManager => widget.user.role.isManager;
  bool get _locked => !_isManager && (!_ctl.entryOpen || _ctl.published);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final list in _c.values) {
      for (final t in list) {
        t.dispose();
      }
    }
    _c.clear();
  }

  String _cell(Rec? r, String k) {
    if (r == null) return '';
    final v = r[k];
    return v is num ? fmtNum(v) : '';
  }

  Future<void> _load() async {
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final id = widget.course.id;
      final enr = await fetch('course_enrollments', cols: 'student_id', eq: {'course_id': id});
      final people = await profileMap();
      final grades = await fetch('course_grades', eq: {'course_id': id});
      final crow = await db.from('courses').select().eq('id', id).maybeSingle();
      final ctl = await fetch('grade_control', eq: {'course_id': id});
      final students = <Rec>[];
      for (final e in enr) {
        final p = people[e['student_id']];
        if (p != null) students.add(p);
      }
      students.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
      _disposeControllers();
      _hadRow.clear();
      for (final s in students) {
        final sid = s['id'] as String;
        Rec? r;
        for (final g in grades) {
          if (g['student_id'] == sid) r = g;
        }
        if (r != null) _hadRow.add(sid);
        _c[sid] = [
          TextEditingController(text: _cell(r, 'coursework')),
          TextEditingController(text: _cell(r, 'midterm')),
          TextEditingController(text: _cell(r, 'final_exam')),
        ];
      }
      if (!mounted) return;
      setState(() {
        _students = students;
        _max = GradeMax.fromRow(crow);
        _ctl = GradeControl.fromRow(ctl.isEmpty ? null : ctl.first);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final limits = [_max.coursework, _max.midterm, _max.finalExam];
    const names = ['أعمال السنة', 'الاختبار النصفي', 'الاختبار النهائي'];
    final rows = <Map<String, dynamic>>[];
    for (final s in _students) {
      final sid = s['id'] as String;
      final t = _c[sid]!;
      final vals = <double?>[];
      for (var i = 0; i < 3; i++) {
        final txt = t[i].text.trim();
        final v = parseNum(txt);
        if (txt.isNotEmpty && v == null) {
          snack(context, 'قيمة غير صالحة في ${names[i]} للطالب ${s['full_name']}');
          return;
        }
        if (v != null && (v < 0 || v > limits[i])) {
          snack(context, '${names[i]} للطالب ${s['full_name']} يجب أن تكون بين 0 و ${fmtNum(limits[i])}');
          return;
        }
        vals.add(v);
      }
      final any = vals.any((v) => v != null);
      if (!any && !_hadRow.contains(sid)) continue;
      rows.add({'course_id': widget.course.id, 'student_id': sid, 'coursework': vals[0], 'midterm': vals[1], 'final_exam': vals[2]});
    }
    if (rows.isEmpty) {
      snack(context, 'لم تُدخل أي درجات بعد');
      return;
    }
    setState(() => _saving = true);
    final ok = await guarded(context, () async {
      await db.from('course_grades').upsert(rows, onConflict: 'course_id,student_id');
    }, ok: 'تم حفظ درجات ${rows.length} طالب');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      for (final r in rows) {
        _hadRow.add(r['student_id'] as String);
      }
    }
  }

  double _studentTotal(String sid) {
    double sum = 0;
    for (final t in _c[sid]!) {
      sum += parseNum(t.text) ?? 0;
    }
    return sum;
  }

  Widget _scoreField(String sid, int i, String label, double max) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextField(
          controller: _c[sid]![i],
          enabled: !_locked,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: '$label / ${fmtNum(max)}', labelStyle: const TextStyle(fontSize: 11), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: Color(0xFFB6C2D1)),
            const SizedBox(height: 10),
            Text('تعذر تحميل كشف الدرجات\n${errText(_error!)}\nتأكد من تنفيذ ملف supabase/grades_patch.sql', textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.6)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
          ]),
        ),
      );
    } else {
      final shown = _students.where((s) => _q.isEmpty || '${s['full_name']} ${s['student_number'] ?? ''}'.contains(_q)).toList();
      body = ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('الدرجة الكاملة: ${fmtNum(_max.total)}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                  controlTag(_ctl),
                ]),
                const SizedBox(height: 6),
                Text('أعمال السنة ${fmtNum(_max.coursework)} · النصفي ${fmtNum(_max.midterm)} · النهائي ${fmtNum(_max.finalExam)}', style: const TextStyle(fontSize: 12, color: muted)),
                if (_locked) ...[
                  const SizedBox(height: 8),
                  Text(_ctl.published ? 'تم اعتماد ونشر النتائج، ولا يمكن التعديل إلا من الإدارة.' : 'أغلقت الإدارة الرصد لهذا المقرر.', style: const TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
                ] else if (_isManager && _ctl.published) ...[
                  const SizedBox(height: 8),
                  const Text('النتائج منشورة بالفعل؛ بعد أي تعديل أعد النشر من «التحكم بالنتائج» ليصل الطلاب التحديث.', style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          TextField(onChanged: (v) => setState(() => _q = v.trim()), decoration: const InputDecoration(hintText: 'بحث باسم الطالب أو رقمه', prefixIcon: Icon(Icons.search_rounded))),
          const SizedBox(height: 10),
          if (_students.isEmpty) const Card(child: EmptyBox('لا يوجد طلاب مسجلون في هذا المقرر بعد')),
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${s['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 13))),
                      Builder(builder: (context) {
                        final tot = _studentTotal(s['id'] as String);
                        final pct = _max.total == 0 ? 0.0 : tot * 100 / _max.total;
                        return Tag('${fmtNum(tot)} · ${gradeLabel(pct)}', color: gradeColor(pct));
                      }),
                    ]),
                    if ((s['student_number'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('الرقم الجامعي: ${s['student_number']}', style: const TextStyle(fontSize: 11, color: muted))),
                    const SizedBox(height: 10),
                    Row(children: [
                      _scoreField(s['id'] as String, 0, 'أعمال السنة', _max.coursework),
                      _scoreField(s['id'] as String, 1, 'النصفي', _max.midterm),
                      _scoreField(s['id'] as String, 2, 'النهائي', _max.finalExam),
                    ]),
                  ]),
                ),
              ),
            ),
        ],
      );
    }
    return PageScaffold(
      title: '${widget.course.code} · ${widget.course.name}',
      fab: (_loading || _error != null || _locked || _students.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الدرجات'),
            ),
      body: body,
    );
  }
}

// ───────────────────────── الطالب: نتائج المقررات ─────────────────────────

class MyResultsPage extends StatelessWidget {
  final AppUser user;
  const MyResultsPage({super.key, required this.user});

  Future<(List<Rec>, List<CourseInfo>, List<Rec>)> _load() async {
    final grades = await fetch('course_grades', eq: {'student_id': user.id});
    final courses = await loadCourses(user);
    final maxes = await fetch('courses', cols: 'id, max_coursework, max_midterm, max_final');
    return (grades, courses, maxes);
  }

  Widget _box(String label, num? v, double max) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: paleBlue, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(fmtNum(v), style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 16)),
            const SizedBox(height: 2),
            Text('$label / ${fmtNum(max)}', style: const TextStyle(fontSize: 10, color: muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'نتائج المقررات',
        body: FutureBody<(List<Rec>, List<CourseInfo>, List<Rec>)>(
          load: _load,
          builder: (context, d, reload) {
            final items = <Widget>[];
            double sumPct = 0;
            for (final g in d.$1) {
              CourseInfo? course;
              for (final c in d.$2) {
                if (c.id == g['course_id']) course = c;
              }
              Rec? mrow;
              for (final m in d.$3) {
                if (m['id'] == g['course_id']) mrow = m;
              }
              final mx = GradeMax.fromRow(mrow);
              final total = gradeTotal(g);
              final pct = mx.total == 0 ? 0.0 : total * 100 / mx.total;
              sumPct += pct;
              items.add(Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(course == null ? 'مقرر' : '${course.code} · ${course.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                        Tag(gradeLabel(pct), color: gradeColor(pct)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _box('أعمال السنة', g['coursework'] as num?, mx.coursework),
                        _box('النصفي', g['midterm'] as num?, mx.midterm),
                        _box('النهائي', g['final_exam'] as num?, mx.finalExam),
                      ]),
                      const SizedBox(height: 12),
                      Text('المجموع: ${fmtNum(total)} من ${fmtNum(mx.total)}  (${pct.round()}%)', style: const TextStyle(fontWeight: FontWeight.w700, color: navy, fontSize: 13)),
                      const SizedBox(height: 8),
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (pct / 100).clamp(0.0, 1.0), minHeight: 8, color: gradeColor(pct), backgroundColor: const Color(0xFFE5ECF5))),
                    ]),
                  ),
                ),
              ));
            }
            return refreshList(reload, [
              if (d.$1.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const Icon(Icons.workspace_premium_outlined, color: blue),
                        const SizedBox(width: 10),
                        Expanded(child: Text('نتائج معلنة: ${d.$1.length} مقرر · المعدل العام ${(sumPct / d.$1.length).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
                      ]),
                    ),
                  ),
                ),
              if (d.$1.isEmpty) const Card(child: EmptyBox('لم تُعلن نتائج أي مقرر بعد.\nستصلك نتيجتك في الإشعارات فور اعتمادها من الإدارة.')),
              ...items,
            ]);
          },
        ),
      );
}

// ───────────────────────── الإدارة: التحكم بالنتائج ─────────────────────────

class _ControlData {
  final List<CourseInfo> courses;
  final List<Rec> control;
  final List<Rec> grades;
  final List<Rec> maxes;
  const _ControlData(this.courses, this.control, this.grades, this.maxes);
}

class ResultsControlPage extends StatefulWidget {
  final AppUser user;
  const ResultsControlPage({super.key, required this.user});
  @override
  State<ResultsControlPage> createState() => _ResultsControlPageState();
}

class _ResultsControlPageState extends State<ResultsControlPage> {
  int _v = 0;

  Future<_ControlData> _load() async {
    final courses = await loadCourses(widget.user);
    final control = await fetch('grade_control');
    final grades = await fetch('course_grades', cols: 'course_id, student_id, coursework, midterm, final_exam');
    final maxes = await fetch('courses', cols: 'id, max_coursework, max_midterm, max_final');
    return _ControlData(courses, control, grades, maxes);
  }

  Future<void> _toggleEntry(CourseInfo c, bool open) async {
    final ok = await guarded(context, () async {
      await db.from('grade_control').upsert({'course_id': c.id, 'entry_open': open, 'updated_by': widget.user.id}, onConflict: 'course_id');
    }, ok: open ? 'تم فتح الرصد للمدرس' : 'تم إغلاق الرصد');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _publish(CourseInfo c, int complete) async {
    final missing = c.enrolled - complete;
    final msg = 'سيتم اعتماد نتائج «${c.name}» ونشرها للطلاب، وإرسال نتيجة كل طالب في إشعار خاص به.'
        '${missing > 0 ? '\n\nتنبيه: $missing طالب لم تكتمل درجاتهم (ستظهر «—» للدرجة الناقصة).' : ''}\n\nهل تريد المتابعة؟';
    if (!await confirmDialog(context, msg)) return;
    if (!mounted) return;
    dynamic sent;
    final ok = await guarded(context, () async {
      sent = await db.rpc('set_results_published', params: {'p_course': c.id, 'p_publish': true});
    });
    if (!mounted) return;
    if (ok) {
      snack(context, 'تم نشر النتائج وإرسال ${sent ?? 0} إشعار للطلاب');
      setState(() => _v++);
    }
  }

  Future<void> _unpublish(CourseInfo c) async {
    if (!await confirmDialog(context, 'إلغاء نشر نتائج «${c.name}»؟ ستختفي النتائج من حسابات الطلاب وتُحذف إشعارات النتيجة، ويُفتح الرصد من جديد.')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.rpc('set_results_published', params: {'p_course': c.id, 'p_publish': false});
    }, ok: 'تم إلغاء النشر');
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _editMax(CourseInfo c, GradeMax m) async {
    final r = await formDialog(context, 'الدرجات العظمى: ${c.code}', [
      FormSpec('cw', 'أعمال السنة', kind: FK.number, initial: fmtNum(m.coursework)),
      FormSpec('mid', 'الاختبار النصفي', kind: FK.number, initial: fmtNum(m.midterm)),
      FormSpec('fin', 'الاختبار النهائي', kind: FK.number, initial: fmtNum(m.finalExam)),
    ]);
    if (r == null || !mounted) return;
    final cw = parseNum(r['cw']);
    final mid = parseNum(r['mid']);
    final fin = parseNum(r['fin']);
    if (cw == null || mid == null || fin == null || cw < 0 || mid < 0 || fin < 0 || cw > 999 || mid > 999 || fin > 999) {
      snack(context, 'أدخل قيماً صحيحة (من 0 إلى 999)');
      return;
    }
    final ok = await guarded(context, () async {
      await db.from('courses').update({'max_coursework': cw, 'max_midterm': mid, 'max_final': fin}).eq('id', c.id);
    }, ok: 'تم حفظ الدرجات العظمى');
    if (ok && mounted) setState(() => _v++);
  }

  Widget _card(_ControlData d, CourseInfo c) {
    final ctl = GradeControl.forCourse(d.control, c.id);
    final rows = d.grades.where((g) => g['course_id'] == c.id).toList();
    Rec? mrow;
    for (final m in d.maxes) {
      if (m['id'] == c.id) mrow = m;
    }
    final mx = GradeMax.fromRow(mrow);
    final complete = rows.where(gradeComplete).length;
    String stats = '';
    if (rows.isNotEmpty && mx.total > 0) {
      final pcts = rows.map((g) => gradeTotal(g) * 100 / mx.total).toList();
      final avg = pcts.reduce((a, b) => a + b) / pcts.length;
      final pass = pcts.where((p) => p >= 50).length * 100 / pcts.length;
      stats = '\nالمتوسط ${avg.round()}% · نسبة النجاح ${pass.round()}%';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${c.code} · ${c.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy))),
              controlTag(ctl),
            ]),
            const SizedBox(height: 6),
            Text('المدرس: ${c.teacherName}\nالمسجلون: ${c.enrolled} · اكتملت درجاتهم: $complete$stats', style: const TextStyle(fontSize: 12, height: 1.6, color: muted)),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('السماح للمدرس بالرصد', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: navy)),
              value: ctl.entryOpen && !ctl.published,
              onChanged: ctl.published ? null : (v) => _toggleEntry(c, v),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GradeSheetPage(user: widget.user, course: c)));
                  if (mounted) setState(() => _v++);
                },
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('كشف الدرجات'),
              ),
              if (!ctl.published) OutlinedButton.icon(onPressed: () => _editMax(c, mx), icon: const Icon(Icons.tune_rounded, size: 18), label: const Text('الدرجات العظمى')),
              if (!ctl.published)
                FilledButton.icon(onPressed: rows.isEmpty ? null : () => _publish(c, complete), icon: const Icon(Icons.send_rounded, size: 18), label: const Text('اعتماد ونشر النتائج'))
              else
                FilledButton.tonalIcon(onPressed: () => _unpublish(c), icon: const Icon(Icons.undo_rounded, size: 18), label: const Text('إلغاء النشر')),
              if (ctl.published)
                OutlinedButton.icon(onPressed: () => _publish(c, complete), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('إعادة الإرسال')),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'التحكم بالنتائج',
        body: FutureBody<_ControlData>(
          key: ValueKey(_v),
          load: _load,
          builder: (context, d, reload) => refreshList(reload, [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('تحكّم بفتح الرصد للمدرسين، راجع كشف الدرجات، ثم اعتمد ونشر النتيجة؛ يصل كل طالب إشعار بنتيجته الخاصة.', style: TextStyle(color: muted, height: 1.6, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 12),
            if (d.courses.isEmpty) const Card(child: EmptyBox('لا توجد مقررات بعد')),
            for (final c in d.courses) _card(d, c),
          ]),
        ),
      );
}
