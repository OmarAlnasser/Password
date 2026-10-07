import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../data/models/vault_entry.dart';
import '../services/ocr/ocr_parser.dart';
import '../services/ocr/ocr_scanner.dart';
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
import 'widgets/empty_state.dart';
import 'widgets/glass_bar.dart';
import 'widgets/max_width_body.dart';
import 'widgets/pill_chip.dart';
import 'widgets/primary_button.dart';
import 'widgets/reveal.dart';
import 'widgets/secret_text.dart';
import 'widgets/site_icon.dart';
import 'widgets/surface_card.dart';

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

  /// True until the first frame is done: only the rows that are there when
  /// the screen first appears play their entrance, not rows that scroll in.
  bool _intro = true;

  /// The scan of a pasted screenshot in progress, if any.
  ScanCancelToken? _scanning;

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
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<VaultEntry> _filtered(VaultSession session) => session.entries
      .where((e) => !_favoritesOnly || e.favorite)
      .where((e) => _tag == null || e.tags.contains(_tag))
      .where((e) => e.matches(_search.text.trim()))
      .toList();

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

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

  /// Arrow keys in the search field of the two-pane layout: move the open row.
  void _moveSelection(int delta) {
    final items = _filtered(context.services.session);
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
      if (_search.text.isNotEmpty) {
        setState(_search.clear);
      } else {
        _searchFocus.unfocus();
      }
      return KeyEventResult.handled;
    }
    if (wide &&
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
          onPressed: () => services.sync!.syncNow(),
        ),
      IconButton(
        tooltip: l.lock,
        icon: const Icon(Icons.lock_outline_rounded),
        onPressed: session.lock,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (v) => switch (v) {
          'gen' => _open(const GeneratorScreen()),
          'ocr' => _open(const OcrImportScreen()),
          'dash' => _open(const DashboardScreen()),
          _ => _open(const SettingsScreen()),
        },
        itemBuilder: (_) => [
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
        textStyle: WidgetStatePropertyAll(tt.bodyLarge!.copyWith(color: t.ink)),
        hintStyle: WidgetStatePropertyAll(
          tt.bodyLarge!.copyWith(color: t.muted),
        ),
        constraints: BoxConstraints(minHeight: height),
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
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side),
        children: [
          Center(
            child: PillChip(
              label: l.allItems,
              selected: everything,
              onSelected: (_) => setState(() {
                _favoritesOnly = false;
                _tag = null;
              }),
            ),
          ),
          gap(),
          Center(
            child: PillChip(
              label: l.favorites,
              icon: Icons.star_rounded,
              selected: _favoritesOnly,
              onSelected: (v) => setState(() => _favoritesOnly = v),
            ),
          ),
          for (final tag in tags) ...[
            gap(),
            Center(
              child: PillChip(
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
        title: l.noEntries,
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
  }) {
    final l = context.l10n;
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
              _Heading(label: label, count: items.length),
            ],
          );
        }
        final e = items[i - 1];
        final selected = wide && e.id == _selectedId;
        return Padding(
          key: selected ? _selectedRowKey : ValueKey(e.id),
          padding: const EdgeInsets.only(bottom: AppSpace.tileGap),
          child: Reveal(
            index: i - 1,
            enabled: _intro && i <= 8,
            child: _EntryRow(
              entry: e,
              selected: selected,
              onTap: () => _openEntry(e, wide: wide),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = context.services.session;
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
      listenable: session,
      builder: (context, _) {
        final items = _filtered(session);
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
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(
            toolbarHeight: toolbarH,
            title: const BrandLockup(),
            actions: _actions(context, roomy: roomy),
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
          floatingActionButton: roomy || vaultEmpty || keyboardOpen
              ? null
              : _fabs(context),
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

/// "All items" (or the active filter) and how many entries match.
class _Heading extends StatelessWidget {
  const _Heading({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: EntryTitle(
                label,
                style: tt.titleSmall!.copyWith(color: t.muted),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
    );
  }
}

/// One entry in the list: site icon, name, username in mono, a star if it is
/// a favourite and a button that copies the password.
///
/// The whole card opens the entry. The text is a [ListTile] for its layout
/// (it grows with the text size and mirrors in Arabic); the card, not the
/// tile, takes the tap, so the card can light up under a mouse.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final VaultEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final e = entry;
    final name = e.title.isEmpty ? e.host : e.title;
    return SurfaceCard(
      selected: selected,
      hoverLift: 0,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: ListTile(
              contentPadding: const EdgeInsetsDirectional.only(
                start: 14,
                end: 4,
              ),
              horizontalTitleGap: 14,
              leading: SiteIcon(url: e.url, title: name, selected: selected),
              title: EntryTitle(name.isEmpty ? '—' : name),
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
          IconButton(
            tooltip: l.copy,
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: e.password.isEmpty
                ? null
                : () => copySecretWithToast(context, e.password),
          ),
          const SizedBox(width: 4),
        ],
      ),
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
