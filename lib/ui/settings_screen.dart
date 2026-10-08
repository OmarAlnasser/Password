import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../services/import_export.dart';
import '../services/settings.dart';
import '../services/sync/sync_service.dart';
import '../services/update/app_version.dart';
import 'app_scope.dart';
import 'import/import_review_screen.dart';
import 'sign_in_screen.dart';
import 'theme/theme.dart';
import 'update/update.dart';
import 'widgets/brand_mark.dart';
import 'widgets/focus_ring.dart';
import 'widgets/glass_bar.dart';
import 'widgets/icon_tile.dart';
import 'widgets/max_width_body.dart';
import 'widgets/pill_chip.dart';
import 'widgets/primary_button.dart';
import 'widgets/pulse_dot.dart';
import 'widgets/reveal.dart';
import 'widgets/section_header.dart';
import 'widgets/surface_card.dart';
import 'widgets/sync_deletion_prompt.dart';

/// Settings in five groups, each a card of rows: appearance, security, sync,
/// data and about. Choices of two or three are pills on the row; longer lists
/// are a pill that opens a menu. On a wide window the groups sit in two
/// columns.
///
/// The About group holds the app name and the updater's rows
/// (`UpdateSettingsTile`, `AboutVersionTile`, see `lib/ui/update/`).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, if (s.sync != null) s.sync]),
      builder: (context, _) {
        final st = s.settings;
        final x = _Txt.of(context);
        final wide = MediaQuery.sizeOf(context).width >= AppLayout.expanded;
        final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

        final appearance = _Group(
          title: x.appearance,
          children: [
            _ChoiceRow<ThemeMode>(
              icon: Icons.palette_outlined,
              title: l.theme,
              value: st.themeMode,
              options: [
                _Choice(ThemeMode.system, l.themeSystem),
                _Choice(ThemeMode.light, l.themeLight),
                _Choice(ThemeMode.dark, l.themeDark),
              ],
              onChanged: (v) => st.update((x) => x.themeMode = v),
            ),
            _ChoiceRow<String>(
              icon: Icons.translate_rounded,
              title: l.language,
              value: st.locale?.languageCode ?? '',
              options: [
                _Choice('', l.themeSystem),
                const _Choice('en', 'English'),
                const _Choice('ar', 'العربية'),
              ],
              onChanged: (v) =>
                  st.update((x) => x.locale = v.isEmpty ? null : Locale(v)),
            ),
          ],
        );

        final security = _Group(
          title: x.security,
          children: [
            _PillRow<int>(
              icon: Icons.timer_outlined,
              title: l.autoLock,
              value: st.autoLockSeconds,
              options: [
                for (final n in {
                  60,
                  120,
                  300,
                  900,
                  3600,
                  st.autoLockSeconds,
                }.toList()..sort())
                  _Choice(
                    n,
                    n >= 60 && n % 60 == 0 ? l.minutes(n ~/ 60) : l.seconds(n),
                  ),
              ],
              onChanged: (v) => st.update((x) => x.autoLockSeconds = v),
            ),
            FocusRing(
              child: SwitchListTile(
                contentPadding: _rowPadding,
                secondary: const _IconTile(icon: Icons.phonelink_lock_outlined),
                title: Text(l.lockOnBackground),
                value: st.lockOnBackground,
                onChanged: (v) => st.update((x) => x.lockOnBackground = v),
              ),
            ),
            _PillRow<int>(
              icon: Icons.content_paste_off_outlined,
              title: l.clipboardClear,
              value: st.clipboardClearSeconds,
              options: [
                for (final n in {
                  10,
                  20,
                  30,
                  60,
                  120,
                  st.clipboardClearSeconds,
                }.toList()..sort())
                  _Choice(n, l.seconds(n)),
              ],
              onChanged: (v) => st.update((x) => x.clipboardClearSeconds = v),
            ),
            FocusRing(
              child: SwitchListTile(
                contentPadding: _rowPadding,
                secondary: const _IconTile(icon: Icons.language_rounded),
                title: Text(l.fetchIcons),
                subtitle: Text(l.fetchIconsNote),
                value: st.fetchIcons,
                onChanged: (v) async {
                  await st.update((x) => x.fetchIcons = v);
                  // Forget the icons in memory; fetch again if turned on.
                  s.favicons?.clear();
                  s.prefetchIcons();
                },
              ),
            ),
            if (s.biometrics != null) _BiometricTile(settings: st),
            _Row(
              icon: Icons.password_rounded,
              title: l.changePassword,
              trailing: const _Chevron(),
              onTap: () => _changePassword(context),
            ),
          ],
        );

        final sync = _Group(title: l.sync, children: [_SyncRows()]);

        final data = _Group(
          title: x.data,
          children: [
            _Row(
              icon: Icons.file_upload_outlined,
              title: l.exportEncrypted,
              trailing: const _Chevron(),
              onTap: () => _export(context),
            ),
            _Row(
              icon: Icons.file_download_outlined,
              title: l.importEncrypted,
              trailing: const _Chevron(),
              onTap: () => _import(context, encrypted: true),
            ),
            _Row(
              icon: Icons.table_chart_outlined,
              title: l.importCsv,
              subtitle: l.csvWarning,
              trailing: const _Chevron(),
              onTap: () => _import(context, encrypted: false),
            ),
          ],
        );

        // The updater's rows: switch, version, last check and "Check now"; one
        // line in a development build, nothing where there are no updates. The
        // plain version row is only added where that tile shows none.
        final updateTile =
            s.updates?.enabled == true || !AppVersion.current.enabled;
        final about = _Group(
          title: x.about,
          ruleIndent: 0,
          children: [
            const _AboutHeader(),
            if (updateTile) const UpdateSettingsTile(),
            if (s.updates?.enabled != true) const AboutVersionTile(),
          ],
        );

        final Widget content;
        if (wide) {
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Each column is its own focus group, so Tab finishes one
              // column before it moves to the other.
              Expanded(
                child: FocusTraversalGroup(
                  child: _column([appearance, security]),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: FocusTraversalGroup(
                  child: _column([sync, data, about], from: 2),
                ),
              ),
            ],
          );
        } else {
          content = _column([appearance, security, sync, data, about]);
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(title: Text(l.settings)),
          body: ListView(
            padding: MaxWidthBody.insets(
              context,
              maxWidth: wide ? AppLayout.page : AppLayout.form,
              base: EdgeInsets.only(
                top: topInset,
                bottom: MediaQuery.paddingOf(context).bottom + 32,
              ),
            ),
            children: [content],
          ),
        );
      },
    );
  }

  /// Groups one under the other, each fading in a beat after the last.
  Widget _column(List<Widget> groups, {int from = 0}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0) const SizedBox(height: 24),
        Reveal(index: from + i, child: groups[i]),
      ],
    ],
  );

  Future<String?> _askPassword(BuildContext context, String label) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      animationStyle: context.motionStyle,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          textDirection: TextDirection.ltr,
          textAlign: Directionality.of(ctx) == TextDirection.rtl
              ? TextAlign.right
              : TextAlign.left,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          PrimaryButton(
            glow: false,
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(ctx.l10n.ok),
          ),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<void> _changePassword(BuildContext context) async {
    final l = context.l10n;
    final s = context.services;
    final messenger = ScaffoldMessenger.of(context);
    final current = await _askPassword(context, l.currentPassword);
    if (current == null || !context.mounted) return;
    final next = await _askPassword(context, l.newPassword);
    if (next == null || !context.mounted) return;
    if (s.strength.evaluate(next).score < 3) {
      messenger.showSnackBar(SnackBar(content: Text(l.passwordTooWeak)));
      return;
    }
    final confirm = await _askPassword(context, l.confirmPassword);
    if (confirm != next) {
      messenger.showSnackBar(SnackBar(content: Text(l.passwordsDontMatch)));
      return;
    }
    try {
      final auth = await s.session.changePassword(current, next);
      await s.sync?.onPasswordReset(newAuthSecret: auth);
      // The biometric wrap holds the vault key, which did not change.
      messenger.showSnackBar(SnackBar(content: Text(l.passwordChanged)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.wrongPassword)));
    }
  }

  Future<void> _export(BuildContext context) async {
    final l = context.l10n;
    final s = context.services;
    final messenger = ScaffoldMessenger.of(context);
    final pw = await _askPassword(context, l.exportPassword);
    if (pw == null || pw.isEmpty) return;
    final data = await s.importExport.exportEncrypted(s.session.entries, pw);
    final bytes = Uint8List.fromList(utf8.encode(data));
    final path = await FilePicker.saveFile(
      fileName: 'khazna-backup.vsnap',
      bytes: bytes,
    );
    if (path != null && (Platform.isWindows || Platform.isLinux)) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (path != null) {
      messenger.showSnackBar(SnackBar(content: Text(l.exported)));
    }
  }

  Future<void> _import(BuildContext context, {required bool encrypted}) async {
    final l = context.l10n;
    final s = context.services;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final picked = await FilePicker.pickFiles(withData: true);
    final file = picked?.files.single;
    final Uint8List? bytes;
    try {
      bytes =
          file?.bytes ??
          (file?.path == null ? null : await File(file!.path!).readAsBytes());
    } finally {
      await _clearPickerCopies();
    }
    if (bytes == null || !context.mounted) return;
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      if (encrypted) {
        final pw = await _askPassword(context, l.exportPassword);
        if (pw == null) return;
        final result = await s.importExport.importEncrypted(text, pw);
        await s.session.saveEntries(result.entries);
        s.prefetchIcons();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.imported(result.entries.length, result.skipped)),
          ),
        );
        return;
      }
      // CSV: nothing is saved until the user has reviewed every login.
      final result = s.importExport.importCsv(text);
      final saved = await navigator.push<int>(
        MaterialPageRoute(
          builder: (_) => ImportReviewScreen(
            imported: result.entries,
            skipped: result.skipped,
          ),
        ),
      );
      if (saved == null || !context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.imported(saved, result.skipped))),
      );
      await _remindDeleteCsv(context);
    } on ImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(l.error)));
    }
  }
}

