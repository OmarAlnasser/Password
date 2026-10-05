import 'package:flutter/material.dart';

import '../data/models/vault_entry.dart';
import '../services/breach_checker.dart';
import 'app_scope.dart';
import 'entry_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int>? _breached;
  bool _checking = false;
  String? _error;

  Future<void> _checkBreaches() async {
    final s = context.services;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await SecurityAnalyzer(s.strength)
          .checkBreaches(s.session.entries, s.breaches);
      if (mounted) setState(() => _breached = r);
    } on Object {
      if (mounted) setState(() => _error = context.l10n.error);
    } finally {
      s.breaches.clearCache();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = context.services;
    final report = SecurityAnalyzer(s.strength).analyze(s.session.entries);
    final byId = {for (final e in s.session.entries) e.id: e};

    Widget section(
      String title,
      IconData icon,
      List<VaultEntry> items, {
      String Function(VaultEntry)? detail,
    }) {
      return ExpansionTile(
        leading: Icon(
          icon,
          color: items.isEmpty ? Colors.green : Colors.orange,
        ),
        title: Text('$title (${items.length})'),
        children: items.isEmpty
            ? [ListTile(title: Text(l.allGood))]
            : [
                for (final e in items)
                  ListTile(
                    title: Text(e.title),
                    subtitle: Text(detail?.call(e) ?? e.username),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EntryDetailScreen(entryId: e.id),
                      ),
                    ),
                  ),
              ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.securityDashboard)),
      body: ListView(
        children: [
          section(l.weakPasswords, Icons.warning_amber, report.weak),
          section(l.reusedPasswords, Icons.copy_all, [
            for (final g in report.reused) ...g,
          ]),
          section(l.oldPasswords, Icons.history, report.old),
          const Divider(),
          if (s.settings.hibpEnabled) ...[
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              subtitle: Text(l.hibpExplain),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore),
                label: Text(l.checkBreaches),
                onPressed: _checking ? null : _checkBreaches,
              ),
            ),
            if (_error != null) ListTile(title: Text(_error!)),
            if (_breached != null)
              section(l.breachedPasswords, Icons.dangerous_outlined, [
                for (final id in _breached!.keys) ?byId[id],
              ], detail: (e) => '× ${_breached![e.id]}'),
          ],
        ],
      ),
    );
  }
}
