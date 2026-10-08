import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'services/platform_bridge.dart';
import 'services/vault_session.dart';
import 'ui/app_scope.dart';
import 'ui/home_screen.dart';
import 'ui/ocr/ocr_import_screen.dart';
import 'ui/quick_search_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/unlock_screen.dart';
import 'ui/update/update_gate.dart';
import 'ui/widgets/app_shell.dart';

class HisnApp extends StatefulWidget {
  const HisnApp({super.key, required this.services});

  final AppServices services;

  @override
  State<HisnApp> createState() => _HisnAppState();
}

class _HisnAppState extends State<HisnApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _idle;
  bool _obscured = false;
  bool _captured = false;
  VaultState? _lastState;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  PickedImage? _pendingShare;

  AppServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.session.addListener(_onSessionChanged);
    s.session.onLock.add(s.clipboard.clearNow);
    if (s.favicons case final icons?) s.session.onLock.add(icons.clear);
    HardwareKeyboard.instance.addHandler(_onKey);
    PlatformBridge.listen(onCapture: (c) => setState(() => _captured = c));
    _initShareIntent();
    _initHotkey();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.session.removeListener(_onSessionChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _shareSub?.cancel();
    _idle?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    final st = s.session.state;
    if (st != _lastState) {
      _lastState = st;
      if (st == VaultState.unlocked) {
        _resetIdle();
        unawaited(s.sync?.onUnlocked());
        s.prefetchIcons();
        final share = _pendingShare;
        if (share != null) {
          _pendingShare = null;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _navigator.currentState?.push(
              MaterialPageRoute<void>(
                builder: (_) => OcrImportScreen(initial: share),
              ),
            ),
          );
        }
      } else {
        _idle?.cancel();
        // Drop every route that may show decrypted data.
        _navigator.currentState?.popUntil((r) => r.isFirst);
      }
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Auto-lock
  // ---------------------------------------------------------------------------

  void _resetIdle() {
    _idle?.cancel();
    if (!s.session.isUnlocked) return;
    _idle = Timer(
      Duration(seconds: s.settings.autoLockSeconds),
      s.session.lock,
    );
  }

  bool _onKey(KeyEvent _) {
    _resetIdle();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // iOS takes the app-switcher snapshot here: cover the content.
        setState(() => _obscured = true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        setState(() => _obscured = true);
        // On desktop "hidden" = minimised; only lock there if configured too.
        if (s.settings.lockOnBackground) s.session.lock();
      case AppLifecycleState.resumed:
        setState(() => _obscured = false);
        _resetIdle();
      case AppLifecycleState.detached:
        s.session.lock();
    }
  }

  // ---------------------------------------------------------------------------
  // Share-to-app (Android / iOS)
  // ---------------------------------------------------------------------------

  void _initShareIntent() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    void handle(List<SharedMediaFile> files) {
      final img = files
          .where((f) => f.type == SharedMediaType.image)
          .firstOrNull;
      if (img == null) return;
      // The plugin hands us a copy in our container: always deleted after OCR.
      final picked = PickedImage(path: img.path);
      if (s.session.isUnlocked) {
        _navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => OcrImportScreen(initial: picked),
          ),
        );
      } else {
        _pendingShare = picked;
      }
      ReceiveSharingIntent.instance.reset();
    }

    ReceiveSharingIntent.instance.getInitialMedia().then(handle);
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(handle);
  }

  // ---------------------------------------------------------------------------
  // Windows global hotkey -> quick search
  // ---------------------------------------------------------------------------

  Future<void> _initHotkey() async {
    if (kIsWeb || !Platform.isWindows) return;
    await hotKeyManager.unregisterAll();
    await hotKeyManager.register(
      HotKey(
        key: PhysicalKeyboardKey.space,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      ),
      keyDownHandler: (_) async {
        await windowManager.show();
        await windowManager.focus();
        if (s.session.isUnlocked) {
          _navigator.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => const QuickSearchScreen()),
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------

  Widget _home() => switch (s.session.state) {
    VaultState.loading => const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    ),
    VaultState.noVault => const SetupScreen(),
    VaultState.locked => const UnlockScreen(),
    VaultState.unlocked => const HomeScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final locale = s.settings.locale;
    return AppScope(
      services: s,
      child: ListenableBuilder(
        listenable: s.settings,
        builder: (context, _) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _resetIdle(),
          onPointerMove: (_) => _resetIdle(),
          child: MaterialApp(
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
            // The type scale follows the language (Outfit / IBM Plex Sans
            // Arabic). AppShell below re-resolves it for the language that is
            // really in use, which also covers "follow the system language".
            theme: AppTheme.light(locale),
            darkTheme: AppTheme.dark(locale),
            themeMode: s.settings.themeMode,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _home(),
            builder: (context, child) => AppShell(
              child: Stack(
                children: [
                  if (child != null)
                    UpdateGate(
                      controller: s.updates,
                      navigatorKey: _navigator,
                      triggers: s.session,
                      child: child,
                    ),
                  if (_obscured || _captured)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
