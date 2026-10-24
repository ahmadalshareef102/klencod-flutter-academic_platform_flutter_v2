import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

const categoryAr = {
  'announcement': 'إعلان',
  'circular': 'تعميم',
  'schedule': 'جدول',
  'exam': 'اختبارات',
  'urgent': 'عاجل',
  'event': 'فعالية',
};

IconData categoryIcon(Object? c) {
  switch (c) {
    case 'circular':
      return Icons.description_outlined;
    case 'schedule':
      return Icons.calendar_month_outlined;
    case 'exam':
      return Icons.quiz_outlined;
    case 'urgent':
      return Icons.priority_high_rounded;
    case 'event':
      return Icons.celebration_outlined;
    default:
      return Icons.campaign_rounded;
  }
}

Color categoryColor(Object? c) {
  switch (c) {
    case 'circular':
      return const Color(0xFF6D4AFF);
    case 'schedule':
      return const Color(0xFF0F9D8A);
    case 'exam':
      return const Color(0xFFF59E0B);
    case 'urgent':
      return const Color(0xFFE11D48);
    case 'event':
      return const Color(0xFFDB2777);
    default:
      return blue;
  }
}

String categoryName(Object? c) => categoryAr[c] ?? 'إعلان';

/// ترتيب: المثبّت أولاً ثم الأحدث.
List<Rec> sortAnnouncements(List<Rec> rows) {
  final list = [...rows];
  list.sort((a, b) {
    final pa = a['is_pinned'] == true ? 1 : 0;
    final pb = b['is_pinned'] == true ? 1 : 0;
    if (pa != pb) return pb - pa;
    return '${b['published_at']}'.compareTo('${a['published_at']}');
  });
  return list;
}

/// نموذج إرسال إعلان/تعميم/جدول… ويصل كل مستلم كإشعار شخصي. يعيد true عند النجاح.
Future<bool> sendBroadcast(BuildContext context, AppUser user) async {
  final isTeacher = user.role == UserRole.teacher;
  final courses = await loadCourses(user);
  if (!context.mounted) return false;
  if (isTeacher && courses.isEmpty) {
    snack(context, 'لا توجد مقررات مسندة إليك');
    return false;
  }
  final r = await formDialog(
    context,
    isTeacher ? 'رسالة لطلاب مقرر' : 'إرسال تعميم / إعلان',
    [
      FormSpec('cat', 'النوع', kind: FK.dropdown, options: categoryAr, initial: 'announcement'),
      const FormSpec('title', 'العنوان'),
      const FormSpec('body', 'النص', kind: FK.multiline),
      if (!isTeacher) const FormSpec('aud', 'موجّه إلى', kind: FK.dropdown, options: audienceAr, initial: 'all'),
      FormSpec('course', isTeacher ? 'المقرر' : 'مقرر محدد (اختياري)', kind: FK.dropdown, required: isTeacher, options: courseOptions(courses, allowNone: !isTeacher), initial: ''),
      const FormSpec('link', 'رابط ملف أو جدول (اختياري)', required: false),
      const FormSpec('pin', 'تثبيت أعلى القائمة', kind: FK.dropdown, options: {'0': 'لا', '1': 'نعم، تثبيت'}, initial: '0'),
    ],
    okLabel: 'إرسال',
    intro: 'سيصل الإرسال إلى كل مستلم كإشعار خاص في التطبيق.',
  );
  if (r == null || !context.mounted) return false;
  dynamic sent;
  final ok = await guarded(context, () async {
    sent = await db.rpc('broadcast_announcement', params: {
      'p_title': r['title']!,
      'p_body': r['body']!,
      'p_category': r['cat'] ?? 'announcement',
      'p_audience': isTeacher ? 'students' : (r['aud'] ?? 'all'),
      'p_course': nz(r['course']),
      'p_link': nz(r['link']),
      'p_pinned': r['pin'] == '1',
    });
  });
  if (ok && context.mounted) snack(context, 'تم الإرسال إلى ${sent ?? 0} مستلم');
  return ok;
}

