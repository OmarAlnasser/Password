import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../data/models/vault_entry.dart';
import '../services/entry_sort.dart';
import '../services/ocr/ocr_parser.dart';
import '../services/ocr/ocr_scanner.dart';
import '../services/sync/sync_service.dart';
import '../services/vault_session.dart';
import 'app_scope.dart';
import 'dashboard_screen.dart';
import 'entry_detail_screen.dart';
import 'entry_edit_screen.dart';
import 'generator_screen.dart';
import 'ocr/ocr_import_screen.dart';
import 'ocr/ocr_widgets.dart';
import 'ocr/quick_save_sheet.dart';
import 'recovery_reset_screen.dart';
import 'settings_screen.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';
import 'widgets/brand_mark.dart';
import 'widgets/confirm_delete_dialog.dart';
import 'widgets/empty_state.dart';
import 'widgets/entry_sort_button.dart';
import 'widgets/entry_use_scope.dart';
import 'widgets/glass_bar.dart';
import 'widgets/max_width_body.dart';
import 'widgets/pill_chip.dart';
import 'widgets/primary_button.dart';
import 'widgets/reveal.dart';
import 'widgets/secret_text.dart';
import 'widgets/site_icon.dart';
import 'widgets/surface_card.dart';
import 'widgets/sync_deletion_prompt.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();

  /// Key of the open row of the two-pane layout, to scroll it into view when
  /// the arrow keys move the selection.
  final _selectedRowKey = GlobalKey();

  String? _tag;
  bool _favoritesOnly = false;
  bool _pasting = false;

  /// The entry shown in the right pane of the two-pane layout.
  String? _selectedId;

  /// Selection mode: rows carry check boxes, a tap ticks a row instead of
  /// opening it, and the header is the selection bar (count, select all,
  /// delete). Entered by a long press, "Select" in the menu, a click on a
  /// row's check box (mouse hover) or Ctrl+click; left by the close button,
  /// Escape or Back.
  bool _selecting = false;

  /// The ids ticked in selection mode. It may still hold entries that are
  /// filtered out (they stay ticked) or that are gone (they are ignored):
  /// [_pickedLive] is what counts and what gets deleted.
  final Set<String> _picked = {};

  /// A mass delete is being written.
  bool _deleting = false;

  /// True until the first frame is done: only the rows that are there when
  /// the screen first appears play their entrance, not rows that scroll in.
  bool _intro = true;

  /// The scan of a pasted screenshot in progress, if any.
  ScanCancelToken? _scanning;

  /// The last-used times the list is ordered by: a copy of
  /// `VaultSession.lastUsedMap` taken when the list is shown for a new reason
  /// (first shown, back from another screen, the app resumed, the sort, the
  /// search or the pills changed, entries added or removed), not the live
  /// map. Copying a password marks its entry used at once; moving that row
  /// to the top right away would put another entry under the finger or
  /// pointer, and a second tap on the same spot would copy the wrong
  /// password. The use is recorded at once; the list shows it next time.
  Map<String, DateTime> _usedOrder = const {};

  /// What [_usedOrder] was taken for (sort, search, pills); null asks for a
  /// new copy at the next build.
  Object? _usedOrderKey;

  /// The entries there were when [_usedOrder] was taken.
  Set<String> _usedOrderIds = const {};

  /// Coming back to the app is showing the list again (see [_usedOrder]).
  late final AppLifecycleListener _lifecycle;

  static const _pasteKeys = [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
    SingleActivator(LogicalKeyboardKey.keyV, meta: true),
  ];
  static const _findKeys = [
    SingleActivator(LogicalKeyboardKey.keyF, control: true),
    SingleActivator(LogicalKeyboardKey.keyF, meta: true),
  ];
  static const _newKeys = [
    SingleActivator(LogicalKeyboardKey.keyN, control: true),
    SingleActivator(LogicalKeyboardKey.keyN, meta: true),
  ];

  /// A list row's height with its gap, at the normal text size. Only used to
  /// jump close to a row that is not built yet.
  static const _rowExtent = 82.0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(onResume: _refreshOrder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _intro = false);
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
    // Locking or leaving the screen: stop reading the screenshot.
    _scanning?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The entries that pass the pills and the search, in the chosen order
  /// (favourites stay pinned on top in every order).
  List<VaultEntry> _filtered(AppServices s) {
    final session = s.session;
    final query = _search.text.trim();
    return sortEntries(
      session.entries
          .where((e) => !_favoritesOnly || e.favorite)
          .where((e) => _tag == null || e.tags.contains(_tag))
          .where((e) => e.matches(query))
          .toList(),
      s.settings.entrySort,
      _lastUsedForOrder(s),
      favoritesFirst: true,
    );
  }

  /// The last-used times to order the list by now: [_usedOrder], taken
  /// again when the sort, the search, the pills or the set of entries
  /// changed since, or after [_refreshOrder].
  Map<String, DateTime> _lastUsedForOrder(AppServices s) {
    final session = s.session;
    final key = (
      s.settings.entrySort,
      _search.text.trim(),
      _tag,
      _favoritesOnly,
    );
    final entries = session.entries;
    final sameEntries =
        entries.length == _usedOrderIds.length &&
        entries.every((e) => _usedOrderIds.contains(e.id));
    if (key != _usedOrderKey || !sameEntries) {
      _usedOrderKey = key;
      _usedOrderIds = {for (final e in entries) e.id};
      _usedOrder = Map.of(session.lastUsedMap);
    }
    return _usedOrder;
  }

  /// The list is shown again (back from another screen, the app resumed):
  /// the next build orders it by the newest last-used times.
  void _refreshOrder() {
    if (mounted) setState(() => _usedOrderKey = null);
  }

  /// Opens [page] on top of the list; coming back refreshes the order.
  void _open(Widget page) {
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page))
          .then((_) => _refreshOrder()),
    );
  }

  void _add() => _open(const EntryEditScreen());

  void _clearFilters() => setState(() {
    _favoritesOnly = false;
    _tag = null;
    _search.clear();
  });

  /// A tap on a row: the pane on the right of a wide window, else a screen.
  void _openEntry(VaultEntry e, {required bool wide}) {
    if (wide) {
      setState(() => _selectedId = e.id);
    } else {
      _open(EntryDetailScreen(entryId: e.id));
    }
  }

  /// A tap (or Enter) on a row. In selection mode it ticks the row; a
  /// Ctrl+click (Cmd+click) starts selection mode with the row ticked;
  /// otherwise it opens the entry. Never opens the pane while selecting.
  void _onRowTap(VaultEntry e, {required bool wide}) {
    if (_selecting) return _toggle(e.id);
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      return _startSelection(e.id);
    }
    _openEntry(e, wide: wide);
  }

  /// [_picked] without the entries that are gone (deleted here, by sync or
  /// on another device).
  Set<String> _pickedLive(VaultSession session) {
    if (_picked.isEmpty) return const {};
    final live = {for (final e in session.entries) e.id};
    return {
      for (final id in _picked)
        if (live.contains(id)) id,
    };
  }

  void _startSelection([String? id]) => setState(() {
    _selecting = true;
    if (id != null) _picked.add(id);
  });

  void _exitSelection() => setState(() {
    _selecting = false;
    _picked.clear();
  });

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id)) _picked.add(id);
  });

  /// "Select all" ticks every row that is listed now (the search and the
  /// pills apply). When those are all ticked already it is "Clear
  /// selection" and unticks everything, rows the search or the pills hide
  /// included, so no tick is left behind that the user cannot see.
  void _toggleAll(List<VaultEntry> listed) => setState(() {
    final ids = [for (final e in listed) e.id];
    if (ids.every(_picked.contains)) {
      _picked.clear();
    } else {
      _picked.addAll(ids);
    }
  });

  /// Asks, then deletes exactly [ids] in one go and says how many went.
  ///
  /// The dialog says how many of them the search or the pills hide (they are
  /// deleted too), and when sync is on and this many would make the other
  /// devices ask before applying it (`SyncService.massDeleteMin` and
  /// `massDeleteRatio`), it says that as well.
  Future<void> _deletePicked(Set<String> ids, List<VaultEntry> listed) async {
    if (ids.isEmpty || _deleting) return;
    final l = context.l10n;
    final services = context.services;
    final session = services.session;
    final messenger = ScaffoldMessenger.of(context);
    final shown = {for (final e in listed) e.id};
    final hidden = ids.where((id) => !shown.contains(id)).length;
    final sync = services.sync;
    final othersWillAsk =
        sync != null &&
        sync.enabled &&
        ids.length >= SyncService.massDeleteMin &&
        ids.length > session.entries.length * SyncService.massDeleteRatio;
    final ok = await confirmDeleteEntries(
      context,
      count: ids.length,
      notes: [
        if (hidden > 0) l.deleteHiddenCount(hidden),
        if (othersWillAsk) l.deleteSyncWarning,
      ],
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      final n = await session.deleteEntries(ids);
      if (mounted) {
        setState(() {
          _selecting = false;
          _picked.clear();
          if (ids.contains(_selectedId)) _selectedId = null;
        });
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.entriesDeleted(n))));
    } on Object catch (e) {
      // deleteEntries is all or nothing: nothing changed. Only the type is
      // logged, never an entry.
      debugPrint('HomeScreen: delete failed (${e.runtimeType})');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.deleteFailed)));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Arrow keys in the search field of the two-pane layout: move the open row.
  void _moveSelection(int delta) {
    final items = _filtered(context.services);
    if (items.isEmpty) return;
    final at = items.indexWhere((e) => e.id == _selectedId);
    final next = at < 0
        ? (delta > 0 ? 0 : items.length - 1)
        : (at + delta).clamp(0, items.length - 1);
    setState(() => _selectedId = items[next].id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _selectedRowKey.currentContext;
      if (row != null) {
        Scrollable.ensureVisible(
          row,
          duration: context.motion(AppMotion.fast),
          curve: AppMotion.standard,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      } else if (_scroll.hasClients) {
        // Not built yet: jump close, then the next frame can find it.
        _scroll.jumpTo(
          (next * _rowExtent).clamp(0.0, _scroll.position.maxScrollExtent),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _selectedRowKey.currentContext;
          if (mounted && c != null) Scrollable.ensureVisible(c);
        });
      }
    });
  }

  KeyEventResult _onSearchKey(KeyEvent event, {required bool wide}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      // Selection mode goes first; the search (and what it ticked) stays.
      if (_selecting) {
        _exitSelection();
      } else if (_search.text.isNotEmpty) {
        setState(_search.clear);
      } else {
        _searchFocus.unfocus();
      }
      return KeyEventResult.handled;
    }
    // Not while selecting: no row is open then, and selecting never opens
    // or changes the pane. The arrows move the caret in the field instead.
    if (wide &&
        !_selecting &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      _moveSelection(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Ctrl+V / Cmd+V while this screen is on top. In a text field (the search
  /// bar) the key pastes into the field as usual. Ctrl+F focuses the search
  /// field and Ctrl+N starts a new entry.
  ///
  /// A keyboard handler rather than a [Focus] around the screen: on desktop,
  /// clicking outside the search field moves focus to the route's scope,
  /// above any such [Focus], and the shortcut would stop working.
  bool _onKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!mounted) return false;
    // Escape leaves selection mode wherever the focus is on this screen. In
    // the search field the field's own handler does it (see _onSearchKey);
    // over a menu or a dialog the route is not current and Escape closes
    // that instead.
    if (_selecting &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        ModalRoute.isCurrentOf(context) == true) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.findAncestorStateOfType<EditableTextState>() != null) {
        return false;
      }
      _exitSelection();
      return true;
    }
    final isPaste = _pasteKeys.any((k) => k.accepts(event, keyboard));
    final isFind = _findKeys.any((k) => k.accepts(event, keyboard));
    final isNew = _newKeys.any((k) => k.accepts(event, keyboard));
    if (!(isPaste || isFind || isNew) ||
        ModalRoute.isCurrentOf(context) == false) {
      return false;
    }
    if (isFind) {
      _searchFocus.requestFocus();
      return true;
    }
    if (isNew) {
      _add();
      return true;
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
  ///
  /// Never a dead end. A screenshot that was read only in part still opens
  /// the sheet, with what was found and the text to pick from. One that could
  /// not be read at all gets a message with what to try, and a way forward.
  Future<void> _paste() async {
    if (_pasting) return;
    final s = context.services;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pasting = true);
    OcrResult? found;
    ScanResult? scan;
    ScanError? failure;
    var screenshot = false;
    try {
      final clip = await s.bridge.readClipboard();
      final image = clip.imagePath;
      final text = clip.text;
      if (image != null) {
        screenshot = true;
        final token = _scanning = ScanCancelToken();
        try {
          if (mounted) {
            scan = await OcrScanner.forPlatform(s.bridge)
                .scan(image, cancel: token);
          }
        } on Object {
          failure = ScanError.failed;
        } finally {
          // Our plaintext copy of the screenshot: never keep it. (The
          // scanner removes its own enlarged copies.)
          _deleteQuietly(image);
          if (identical(_scanning, token)) _scanning = null;
        }
      } else {
        if (text != null && !s.clipboard.isOwnCopy(text)) {
          found = OcrCredentialParser().parseText(text);
        }
        // A screenshot was copied but could not be turned into a file: say
        // so, rather than asking for a screenshot the user just copied. Text
        // that holds a login still wins.
        if (clip.imageError != null &&
            (found == null ||
                (found.username == null && found.password == null))) {
          screenshot = true;
          failure = ScanError.unsupportedImage;
          found = null;
        }
      }
    } on Object {
      found = null;
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
    if (!mounted) return;

    if (scan != null || failure != null) {
      final read = scan;
      if (read == null || ocrFoundNothing(read)) {
        final action = await showOcrFailureDialog(
          context,
          error: failure ?? ocrFailureOf(read!),
          passes: read?.passes ?? const [],
        );
        if (!mounted) return;
        switch (action) {
          case OcrFailureAction.again:
            return _paste();
          case OcrFailureAction.byHand:
            final saved = await QuickSaveSheet.show(
              context,
              const OcrResult(chips: []),
            );
            if (saved && mounted) {
              await offerClearClipboard(context, screenshot: true);
            }
          case null:
            break;
        }
        return;
      }
      found = read.best;
    } else if (found == null ||
        (found.username == null && found.password == null)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.pasteNothingFound)));
      return;
    }
    final saved = await QuickSaveSheet.show(
      context,
      found,
      passes: scan?.passes ?? const [],
    );
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

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------

  /// The header buttons. From 600 px wide there is room for "Paste" (the
  /// primary action) and "Add entry" here; on a phone they are the floating
  /// buttons instead.
  List<Widget> _actions(BuildContext context, {required bool roomy}) {
    final l = context.l10n;
    final t = context.tokens;
    final services = context.services;
    final session = services.session;
    return [
      if (roomy) ...[
        IconButton(
          tooltip: l.pasteLogin,
          style: IconButton.styleFrom(
            backgroundColor: t.strong,
            foregroundColor: t.onStrong,
            disabledBackgroundColor: t.strong.withValues(alpha: 0.5),
            disabledForegroundColor: t.onStrong,
          ),
          icon: _pasting
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.onStrong,
                  ),
                )
              : const Icon(Icons.content_paste),
          onPressed: _pasting ? null : _paste,
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(l.addEntry),
          onPressed: _add,
        ),
        const SizedBox(width: 4),
      ],
      if (services.sync != null)
        IconButton(
          tooltip: l.syncNow,
          icon: const Icon(Icons.sync_rounded),
          onPressed: () => syncNowFromButton(services.sync!),
        ),
      IconButton(
        tooltip: l.lock,
        icon: const Icon(Icons.lock_outline_rounded),
        onPressed: session.lock,
      ),
      PopupMenuButton<String>(
        popUpAnimationStyle: context.motionStyle,
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (v) => switch (v) {
          'select' => _startSelection(),
          'gen' => _open(const GeneratorScreen()),
          'ocr' => _open(const OcrImportScreen()),
          'dash' => _open(const DashboardScreen()),
          _ => _open(const SettingsScreen()),
        },
        itemBuilder: (_) => [
          if (session.entries.isNotEmpty)
            _menuItem('select', Icons.checklist_rounded, l.selectEntries, t),
          _menuItem('gen', Icons.password_rounded, l.generator, t),
          _menuItem(
            'ocr',
            Icons.document_scanner_outlined,
            l.scanScreenshot,
            t,
          ),
          _menuItem('dash', Icons.shield_outlined, l.securityDashboard, t),
          _menuItem('settings', Icons.settings_outlined, l.settings, t),
        ],
      ),
      const SizedBox(width: 4),
    ];
  }

  /// The selection bar's buttons: "Select all" (or "Clear selection" when
  /// every listed row is ticked) and "Delete". A wide window with normal text
  /// shows them with labels; otherwise they are icon buttons with tooltips.
  List<Widget> _selectionActions(
    BuildContext context,
    List<VaultEntry> listed,
    Set<String> picked, {
    required bool labelled,
  }) {
    final l = context.l10n;
    final t = context.tokens;
    final allTicked =
        listed.isNotEmpty && listed.every((e) => picked.contains(e.id));
    final toggleLabel = allTicked ? l.clearSelection : l.selectAll;
    final toggleIcon = Icon(
      allTicked ? Icons.deselect_rounded : Icons.select_all_rounded,
    );
    final VoidCallback? toggle = listed.isEmpty
        ? null
        : () => _toggleAll(listed);
    final VoidCallback? delete = picked.isEmpty || _deleting
        ? null
        : () => _deletePicked(picked, listed);
    return [
      if (labelled) ...[
        TextButton.icon(
          icon: toggleIcon,
          label: Text(toggleLabel),
          onPressed: toggle,
        ),
        const SizedBox(width: 8),
        PrimaryButton(
          destructive: true,
          glow: false,
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: delete,
          child: Text(l.delete),
        ),
        const SizedBox(width: 16),
      ] else ...[
        IconButton(tooltip: toggleLabel, icon: toggleIcon, onPressed: toggle),
        IconButton(
          tooltip: l.deleteSelected,
          style: IconButton.styleFrom(foregroundColor: t.error),
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: delete,
        ),
        const SizedBox(width: 4),
      ],
    ];
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    AppTokens t,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: t.accent2),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );

  /// The search pill. Escape clears it (or leaves it), and in the two-pane
  /// layout the arrow keys move the open row.
  Widget _searchField(
    BuildContext context,
    double height, {
    bool wide = false,
  }) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onSearchKey(event, wide: wide),
      // SearchBar's InkWell makes the whole pill tappable; without a label it
      // is an unnamed tap target for a screen reader.
      child: Semantics(
        container: true,
        label: l.search,
        child: SearchBar(
          controller: _search,
          focusNode: _searchFocus,
          hintText: l.search,
          leading: Icon(Icons.search_rounded, color: t.muted),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: l.clear,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(_search.clear),
              ),
          ],
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(t.surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? BorderSide(color: t.focusRing, width: 2)
                : BorderSide(color: t.outline),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsetsDirectional.only(start: 16, end: 8),
          ),
          textStyle: WidgetStatePropertyAll(
            tt.bodyLarge!.copyWith(color: t.ink),
          ),
          hintStyle: WidgetStatePropertyAll(
            tt.bodyLarge!.copyWith(color: t.muted),
          ),
          constraints: BoxConstraints(minHeight: height),
        ),
      ),
    );
  }

  /// "All items", "Favorites" and one pill per tag, in a row that scrolls.
  Widget _chips(
    BuildContext context,
    List<String> tags,
    double height,
    double side,
  ) {
    final l = context.l10n;
    final everything = !_favoritesOnly && _tag == null;
    Widget gap() => const SizedBox(width: 8);
    // Keyboard focus brings the pill to the middle of the row. The default
    // traversal scroll left it flush with (or, in Arabic, outside) the edge
    // of the pane.
    Widget pill(Widget chip) => _RevealOnFocus(child: Center(child: chip));
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side),
        children: [
          pill(
            PillChip(
              label: l.allItems,
              selected: everything,
              onSelected: (_) => setState(() {
                _favoritesOnly = false;
                _tag = null;
              }),
            ),
          ),
          gap(),
          pill(
            PillChip(
              label: l.favorites,
              icon: Icons.star_rounded,
              selected: _favoritesOnly,
              onSelected: (v) => setState(() => _favoritesOnly = v),
            ),
          ),
          for (final tag in tags) ...[
            gap(),
            pill(
              PillChip(
                label: tag,
                selected: _tag == tag,
                onSelected: (v) => setState(() => _tag = v ? tag : null),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Nothing to list: a new vault, or filters that match nothing.
  Widget _empty(BuildContext context, {required bool vaultEmpty}) {
    final l = context.l10n;
    if (!vaultEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l.noResults,
        action: OutlinedButton(onPressed: _clearFilters, child: Text(l.clear)),
      );
    }
    return EmptyState(
      icon: Icons.lock_outline_rounded,
      title: l.noEntries,
      message: appTaglineFor(Localizations.maybeLocaleOf(context)),
      action: PrimaryButton(
        icon: const Icon(Icons.add_rounded),
        onPressed: _add,
        child: Text(l.addEntry),
      ),
      secondaryAction: OutlinedButton.icon(
        icon: const Icon(Icons.content_paste_rounded),
        label: Text(l.pasteLogin),
        onPressed: _pasting ? null : _paste,
      ),
    );
  }

  /// Paste (primary) and Add (secondary) for phones.
  Widget _fabs(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final add = DecoratedBox(
      decoration: ShapeDecoration(
        shape: const CircleBorder(),
        shadows: [
          BoxShadow(
            color: t.shadow,
            offset: const Offset(0, 6),
            blurRadius: 22,
          ),
        ],
      ),
      child: FloatingActionButton(
        heroTag: 'add',
        tooltip: l.addEntry,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: t.surface3,
        foregroundColor: t.accent2,
        hoverColor: t.surface3,
        shape: CircleBorder(side: BorderSide(color: t.line2)),
        onPressed: _add,
        child: const Icon(Icons.add_rounded),
      ),
    );
    final paste = DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        shadows: [
          BoxShadow(
            color: t.buttonGlow,
            offset: const Offset(0, 8),
            blurRadius: 26,
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'paste',
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        onPressed: _pasting ? null : _paste,
        icon: _pasting
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.onStrong,
                ),
              )
            : const Icon(Icons.content_paste_rounded),
        label: Text(l.pasteLogin),
      ),
    );
    // Large system text makes the Paste button too wide to sit next to Add.
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [add, const SizedBox(height: 12), paste],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [add, const SizedBox(width: 12), paste],
    );
  }

  /// The rows of [items] under a small heading (the active filter and how
  /// many entries match).
  Widget _list(
    BuildContext context,
    List<VaultEntry> items, {
    required EdgeInsets padding,
    required bool wide,
    required Set<String> picked,
  }) {
    final l = context.l10n;
    final settings = context.services.settings;
    final sync = context.services.sync;
    final deletedElsewhere = sync?.pendingMassDeletion;
    final label = _tag ?? (_favoritesOnly ? l.favorites : l.allItems);
    return ListView.builder(
      controller: _scroll,
      padding: padding,
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // UPDATE-BANNER-SLOT: the auto-update team puts its "update
              // ready" banner here (a SurfaceCard(featured: true) with a
              // gap of 12 below it). The list scrolls it away with the rest.
              //
              // Another device deleted most of the vault and sync here is
              // waiting for the user to apply or keep it.
              if (sync != null && deletedElsewhere != null) ...[
                SyncDeletionPrompt(sync: sync, count: deletedElsewhere),
                const SizedBox(height: 12),
              ],
              _Heading(
                label: label,
                count: items.length,
                sort: settings.entrySort,
                onSort: (v) => settings.entrySort = v,
              ),
            ],
          );
        }
        final e = items[i - 1];
        final open = wide && !_selecting && e.id == _selectedId;
        return Padding(
          key: open ? _selectedRowKey : ValueKey(e.id),
          padding: const EdgeInsets.only(bottom: AppSpace.tileGap),
          child: Reveal(
            index: i - 1,
            enabled: _intro && i <= 8,
            child: _EntryRow(
              entry: e,
              selected: open,
              selecting: _selecting,
              picked: picked.contains(e.id),
              onTap: () => _onRowTap(e, wide: wide),
              onLongPress: () =>
                  _selecting ? _toggle(e.id) : _startSelection(e.id),
              onPick: () => _startSelection(e.id),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = context.services;
    final session = services.session;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final wide = width >= AppLayout.expanded;
    final roomy = width >= AppLayout.compact;
    final scaler = media.textScaler;
    // Large system text makes the pills and the search field taller.
    final searchH = math.max(52.0, scaler.scale(16 * 1.5) + 24);
    final chipsH = math.max(48.0, scaler.scale(14 * 1.35) + 18) + 8;
    final toolbarH = wide ? 72.0 : kToolbarHeight;
    // Phone and tablet: search and pills are part of the header.
    final bottomH = wide ? 0.0 : 6 + searchH + 8 + chipsH + 4;
    final topInset = media.padding.top + toolbarH + bottomH;

    return ListenableBuilder(
      // The sort order is a setting; the entries and their last-used times
      // come from the session (see _usedOrder for when the order follows
      // them); sync can be waiting for the user (SyncDeletionPrompt).
      listenable: Listenable.merge([
        session,
        services.settings,
        if (services.sync != null) services.sync,
      ]),
      builder: (context, _) {
        final items = _filtered(services);
        final picked = _pickedLive(session);
        final tags = session.allTags.toList()..sort();
        final vaultEmpty = session.entries.isEmpty;
        final selected = _selectedId == null
            ? null
            : session.byId(_selectedId!);
        final gutter = AppSpace.gutter(width);
        // Side padding that centres a column of at most 640 on a tablet.
        final side = MaxWidthBody.insets(
          context,
          maxWidth: AppLayout.form,
        ).left;

        final Widget body;
        if (wide) {
          final listW = (width * 0.32).clamp(360.0, 420.0);
          body = Row(
            // Stretch: the detail pane is as tall as the window, so its
            // content starts at the top whatever the entry's length.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: topInset + 4),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      child: SizedBox(
                        height: searchH,
                        child: _searchField(context, searchH, wide: true),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _chips(context, tags, chipsH, gutter),
                    Expanded(
                      child: items.isEmpty
                          ? _empty(context, vaultEmpty: vaultEmpty)
                          : _list(
                              context,
                              items,
                              wide: true,
                              picked: picked,
                              padding: EdgeInsets.fromLTRB(
                                gutter,
                                8,
                                gutter,
                                24,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: topInset),
                child: VerticalDivider(width: 1, thickness: 1, color: t.line),
              ),
              Expanded(
                child: selected == null
                    ? Padding(
                        padding: EdgeInsets.only(top: topInset),
                        child: const _NothingSelected(),
                      )
                    : EntryDetailView(
                        key: ValueKey(selected.id),
                        entryId: selected.id,
                        embedded: true,
                        topInset: topInset + 8,
                        onDeleted: () => setState(() => _selectedId = null),
                      ),
              ),
            ],
          );
        } else if (items.isEmpty) {
          body = Padding(
            padding: EdgeInsets.only(top: topInset),
            child: _empty(context, vaultEmpty: vaultEmpty),
          );
        } else {
          body = _list(
            context,
            items,
            wide: false,
            picked: picked,
            padding: EdgeInsets.fromLTRB(
              side,
              topInset + 8,
              side,
              // Room for the floating buttons below the last entry.
              media.padding.bottom + (vaultEmpty ? 24 : 112),
            ),
          );
        }

        final keyboardOpen = media.viewInsets.bottom > 0;
        final scaffold = Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(
            toolbarHeight: toolbarH,
            alwaysGlass: _selecting,
            leading: _selecting
                ? IconButton(
                    tooltip: context.l10n.exitSelection,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _exitSelection,
                  )
                : null,
            title: _selecting
                ? _SelectionCount(count: picked.length)
                : const BrandLockup(),
            actions: _selecting
                ? _selectionActions(
                    context,
                    items,
                    picked,
                    labelled: wide && scaler.scale(10) <= 13,
                  )
                : _actions(context, roomy: roomy),
            bottom: wide
                ? null
                : _HeaderBottom(
                    height: bottomH,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: side),
                          child: SizedBox(
                            height: searchH,
                            child: _searchField(context, searchH),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _chips(context, tags, chipsH, side),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
          ),
          body: body,
          floatingActionButton:
              roomy || vaultEmpty || keyboardOpen || _selecting
              ? null
              : _fabs(context),
        );
        // Back (the system button or gesture) leaves selection mode first.
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _selecting) _exitSelection();
          },
          child: scaffold,
        );
      },
    );
  }
}

