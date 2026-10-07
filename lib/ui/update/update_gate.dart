import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/update/app_version.dart';
import '../../services/update/update_controller.dart';
import '../../services/update/update_providers.dart';
import '../../services/update/windows_installer.dart';
import '../theme/tokens.dart';
import 'update_banner.dart';
import 'update_format.dart';
import 'update_release_links.dart';
import 'update_sheet.dart';

/// Wraps the app's content (the `Navigator`) and takes care of updates:
///
/// * It runs the throttled automatic check a few seconds after start-up, when
///   the vault state changes (unlock) and when the app returns to the
///   foreground. `UpdateController.checkAutomatically` does the throttling
///   (once a day), honours the "check automatically" switch and sweeps the
///   leftovers of the last update.
/// * When a newer signed version exists, a dismissible [UpdateBanner] appears
///   at the top. It pushes the page down instead of covering the app bar, so
///   nothing becomes unreachable. Tapping it opens the [UpdateSheet].
/// * It never downloads or installs by itself. Only the buttons in the sheet
///   do, and installing is always a second, explicit tap.
/// * On Windows it reports a swap that was rolled back or never started
///   (`WindowsUpdateInstaller.readHelperResult`), once.
///
/// With a null or disabled [controller] (development builds, other platforms,
/// the autofill entry point) it is just [child], so there is no cost and
/// nothing to see.
///
/// Place it where `MaterialApp.builder` puts its content, above the
/// `Navigator`, and pass the navigator's key so the sheet opens inside it:
///
/// ```dart
/// builder: (context, child) => AppShell(
///   child: UpdateGate(
///     controller: services.updates,
///     navigatorKey: _navigator,
///     triggers: services.session,
///     child: child!,
///   ),
/// ),
/// ```
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
    this.triggers,
    this.startDelay = const Duration(seconds: 3),
    this.settleDelay = const Duration(seconds: 12),
    this.openUrl,
    this.readHelperResult,
    this.installed,
  });

  final UpdateController? controller;

  /// The key of the app's `Navigator`: the sheet is opened on it.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Notified when the vault locks or unlocks (pass the session). Each
  /// notification may trigger a throttled check.
  final Listenable? triggers;

  /// Wait after start-up (and after a trigger) before checking, so the check
  /// never competes with unlocking.
  final Duration startDelay;

  /// How long an "up to date" or check-failed message stays before the
  /// controller goes back to idle (so automatic checks can run again).
  final Duration settleDelay;

  /// See [UpdateSheet.openUrl].
  final UrlOpener? openUrl;

  /// Reads the Windows swap script's last result; defaults to
  /// `WindowsUpdateInstaller.readHelperResult` on Windows and nothing
  /// elsewhere. For tests.
  final Future<WindowsUpdateHelperResult> Function()? readHelperResult;

  /// See [UpdateSheet.installed].
  final AppVersion? installed;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  Timer? _checkTimer;
  Timer? _settleTimer;
  bool _sheetOpen = false;

  // The banner the user closed: the same step of the same build stays hidden.
  UpdateStatus? _hiddenStatus;
  int? _hiddenBuild;

  WindowsUpdateHelperResult _notice = WindowsUpdateHelperResult.none;
  bool _noticeHidden = false;

  UpdateController? get _c {
    final c = widget.controller;
    return c != null && c.enabled ? c : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  @override
  void didUpdateWidget(UpdateGate old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.triggers != widget.triggers) {
      _detach(old);
      _attach();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach(widget);
    _checkTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  void _attach() {
    final c = _c;
    if (c == null) return;
    c.addListener(_onController);
    widget.triggers?.addListener(_onTrigger);
    // The first check always runs (it also sweeps the last update's files);
    // later ones only when one is due.
    _scheduleCheck(force: true);
    unawaited(_readNotice());
  }

  void _detach(UpdateGate gate) {
    gate.controller?.removeListener(_onController);
    gate.triggers?.removeListener(_onTrigger);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleCheck();
  }

  void _onTrigger() => _scheduleCheck();

  void _scheduleCheck({bool force = false}) {
    final c = _c;
    if (c == null || (_checkTimer?.isActive ?? false)) return;
    if (!force && !c.autoCheckDue) return;
    _checkTimer = Timer(widget.startDelay, () {
      if (mounted) unawaited(_c?.checkAutomatically());
    });
  }

  /// After a manual check the "up to date" or "could not check" message is
  /// shown for a while and then cleared, so that the controller is idle again
  /// and the next automatic check is not blocked by an old message.
  void _onController() {
    final c = _c;
    if (c == null) return;
    final message =
        c.status == UpdateStatus.upToDate ||
        (c.status == UpdateStatus.error && c.manifest == null);
    if (!message || _sheetOpen) {
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }
    _settleTimer ??= Timer(widget.settleDelay, () {
      _settleTimer = null;
      final now = _c;
      if (!mounted || now == null || _sheetOpen) return;
      if (now.status == UpdateStatus.upToDate ||
          (now.status == UpdateStatus.error && now.manifest == null)) {
        now.dismiss();
      }
    });
  }

  Future<void> _readNotice() async {
    final Future<WindowsUpdateHelperResult> Function()? read =
        widget.readHelperResult ??
        (Platform.isWindows ? WindowsUpdateInstaller.readHelperResult : null);
    if (read == null) return;
    final WindowsUpdateHelperResult result;
    try {
      result = await read();
    } on Object {
      return;
    }
    if (!mounted) return;
    if (result == WindowsUpdateHelperResult.rolledBack ||
        result == WindowsUpdateHelperResult.rollbackFailed ||
        result == WindowsUpdateHelperResult.aborted) {
      setState(() => _notice = result);
    }
  }

  BuildContext? get _overlayContext {
    final context = widget.navigatorKey.currentState?.overlay?.context;
    return context != null && context.mounted ? context : null;
  }

  Future<void> _openSheet() async {
    final c = _c;
    final context = _overlayContext;
    if (c == null || context == null || _sheetOpen) return;
    _sheetOpen = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    try {
      await showUpdateSheet(
        context,
        controller: c,
        openUrl: widget.openUrl,
        installed: widget.installed,
        onLater: () => _hide(c.status, c.manifest?.build),
      );
    } finally {
      _sheetOpen = false;
      if (mounted) _onController();
    }
  }

  Future<void> _openNotice() async {
    final context = _overlayContext;
    if (context == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l = AppLocalizations.of(dialogContext);
        final text = switch (_notice) {
          WindowsUpdateHelperResult.rollbackFailed => l.updateNoticeDamaged,
          WindowsUpdateHelperResult.aborted => l.updateNoticeAborted,
          _ => l.updateNoticeRolledBack,
        };
        return AlertDialog(
          title: Text(l.updateNoticeTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(text),
                if (_notice == WindowsUpdateHelperResult.rollbackFailed) ...[
                  const SizedBox(height: 16),
                  UpdateReleaseLinks(openUrl: widget.openUrl),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l.close),
            ),
          ],
        );
      },
    );
    if (mounted) setState(() => _noticeHidden = true);
  }

  void _hide(UpdateStatus status, int? build) {
    if (!mounted) return;
    setState(() {
      _hiddenStatus = status;
      _hiddenBuild = build;
    });
  }

  /// The banner for the controller's current step, or null.
  Widget? _banner(BuildContext context, UpdateController c) {
    final l = AppLocalizations.of(context);
    final status = c.status;
    final build = c.manifest?.build;
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final hidden = _hiddenStatus == status && _hiddenBuild == build;
    final hide = l.updateHideBanner;

    UpdateBanner? update;
    if (!hidden) {
      void open() => unawaited(_openSheet());
      void close() => _hide(status, build);
      update = switch (status) {
        UpdateStatus.available when c.manifest != null => UpdateBanner(
          title: l.updateAvailable,
          subtitle: l.updateVersionNumber(
            isolateLtr(c.manifest!.version.version),
          ),
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        UpdateStatus.downloading => UpdateBanner(
          title: l.updateBannerDownloading(
            updatePercent(c.progress).toString(),
          ),
          progress: c.progress ?? 0,
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        UpdateStatus.verifying => UpdateBanner(
          title: l.updateVerifying,
          indeterminate: true,
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        UpdateStatus.readyToInstall => UpdateBanner(
          title: l.updateReadyTitle,
          subtitle: l.updateTapForDetails,
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        UpdateStatus.installing => UpdateBanner(
          title: windows ? l.updateInstallingWindows : l.updateInstalling,
          indeterminate: true,
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        // A failed download or install of a known update. A failed manual
        // check is shown where it was asked for (the settings tile).
        UpdateStatus.error when c.manifest != null => UpdateBanner(
          title: l.updateBannerFailed,
          subtitle: l.updateTapForDetails,
          tone: UpdateBannerTone.error,
          onOpen: open,
          onHide: close,
          hideLabel: hide,
        ),
        _ => null,
      };
    }
    if (update != null) return update;

    if (_notice != WindowsUpdateHelperResult.none && !_noticeHidden) {
      return UpdateBanner(
        title: l.updateNoticeTitle,
        subtitle: l.updateTapForDetails,
        tone: UpdateBannerTone.error,
        onOpen: () => unawaited(_openNotice()),
        onHide: () => setState(() => _noticeHidden = true),
        hideLabel: hide,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final banner = _banner(context, c);
        // `verticalDirection: up` puts the LAST child on top. The page is
        // listed first on purpose: semantics are gathered in paint order, and
        // the Navigator's first route has a modal barrier that blocks
        // everything painted before it, which would hide a banner painted
        // earlier from screen readers.
        return Column(
          verticalDirection: VerticalDirection.up,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // The banner took the top safe-area inset; the page below must
              // not pad for the status bar a second time.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: banner != null,
                child: widget.child,
              ),
            ),
            // With "reduce motion" on the banner is simply there. (AnimatedSize
            // with a zero duration re-dirties itself during layout.)
            if (MediaQuery.disableAnimationsOf(context))
              banner ?? const SizedBox(width: double.infinity)
            else
              AnimatedSize(
                duration: AppMotion.page,
                curve: AppMotion.ease,
                alignment: Alignment.topCenter,
                child: banner ?? const SizedBox(width: double.infinity),
              ),
          ],
        );
      },
    );
  }
}