/// file_picker copies the picked file into the app cache on Android and
/// iOS. For a CSV that copy holds every password in plain text (audit M-6),
/// so it goes as soon as the bytes are read.
Future<void> _clearPickerCopies() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await FilePicker.clearTemporaryFiles();
  } on Object {
    // Best effort; the OS clears the cache eventually.
  }
}

/// The app cannot delete the user's CSV export (it may be in Downloads, a
/// cloud folder or an e-mail), so it reminds them.
Future<void> _remindDeleteCsv(BuildContext context) => showDialog<void>(
  context: context,
  animationStyle: context.motionStyle,
  builder: (c) => AlertDialog(
    // Centre: the dialog's icon slot is tight, which would stretch a tile
    // with a fixed size into a flat bar.
    icon: Center(
      child: _IconTile(
        icon: Icons.delete_sweep_outlined,
        size: 56,
        color: c.tokens.warn,
        fill: c.tokens.warnContainer,
      ),
    ),
    title: Text(c.l10n.deleteCsvTitle, textAlign: TextAlign.center),
    content: Text(c.l10n.deleteCsvBody, textAlign: TextAlign.center),
    actionsAlignment: MainAxisAlignment.center,
    actions: [
      PrimaryButton(
        glow: false,
        onPressed: () => Navigator.pop(c),
        child: Text(c.l10n.ok),
      ),
    ],
  ),
);

