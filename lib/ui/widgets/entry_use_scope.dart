import 'package:flutter/widgets.dart';

/// Marks a subtree as showing one vault entry, so that copying one of its
/// secrets there (through `copySecretWithToast`) counts as using that entry
/// for the "Recently used" order (`VaultSession.markUsed`).
///
/// The detail view wraps itself in one, so every copy button inside it (the
/// username, the password, the one-time code, an old password) marks the
/// entry without each button having to know which entry it belongs to. It
/// carries only the entry's id, never anything secret.
class EntryUseScope extends InheritedWidget {
  const EntryUseScope({super.key, required this.entryId, required super.child});

  /// The entry whose secrets are shown below.
  final String entryId;

  /// The id of the nearest enclosing scope, or null outside any. Does not
  /// make [context] depend on the scope: it is read on a tap, not in build.
  static String? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EntryUseScope>()?.entryId;

  @override
  bool updateShouldNotify(EntryUseScope oldWidget) =>
      entryId != oldWidget.entryId;
}