/// The search field and the pills under the toolbar, as the `bottom` of the
/// glass app bar. Its height is computed from the text size, so large text
/// cannot overflow it.
class _HeaderBottom extends StatelessWidget implements PreferredSizeWidget {
  const _HeaderBottom({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: child);
}

/// "All items" (or the active filter), how many entries match and the sort
/// control. The sort pill sits at the end of the line, or under the label
/// when large text or a long tag name leaves no room for it.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.label,
    required this.count,
    required this.sort,
    required this.onSort,
  });

  final String label;
  final int count;
  final EntrySort sort;
  final ValueChanged<EntrySort> onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 0, 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: EntryTitle(
                    label,
                    style: tt.titleSmall!.copyWith(color: t.muted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$count',
                style: AppText.numeral.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: t.accent2,
                ),
              ),
            ],
          ),
          EntrySortButton(value: sort, onChanged: onSort),
        ],
      ),
    );
  }
}

/// The title of the selection bar: how many entries are ticked. A live
/// region, so a screen reader says the new count after every tick.
class _SelectionCount extends StatelessWidget {
  const _SelectionCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Shrinks rather than cuts: with very large text on a small phone
    // "عنصران محددان" would otherwise lose the half that says what it is.
    return Semantics(
      liveRegion: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          context.l10n.selectedCount(count),
          maxLines: 1,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// One entry in the list: site icon, name, username in mono, a star if it is
/// a favourite and a button that copies the password.
///
/// The whole card opens the entry. The text is a [ListTile] for its layout
/// (it grows with the text size and mirrors in Arabic); the card, not the
/// tile, takes the tap, so the card can light up under a mouse.
///
/// In selection mode a check box leads the row, a tap ticks it, the copy
/// button is gone and a screen reader hears one node: "name, username",
/// selected or not. Under a mouse pointer (outside selection mode) the site
/// icon turns into a check box that starts selection mode with this row.
class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onPick,
    this.selecting = false,
    this.picked = false,
  });

  final VaultEntry entry;

  /// The open row of the two-pane layout.
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// The check box shown under a mouse pointer was clicked.
  final VoidCallback onPick;

  /// Selection mode, and whether this row is ticked.
  final bool selecting;
  final bool picked;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hover = false;

  void _setHover(bool v) {
    if (_hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final e = widget.entry;
    final selecting = widget.selecting;
    final name = e.title.isEmpty ? e.host : e.title;
    final shown = name.isEmpty ? '—' : name;
    final lit = selecting ? widget.picked : widget.selected;

    // The row itself is the control for the keyboard and a screen reader,
    // so the box is for the pointer only: no focus stop, no second node.
    Widget box(bool value, VoidCallback onChanged) => ExcludeSemantics(
      child: ExcludeFocus(
        child: Checkbox(value: value, onChanged: (_) => onChanged()),
      ),
    );

    final icon = SiteIcon(url: e.url, title: name, selected: lit);
    final leading = selecting
        ? icon
        : AnimatedSwitcher(
            duration: context.motion(AppMotion.fast),
            child: _hover
                ? SizedBox.square(
                    key: const ValueKey('box'),
                    dimension: 44,
                    child: Center(child: box(false, widget.onPick)),
                  )
                : KeyedSubtree(key: const ValueKey('icon'), child: icon),
          );

    Widget card = SurfaceCard(
      selected: lit,
      hoverLift: 0,
      padding: EdgeInsets.zero,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Row(
        children: [
          // Where the hover box was, so the box stays under the pointer.
          if (selecting)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: SizedBox(
                width: 44,
                child: Center(child: box(widget.picked, widget.onTap)),
              ),
            ),
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsetsDirectional.only(
                start: selecting ? 10 : 14,
                end: 4,
              ),
              horizontalTitleGap: 14,
              leading: leading,
              title: EntryTitle(shown),
              subtitle: e.username.isEmpty ? null : LtrText(e.username),
            ),
          ),
          if (e.favorite)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Icon(
                Icons.star_rounded,
                color: t.accent2,
                size: 20,
                semanticLabel: l.favorite,
              ),
            ),
          if (selecting)
            const SizedBox(width: 10)
          else
            IconButton(
              tooltip: l.copy,
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: e.password.isEmpty
                  ? null
                  : () => copySecretWithToast(
                      context,
                      e.password,
                      usedEntryId: e.id,
                    ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
    if (selecting) {
      card = Semantics(
        container: true,
        label: [
          shown,
          if (e.username.isNotEmpty) e.username,
          if (e.favorite) l.favorite,
        ].join(', '),
        selected: widget.picked,
        checked: widget.picked,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        excludeSemantics: true,
        child: card,
      );
    }
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: card,
    );
  }
}

