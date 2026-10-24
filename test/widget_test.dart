import 'package:academic_platform/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('لا يسمح بتسجيل دخول تجريبي عندما لا تكون إعدادات Supabase موجودة', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AcademicPlatformApp());
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'student@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await tester.tap(find.text('دخول إلى المنصة'));
    await tester.pump();
    if (!isSupabaseConfigured) {
      expect(find.textContaining('لم يتم إعداد Supabase بعد'), findsOneWidget);
    }
  });
}