/// [text] kept left to right inside a sentence of another direction (an
/// e-mail address in an Arabic line): isolate marks U+2066 and U+2069.
String _ltr(String text) => '\u2066$text\u2069';

const _rowPadding = IconTile.rowPadding;

class _BiometricTile extends StatefulWidget {
  const _BiometricTile({required this.settings});
  final AppSettings settings;

  @override
  State<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends State<_BiometricTile> {
  bool? _available;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.services.biometrics!.isAvailable().then((v) {
      if (mounted) setState(() => _available = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return FocusRing(
      child: SwitchListTile(
        contentPadding: _rowPadding,
        secondary: const _IconTile(icon: Icons.fingerprint_rounded),
        title: Text(context.l10n.biometrics),
        value: widget.settings.biometricsEnabled,
        onChanged: _available != true
            ? null
            : (v) async {
                final bio = s.biometrics!;
                if (v) {
                  await bio.enable(
                    s.session.crypto,
                    s.session.keyring.vaultKey,
                  );
                  if (!await bio.isEnabled) return;
                } else {
                  await bio.disable();
                }
                await widget.settings.update((x) => x.biometricsEnabled = v);
              },
      ),
    );
  }
}

/// The rows of the sync group: not configured, off (tap to turn on) or on
/// (who it syncs as, when it last did, a sync button and sign out).
class _SyncRows extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final s = context.services;
    final sync = s.sync;
    if (sync == null) {
      return _Row(
        icon: Icons.cloud_off_outlined,
        title: l.sync,
        subtitle: 'SUPABASE_URL not configured',
      );
    }
    if (!sync.enabled) {
      return _Row(
        icon: Icons.cloud_outlined,
        title: l.enableSync,
        trailing: const _Chevron(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SignInScreen(enableForLocal: true),
          ),
        ),
      );
    }
    final failed = sync.status == SyncStatus.error;
    return Column(
      children: [
        ListTile(
          contentPadding: _rowPadding,
          leading: _IconTile(
            icon: failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            color: failed ? t.error : t.good,
            fill: failed ? t.errorContainer : t.goodContainer,
          ),
          // The address reads left to right inside an Arabic sentence.
          title: Text(l.syncEnabled(_ltr(s.settings.syncEmail ?? ''))),
          subtitle: sync.lastSync == null
              ? null
              : Row(
                  children: [
                    PulseDot(
                      color: failed ? t.error : t.good,
                      size: 6,
                      active: !failed,
                      pulses: 2,
                    ),
                    Flexible(
                      child: Text(
                        l.lastSynced(
                          TimeOfDay.fromDateTime(sync.lastSync!)
                              .format(context),
                        ),
                      ),
                    ),
                  ],
                ),
          trailing: IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: l.syncNow,
            onPressed: () => syncNowFromButton(sync),
          ),
        ),
        // Another device deleted most of the vault: apply it here or keep
        // the entries (sync here waits for that choice).
        if (sync.pendingMassDeletion case final count?) ...[
          const _Rule(),
          SyncDeletionPrompt(sync: sync, count: count, framed: false),
        ],
        const _Rule(),
        _Row(
          icon: Icons.logout_rounded,
          title: l.signOut,
          trailing: const _Chevron(),
          onTap: sync.disable,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Layout pieces
// -----------------------------------------------------------------------------

/// A titled card of rows with a hairline between them.
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    this.ruleIndent = 66,
  });

  final String title;
  final List<Widget> children;

  /// Where the hairlines start: under the text of a standard row (66), or at
  /// the edge for rows of another make (the updater's).
  final double ruleIndent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: SectionHeader(title: title, size: SectionHeaderSize.group),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) _Rule(indent: ruleIndent),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The hairline between rows, starting under the text, not under the icon.
class _Rule extends StatelessWidget {
  const _Rule({this.indent = 66});