/// The detail pane of the two-pane layout while no entry is open.
class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.maybeLocaleOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 72, glow: true),
              const SizedBox(height: 28),
              Text(
                appNameFor(locale),
                textAlign: TextAlign.center,
                style: tt.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                appTaglineFor(locale),
                textAlign: TextAlign.center,
                style: tt.bodyMedium!.copyWith(color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies [value] (a password, a username, a one-time code) to the clipboard
/// and says so, without the value and with when the clipboard clears.
///
/// When the value belongs to an entry, the entry counts as just used for the
/// "Recently used" order (`VaultSession.markUsed`): pass its id as
/// [usedEntryId], or call this from inside an [EntryUseScope].
Future<void> copySecretWithToast(
  BuildContext context,
  String value, {
  String? usedEntryId,
}) async {
  final s = context.services;
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final used = usedEntryId ?? EntryUseScope.maybeOf(context);
  await s.clipboard.copySecret(value);
  if (used != null) unawaited(s.session.markUsed(used));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(l.copied(s.settings.clipboardClearSeconds))),
    );
}

/// Scrolls its row so the child is in the middle whenever it (or something in
/// it) gets keyboard focus. It is not a focus stop of its own.
class _RevealOnFocus extends StatelessWidget {
  const _RevealOnFocus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        // Keyboard navigation only: a tap or click leaves the row alone.
        if (!focused ||
            FocusManager.instance.highlightMode !=
                FocusHighlightMode.traditional) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: context.motion(AppMotion.fast),
            curve: AppMotion.ease,
          );
        });
      },
      child: child,
    );
  }
}
