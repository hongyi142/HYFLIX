import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyflix_tv/pages/auth_page.dart';

void main() {
  testWidgets('login fields accept typing right after a tap', (tester) async {
    tester.testTextInput.register();
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));
    await tester.pumpAndSettle();

    final emailField = find.byType(TextFormField).first;
    await tester.tap(emailField);
    await tester.pump();
    await tester.pump();

    tester.testTextInput.enterText('user@example.com');
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.controller.text, 'user@example.com');
  });

  testWidgets('a second tap on a login field also keeps it editable', (tester) async {
    tester.testTextInput.register();
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));
    await tester.pumpAndSettle();

    final emailField = find.byType(TextFormField).first;
    await tester.tap(emailField);
    await tester.pump();
    await tester.pump();
    await tester.tap(emailField);
    await tester.pump();
    await tester.pump();

    tester.testTextInput.enterText('again@example.com');
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.controller.text, 'again@example.com');
  });
}
