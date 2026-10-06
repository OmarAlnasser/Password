import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/vault_entry.dart';
import '../services/ocr/ocr_engine.dart';
import '../services/ocr/ocr_parser.dart';
import '../services/vault_session.dart';
import 'app_scope.dart';
import 'dashboard_screen.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'generator_screen.dart';
import 'ocr/ocr_import_screen.dart';
import 'ocr/quick_save_sheet.dart';
import 'recovery_reset_screen.dart';
import 'settings_screen.dart';
import 'widgets/site_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String? _tag;
  bool _favoritesOnly = false;
  bool _pasting = false;

  static const _pasteKeys = [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
    SingleActivator(LogicalKeyboardKey.keyV, meta: true),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
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
    HardwareKeyboard.instance.removeHandler(_onKey);
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

  /// Ctrl+V / Cmd+V while this screen is on top. In a text field (the search
  /// bar) the key pastes into the field as usual.
  ///
  /// A keyboard handler rather than a [Focus] around the screen: on desktop,
  /// clicking outside the search field moves focus to the route's scope,
  /// above any such [Focus], and the shortcut would stop working.
  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!mounted ||
        !_pasteKeys.any((k) => k.accepts(event, keyboard)) ||
        ModalRoute.isCurrentOf(context) == false) {
      return false;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorStateOfType<EditableTextState>() != null) {
      return false;
    }
    unawaited(_paste());
    return true;
  }

  /// Reads what the user copied: a screenshot is OCR'd on the device, text is
  /// parsed as it is. Offers to save the login found, then to clear the
  /// clipboard.
  Future<void> _paste() async {
    if (_pasting) return;
    final s = context.services;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pasting = true);
    OcrResult? found;
    var screenshot = false;
    try {
      final clip = await s.bridge.readClipboard();
      final image = clip.imagePath;
      final text = clip.text;
      if (image != null) {
        screenshot = true;
        try {
          if (mounted) {
            final lines = await OcrEngine.forPlatform(s.bridge)
                .recognize(image);
            found = OcrCredentialParser().parse(lines);
          }
        } finally {
          // Our plaintext copy of the screenshot: never keep it.
          _deleteQuietly(image);
        }
      } else if (text != null && !s.clipboard.isOwnCopy(text)) {
        found = OcrCredentialParser().parseText(text);
      }
    } on Object {
      found = null;
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
    if (!mounted) return;
    if (found == null || (found.username == null && found.password == null)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.pasteNothingFound)));
      return;
    }
    final saved = await QuickSaveSheet.show(context, found);
    if (saved && mounted) {
      await offerClearClipboard(context, screenshot: screenshot);
    }
  }

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } on Object {
      // Already gone, or best effort.
    }
  }

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
              IconButton(
                tooltip: l.pasteLogin,
                icon: const Icon(Icons.content_paste),
                onPressed: _pasting ? null : _paste,
              ),
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
                  // Room for the two floating buttons below the last entry.
                  padding: const EdgeInsets.only(bottom: 136),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return ListTile(
                      leading: SiteIcon(url: e.url, title: e.title),
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
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'paste',
                tooltip: l.pasteLogin,
                onPressed: _pasting ? null : _paste,
                child: _pasting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.content_paste),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'add',
                icon: const Icon(Icons.add),
                label: Text(l.addEntry),
                onPressed: () => _open(const EntryEditScreen()),
              ),
            ],
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
