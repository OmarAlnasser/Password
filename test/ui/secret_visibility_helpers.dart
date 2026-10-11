import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers for tests that a secret is, or is not, on screen.
///
/// `find.text(secret)` is not enough to say "not shown": it also matches an
/// obscured [EditableText] by its controller. These look at what is really
/// drawn, spoken and put in tooltips. Values in the tests are synthetic.

/// Every string the accessibility tree carries: label, value, hint, tooltip.
/// Needs `tester.ensureSemantics()` to be active.
List<String> semanticStrings(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  expect(
    root,
    isNotNull,
    reason: 'semantics must be enabled: call tester.ensureSemantics()',
  );
  final out = <String>[];
  void visit(SemanticsNode node) {
    final d = node.getSemanticsData();
    out
      ..add(d.label)
      ..add(d.value)
      ..add(d.hint)
      ..add(d.tooltip);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root!);
  return out.where((s) => s.isNotEmpty).toList();
}

/// Text drawn by `Text` / `RichText` widgets (not by editable fields).
Iterable<String> drawnTexts(WidgetTester tester) => [
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(includeSemanticsLabels: false),
];

/// Messages of every tooltip in the tree.
Iterable<String> tooltipMessages(WidgetTester tester) => [
  for (final w in tester.widgetList<Tooltip>(find.byType(Tooltip)))
    w.message ?? w.richMessage?.toPlainText() ?? '',
];

/// The editable fields that hold [secret] (any part of it).
List<EditableText> fieldsHolding(WidgetTester tester, String secret) => [
  for (final w in tester.widgetList<EditableText>(find.byType(EditableText)))
    if (w.controller.text.contains(secret)) w,
];

/// [secret] is nowhere to be read: not drawn, not in an unobscured field, not
/// in a tooltip, not in the accessibility tree. Obscured fields that hold it
/// are fine (that is the masked state).
void expectSecretHidden(WidgetTester tester, String secret) {
  expect(
    drawnTexts(tester).where((t) => t.contains(secret)),
    isEmpty,
    reason: 'drawn as text',
  );
  for (final field in fieldsHolding(tester, secret)) {
    expect(field.obscureText, isTrue, reason: 'a field shows it in clear');
  }
  expect(
    tooltipMessages(tester).where((t) => t.contains(secret)),
    isEmpty,
    reason: 'in a tooltip',
  );
  expect(
    semanticStrings(tester).where((t) => t.contains(secret)),
    isEmpty,
    reason: 'in the accessibility tree',
  );
}

/// [secret] can be read on screen: drawn as text, or in an unobscured field.
void expectSecretShown(WidgetTester tester, String secret) {
  final drawn = drawnTexts(tester).any((t) => t.contains(secret));
  final inField = fieldsHolding(tester, secret).any((f) => !f.obscureText);
  expect(
    drawn || inField,
    isTrue,
    reason: 'neither drawn as text nor in an unobscured field',
  );
}

/// The real [TextField] with this label.
Finder fieldLabelled(String label) => find.widgetWithText(TextField, label);

/// A widget test with the accessibility tree switched on, so that
/// [expectSecretHidden] can look at what a screen reader would hear.
void testWithSemantics(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}