  final double indent;

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: indent, endIndent: 0);
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.chevron_right_rounded, color: context.tokens.muted);
}

/// The 36 px rounded tile with an outline icon at the start of a row.
typedef _IconTile = IconTile;

/// A plain row: icon tile, title, optional subtitle and trailing widget.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      child: ListTile(
        contentPadding: _rowPadding,
        leading: _IconTile(icon: icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// One option of a choice or a pill menu.
class _Choice<T> {
  const _Choice(this.value, this.label, [this.icon]);

  final T value;
  final String label;
  final IconData? icon;
}

/// A row with a few choices as pills under its title (theme, language).
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final List<_Choice<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _IconTile(icon: icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Semantics(
                    header: true,
                    child: Text(title, style: tt.titleMedium),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final o in options)
                      PillChip(
                        label: o.label,
                        icon: o.icon,
                        selected: o.value == value,
                        onSelected: (_) => onChanged(o.value),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with a pill at its end that opens a menu of choices (auto-lock,
/// clipboard). With large system text the pill drops under the title.
class _PillRow<T> extends StatelessWidget {
  const _PillRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final List<_Choice<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 21;
    final pill = _PillMenu<T>(
      title: title,
      value: value,
      options: options,
      onChanged: onChanged,
    );
    final heading = Text(title, style: tt.titleMedium);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _IconTile(icon: icon),
                    const SizedBox(width: 14),
                    Expanded(child: heading),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 50),
                  child: pill,
                ),
              ],
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  _IconTile(icon: icon),
                  const SizedBox(width: 14),
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  pill,
                ],
              ),
            ),
    );
  }
}

/// The pill that shows the chosen value and opens the menu of options.
class _PillMenu<T> extends StatelessWidget {
  const _PillMenu({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<_Choice<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final current = options.firstWhere(
      (o) => o.value == value,
      orElse: () => options.first,
    );
    return MenuAnchor(
      menuChildren: [
        for (final o in options)
          MenuItemButton(
            leadingIcon: Icon(
              o.value == value ? Icons.check_rounded : null,
              size: 20,
              color: t.accent2,
            ),
            onPressed: () => onChanged(o.value),
            child: Text(o.label),
          ),
      ],
      // One node that names the setting and its value, says whether the menu
      // is open, and keeps the InkWell's own focus and tap semantics (an
      // excludeSemantics here made it unreachable for a keyboard screen
      // reader). The pill's text and arrow are excluded: the label has them.
      builder: (context, controller, _) => Semantics(
        container: true,
        button: true,
        label: '$title: ${current.label}',
        expanded: controller.isOpen,
        child: Material(
          color: t.surface2,
          shape: StadiumBorder(
            side: BorderSide(color: controller.isOpen ? t.accent : t.line2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 10, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        current.label,
                        style: tt.labelLarge!.copyWith(color: t.ink),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, size: 20, color: t.soft),
                    ],
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

/// The app's name and tagline over the updater's rows. The name comes from
/// `lib/brand.dart`, never from a literal here.
class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.maybeLocaleOf(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
      child: Row(
        children: [
          const BrandMark(size: 48, glow: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    appNameFor(locale).toUpperCase(),
                    style: AppText.wordmark.copyWith(
                      color: t.ink,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(appTaglineFor(locale), style: tt.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The few words only this screen needs. They are written here, in both
/// languages, until they move into `lib/l10n/*.arb` with the others.
class _Txt {
  const _Txt(this.ar);

  factory _Txt.of(BuildContext context) => _Txt(context.isArabic);

  final bool ar;

  String get appearance => ar ? 'الواجهة' : 'Appearance';
  String get security => ar ? 'الأمان' : 'Security';
  String get data => ar ? 'البيانات' : 'Data';
  String get about => ar ? 'حول التطبيق' : 'About';
}
