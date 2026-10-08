import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/models/vault_entry.dart';
import 'l10n/app_localizations.dart';
import 'services/autofill_matcher.dart';
import 'services/vault_session.dart';
import 'ui/app_scope.dart';
import 'ui/theme/app_theme.dart';
import 'ui/unlock_screen.dart';
import 'ui/widgets/app_shell.dart';

/// Minimal UI for Android autofill: unlock, then pick a matching entry.
class AutofillApp extends StatefulWidget {
  const AutofillApp({super.key, required this.services});

  final AppServices services;

  @override
  State<AutofillApp> createState() => _AutofillAppState();
}

class _AutofillAppState extends State<AutofillApp> {
  static const _channel = MethodChannel('app.vaultsnap/autofill');

  String? _package;
  String? _domain;

  @override
  void initState() {
    super.initState();
    widget.services.session.addListener(_refresh);
    _channel.invokeMapMethod<String, String?>('getRequest').then((m) {
      setState(() {
        _package = m?['package'];
        _domain = m?['domain'];
      });
    });
  }

  @override
  void dispose() {
    widget.services.session.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _fill(VaultEntry e) async {
    final session = widget.services.session;
    await _channel.invokeMethod<void>('fill', {
      'username': e.username,
      'password': e.password,
    });
    // A fill is a use of the entry ("Recently used"). Awaited, so the time
    // is written before the lock closes the database (a failed write is
    // only logged there).
    await session.markUsed(e.id);
    await session.lock();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.services.session;
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(widget.services.settings.locale),
        darkTheme: AppTheme.dark(widget.services.settings.locale),
        themeMode: widget.services.settings.themeMode,
        builder: (context, child) => AppShell(child: child!),
        locale: widget.services.settings.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: switch (session.state) {
          VaultState.unlocked => _Picker(
            entries: AutofillMatcher.match(
              session.entries,
              domain: _domain,
              appId: _package,
            ),
            target: _domain ?? _package ?? '',
            onPick: _fill,
            onCancel: () => _channel.invokeMethod<void>('cancel'),
          ),
          VaultState.locked => const UnlockScreen(),
          _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.entries,
    required this.target,
    required this.onPick,
    required this.onCancel,
  });

  final List<VaultEntry> entries;
  final String target;
  final void Function(VaultEntry) onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(target),
      leading: IconButton(icon: const Icon(Icons.close), onPressed: onCancel),
    ),
    body: entries.isEmpty
        ? Center(child: Text(context.l10n.noEntries))
        : ListView(
            children: [
              for (final e in entries)
                ListTile(
                  title: Text(e.title),
                  subtitle: Text(e.username),
                  onTap: () => onPick(e),
                ),
            ],
          ),
  );
}