/// بطاقة إعلان موحّدة (النوع + التثبيت + الرابط).
class BroadcastCard extends StatelessWidget {
  final Rec a;
  final String? footer;
  final VoidCallback? onLongPress;
  const BroadcastCard({super.key, required this.a, this.footer, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cat = a['category'];
    final color = categoryColor(cat);
    final link = (a['link_url'] ?? '').toString();
    final pinned = a['is_pinned'] == true;
    return Card(
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(categoryIcon(cat), color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Tag(categoryName(cat), color: color),
                  if (pinned) ...[const SizedBox(width: 6), const Icon(Icons.push_pin_rounded, size: 15, color: Color(0xFFF59E0B))],
                ]),
                const SizedBox(height: 8),
                Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
                const SizedBox(height: 5),
                Text('${a['body']}', style: const TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF6B7A8D))),
                if (link.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) snack(context, 'تم نسخ الرابط، الصقه في المتصفح');
                    },
                    child: Row(children: [
                      const Icon(Icons.link_rounded, size: 16, color: blue),
                      const SizedBox(width: 4),
                      Expanded(child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: blue, fontWeight: FontWeight.w700))),
                      const Icon(Icons.copy_rounded, size: 14, color: blue),
                    ]),
                  ),
                ],
                const SizedBox(height: 8),
                Text(footer ?? fmtDateTime(a['published_at']), style: const TextStyle(fontSize: 10, color: muted, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// مركز التعميمات للإدارة ورئيس القسم: إرسال، تصفية حسب النوع، حذف.
class BroadcastCenterPage extends StatefulWidget {
  final AppUser user;
  const BroadcastCenterPage({super.key, required this.user});
  @override
  State<BroadcastCenterPage> createState() => _BroadcastCenterPageState();
}

class _BroadcastCenterPageState extends State<BroadcastCenterPage> {
  int _v = 0;
  String _filter = 'all';

  Future<void> _add() async {
    final ok = await sendBroadcast(context, widget.user);
    if (ok && mounted) setState(() => _v++);
  }

  Future<void> _delete(Rec a) async {
    if (!await confirmDialog(context, 'حذف \"${a['title']}\"؟ سيُحذف من قائمة الإعلانات لدى الجميع.')) return;
    if (!mounted) return;
    final ok = await guarded(context, () async {
      await db.from('announcements').delete().eq('id', a['id']);
    }, ok: 'تم الحذف');
    if (ok && mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'مركز التعميمات',
      fab: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.send_rounded), label: const Text('إرسال جديد')),
      body: FutureBody<List<Rec>>(
        key: ValueKey(_v),
        load: () async => sortAnnouncements(await loadAnnouncements(widget.user)),
        builder: (context, all, reload) {
          final list = _filter == 'all' ? all : all.where((a) => (a['category'] ?? 'announcement') == _filter).toList();
          return refreshList(reload, [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text('أرسل إعلاناً أو تعميماً أو جدولاً أو موعد اختبارات للطلاب أو المدرسين أو لمقرر محدد. إجمالي المرسل: ${all.length} · المثبّت: ${all.where((a) => a['is_pinned'] == true).length}', style: const TextStyle(color: muted, height: 1.6, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(label: const Text('الكل'), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
              for (final e in categoryAr.entries) ChoiceChip(label: Text(e.value), selected: _filter == e.key, onSelected: (_) => setState(() => _filter = e.key)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty) const Card(child: EmptyBox('لا توجد رسائل في هذا القسم')),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BroadcastCard(
                  a: a,
                  footer: '${fmtDateTime(a['published_at'])} · ${audienceAr[a['audience']] ?? ''} · اضغط مطولاً للحذف',
                  onLongPress: widget.user.role.isManager || a['created_by'] == widget.user.id ? () => _delete(a) : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}
