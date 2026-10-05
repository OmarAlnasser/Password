import 'package:flutter/material.dart';

import '../data/models/vault_entry.dart';
import '../services/vault_session.dart';
import 'app_scope.dart';
import 'dashboard_screen.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'generator_screen.dart';
import 'ocr/ocr_import_screen.dart';
import 'recovery_reset_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String? _tag;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.services.session.unlockedViaRecovery) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const RecoveryResetScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VaultEntry> _filtered(VaultSession session) => session.entries
      .where((e) => !_favoritesOnly || e.favorite)
      .where((e) => _tag == null || e.tags.contains(_tag))
      .where((e) => e.matches(_search.text.trim()))
      .toList();

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final services = context.services;
    final session = services.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final items = _filtered(session);
        final tags = session.allTags.toList()..sort();
        return Scaffold(
          appBar: AppBar(
            title: Text(l.appTitle),
            actions: [
              if (services.sync != null)
                IconButton(
                  tooltip: l.syncNow,
                  icon: const Icon(Icons.sync),
                  onPressed: () => services.sync!.syncNow(),
                ),
              IconButton(
                tooltip: l.lock,
                icon: const Icon(Icons.lock_outline),
                onPressed: session.lock,
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'gen' => _open(const GeneratorScreen()),
                  'ocr' => _open(const OcrImportScreen()),
                  'dash' => _open(const DashboardScreen()),
                  _ => _open(const SettingsScreen()),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'gen', child: Text(l.generator)),
                  PopupMenuItem(value: 'ocr', child: Text(l.scanScreenshot)),
                  PopupMenuItem(
                    value: 'dash',
                    child: Text(l.securityDashboard),
                  ),
                  PopupMenuItem(value: 'settings', child: Text(l.settings)),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(112),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SearchBar(
                      controller: _search,
                      hintText: l.search,
                      leading: const Icon(Icons.search),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: FilterChip(
                            avatar: const Icon(Icons.star, size: 18),
                            label: Text(l.favorites),
                            selected: _favoritesOnly,
                            onSelected: (v) =>
                                setState(() => _favoritesOnly = v),
                          ),
                        ),
                        for (final t in tags)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: FilterChip(
                              label: Text(t),
                              selected: _tag == t,
                              onSelected: (v) =>
                                  setState(() => _tag = v ? t : null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: items.isEmpty
              ? Center(child: Text(l.noEntries))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          e.title.isEmpty
                              ? '?'
                              : e.title.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(e.title.isEmpty ? e.host : e.title),
                      subtitle: Text(e.username),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.favorite)
                            const Icon(Icons.star, color: Colors.amber),
                          IconButton(
                            tooltip: l.copy,
                            icon: const Icon(Icons.key),
                            onPressed: e.password.isEmpty
                                ? null
                                : () =>
                                      copySecretWithToast(context, e.password),
                          ),
                        ],
                      ),
                      onTap: () => _open(EntryDetailScreen(entryId: e.id)),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(l.addEntry),
            onPressed: () => _open(const EntryEditScreen()),
          ),
        );
      },
    );
  }
}

Future<void> copySecretWithToast(BuildContext context, String value) async {
  final s = context.services;
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  await s.clipboard.copySecret(value);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(l.copied(s.settings.clipboardClearSeconds))),
    );
}
