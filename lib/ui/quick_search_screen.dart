import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../data/models/vault_entry.dart';
import 'app_scope.dart';
import 'entry_detail_screen.dart';
import 'home_screen.dart';
import 'theme/tokens.dart';
import 'widgets/brand_mark.dart';
import 'widgets/secret_text.dart';
import 'widgets/site_icon.dart';

/// Windows global-hotkey popup, laid out as a command palette: type to filter,
/// Enter copies the password of the highlighted match (Shift+Enter copies the
/// username), the arrow keys move the highlight, Esc hides the window.
class QuickSearchScreen extends StatefulWidget {
  const QuickSearchScreen({super.key});

  @override
  State<QuickSearchScreen> createState() => _QuickSearchScreenState();
}

class _QuickSearchScreenState extends State<QuickSearchScreen> {
  final _q = TextEditingController();
  final _selectedKey = GlobalKey();
  int _selected = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Moves the highlight by [delta] rows (wrapping) and scrolls it into view.
  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedKey.currentContext;
      if (mounted && row != null) {
        Scrollable.ensureVisible(
          row,
          duration: context.motion(AppMotion.fast),
          curve: AppMotion.standard,
        );
      }
    });
  }

  Future<void> _close() async {
    if (mounted) Navigator.of(context).maybePop();
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final items = context.services.session.entries
        .where((e) => e.matches(_q.text.trim()))
        .take(8)
        .toList();
    if (_selected >= items.length) _selected = 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, items.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(items.length - 1, items.length),
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => Align(
              alignment: const Alignment(0, -0.4),
              child: ConstrainedBox(
                // The card never grows past the window: the list scrolls.
                constraints: BoxConstraints(
                  maxWidth: AppLayout.dialog + 32,
                  maxHeight: math.max(0, c.maxHeight - 32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: t.dialogGradient,
                      borderRadius: AppRadius.dialogAll,
                      border: Border.all(color: t.dialogBorder),
                      boxShadow: t.dialogShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.dialogAll,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              18,
                              14,
                              8,
                              0,
                            ),
                            child: Row(
                              children: [
                                const BrandMark(size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      l.quickSearch,
                                      style: tt.labelMedium!.copyWith(
                                        color: t.accent2,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: l.close,
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: _close,
                                ),
                              ],
                            ),
                          ),
                          _SearchInput(
                            controller: _q,
                            onChanged: () => setState(() => _selected = 0),
                            onSubmit: () async {
                              if (items.isEmpty) return;
                              final e = items[_selected];
                              final shift =
                                  HardwareKeyboard.instance.isShiftPressed;
                              await copySecretWithToast(
                                context,
                                shift ? e.username : e.password,
                              );
                              await _close();
                            },
                          ),
                          Divider(height: 1, thickness: 1, color: t.line),
                          if (items.isEmpty)
                            _NoMatches(vaultEmpty: _q.text.trim().isEmpty)
                          else
                            Flexible(
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(8),
                                children: [
                                  for (var i = 0; i < items.length; i++)
                                    _ResultRow(
                                      key: i == _selected ? _selectedKey : null,
                                      entry: items[i],
                                      selected: i == _selected,
                                      onHover: () =>
                                          setState(() => _selected = i),
                                      onTap: () async {
                                        await copySecretWithToast(
                                          context,
                                          items[i].password,
                                        );
                                        await _close();
                                      },
                                    ),
                                ],
                              ),
                            ),
                          Divider(height: 1, thickness: 1, color: t.line),
                          _Hints(
                            passwordLabel: l.password,
                            usernameLabel: l.username,
                            closeLabel: l.close,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big borderless field at the top of the palette.
class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    const none = InputBorder.none;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.go,
        style: tt.titleLarge!.copyWith(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: l.search,
          hintStyle: tt.titleLarge!.copyWith(
            fontWeight: FontWeight.w400,
            color: t.muted,
          ),
          filled: false,
          border: none,
          enabledBorder: none,
          focusedBorder: none,
          disabledBorder: none,
          errorBorder: none,
          focusedErrorBorder: none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: t.accent2, size: 26),
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

/// One match: icon, name and username. The highlighted one says which key
/// copies what.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final VaultEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final e = entry;
    final name = e.title.isEmpty ? e.host : e.title;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!selected) onHover();
        },
        child: AnimatedContainer(
          duration: context.motion(AppMotion.fast),
          curve: AppMotion.standard,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: selected ? t.selected : Colors.transparent,
            borderRadius: AppRadius.controlAll,
            border: Border.all(
              color: selected ? t.selectedBorder : Colors.transparent,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadius.controlAll,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 12, 8),
                child: Row(
                  children: [
                    SiteIcon(
                      url: e.url,
                      title: name,
                      size: 38,
                      selected: selected,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EntryTitle(name, style: tt.titleMedium),
                          if (e.username.isNotEmpty) LtrText(e.username),
                        ],
                      ),
                    ),
                    if (selected)
                      const _KeyCap.icon(Icons.keyboard_return_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.vaultEmpty});

  /// The field is empty, so the vault itself has nothing in it.
  final bool vaultEmpty;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            vaultEmpty ? Icons.lock_outline_rounded : Icons.search_off_rounded,
            size: 30,
            color: t.muted,
          ),
          const SizedBox(height: 10),
          Text(
            l.noEntries,
            textAlign: TextAlign.center,
            style: tt.bodyMedium!.copyWith(color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// The footer: which key does what.
class _Hints extends StatelessWidget {
  const _Hints({
    required this.passwordLabel,
    required this.usernameLabel,
    required this.closeLabel,
  });

  final String passwordLabel;
  final String usernameLabel;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    Widget hint(List<Widget> keys, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Keys read left to right ("Shift", then Enter) in Arabic too.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisSize: MainAxisSize.min, children: keys),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall!.copyWith(color: t.muted),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          hint([
            const _KeyCap.icon(Icons.keyboard_return_rounded),
          ], passwordLabel),
          hint([
            const _KeyCap.text('Shift'),
            const SizedBox(width: 4),
            const _KeyCap.icon(Icons.keyboard_return_rounded),
          ], usernameLabel),
          hint([const _KeyCap.text('Esc')], closeLabel),
        ],
      ),
    );
  }
}

/// A key on a keyboard, drawn as a small rounded cap. Key names are not
/// translated: they are what is printed on the keys.
class _KeyCap extends StatelessWidget {
  const _KeyCap.text(String this.label) : icon = null;
  const _KeyCap.icon(IconData this.icon) : label = null;

  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: t.line2),
        ),
        child: label != null
            ? Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  label!,
                  style: tt.bodySmall!.copyWith(
                    color: t.soft,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              )
            : Icon(icon, size: 15, color: t.soft),
      ),
    );
  }
}
