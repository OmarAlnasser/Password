import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/import_export.dart';
import '../services/settings.dart';
import '../services/sync/sync_service.dart';
import 'app_scope.dart';
import 'import/import_review_screen.dart';
import 'sign_in_screen.dart';
import 'update/update.dart';

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
        return Scaffold(
          appBar: AppBar(title: Text(l.settings)),
          body: ListView(
            children: [
              ListTile(
                title: Text(l.theme),
                trailing: DropdownButton<ThemeMode>(
                  value: st.themeMode,
                  onChanged: (v) => st.update((x) => x.themeMode = v!),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(l.themeSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(l.themeLight),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(l.themeDark),
                    ),
                  ],
                ),
              ),
              ListTile(
                title: Text(l.language),
                trailing: DropdownButton<String>(
                  value: st.locale?.languageCode ?? '',
                  onChanged: (v) => st.update(
                    (x) => x.locale = v == null || v.isEmpty ? null : Locale(v),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(l.themeSystem)),
                    const DropdownMenuItem(value: 'en', child: Text('English')),
                    const DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                title: Text(l.autoLock),
                trailing: DropdownButton<int>(
                  value: st.autoLockSeconds,
                  onChanged: (v) => st.update((x) => x.autoLockSeconds = v!),
                  items: [
                    for (final m in {1, 2, 5, 15, 60, st.autoLockSeconds ~/ 60})
                      if (m > 0)
                        DropdownMenuItem(
                          value: m * 60,
                          child: Text(l.minutes(m)),
                        ),
                    if (st.autoLockSeconds < 60)
                      DropdownMenuItem(
                        value: st.autoLockSeconds,
                        child: Text(l.seconds(st.autoLockSeconds)),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: Text(l.lockOnBackground),
                value: st.lockOnBackground,
                onChanged: (v) => st.update((x) => x.lockOnBackground = v),
              ),
              ListTile(
                title: Text(l.clipboardClear),
                trailing: DropdownButton<int>(
                  value: st.clipboardClearSeconds,
                  onChanged: (v) =>
                      st.update((x) => x.clipboardClearSeconds = v!),
                  items: [
                    for (final n in {
                      10,
                      20,
                      30,
                      60,
                      120,
                      st.clipboardClearSeconds,
                    })
                      DropdownMenuItem(value: n, child: Text(l.seconds(n))),
                  ],
                ),
              ),
              SwitchListTile(
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
              if (s.biometrics != null) _BiometricTile(settings: st),
              ListTile(
                title: Text(l.changePassword),
                leading: const Icon(Icons.password),
                onTap: () => _changePassword(context),
              ),
              const Divider(),
              _SyncTile(),
              const Divider(),
              // Switch, version, last check and "Check now"; one line in a
              // development build, nothing where there are no updates.
              const UpdateSettingsTile(),
              // The tile above already shows the version when it is there.
              if (s.updates?.enabled != true) const AboutVersionTile(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: Text(l.exportEncrypted),
                onTap: () => _export(context),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(l.importEncrypted),
                onTap: () => _import(context, encrypted: true),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(l.importCsv),
                subtitle: Text(l.csvWarning),
                onTap: () => _import(context, encrypted: false),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _askPassword(BuildContext context, String label) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
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
      fileName: 'vaultsnap-backup.vsnap',
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
  builder: (c) => AlertDialog(
    icon: const Icon(Icons.delete_sweep_outlined),
    title: Text(c.l10n.deleteCsvTitle),
    content: Text(c.l10n.deleteCsvBody),
    actions: [
      FilledButton(onPressed: () => Navigator.pop(c), child: Text(c.l10n.ok)),
    ],
  ),
);

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
    return SwitchListTile(
      title: Text(context.l10n.biometrics),
      value: widget.settings.biometricsEnabled,
      onChanged: _available != true
          ? null
          : (v) async {
              final bio = s.biometrics!;
              if (v) {
                await bio.enable(s.session.crypto, s.session.keyring.vaultKey);
                if (!await bio.isEnabled) return;
              } else {
                await bio.disable();
              }
              await widget.settings.update((x) => x.biometricsEnabled = v);
            },
    );
  }
}

class _SyncTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = context.services;
    final sync = s.sync;
    if (sync == null) {
      return ListTile(
        leading: const Icon(Icons.cloud_off),
        title: Text(l.sync),
        subtitle: const Text('SUPABASE_URL not configured'),
      );
    }
    if (!sync.enabled) {
      return ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(l.enableSync),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SignInScreen(enableForLocal: true),
          ),
        ),
      );
    }
    return Column(
      children: [
        ListTile(
          leading: Icon(
            sync.status == SyncStatus.error
                ? Icons.cloud_off
                : Icons.cloud_done,
          ),
          title: Text(l.syncEnabled(s.settings.syncEmail ?? '')),
          subtitle: sync.lastSync == null
              ? null
              : Text(
                  l.lastSynced(
                    TimeOfDay.fromDateTime(sync.lastSync!).format(context),
                  ),
                ),
          trailing: IconButton(
            icon: const Icon(Icons.sync),
            onPressed: sync.syncNow,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l.signOut),
          onTap: sync.disable,
        ),
      ],
    );
  }
}
