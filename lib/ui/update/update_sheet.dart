import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/update/app_version.dart';
import '../../services/update/update_controller.dart';
import '../../services/update/update_failure.dart';
import '../../services/update/update_installer.dart';
import '../../services/update/update_providers.dart';
import '../theme/tokens.dart';
import '../widgets/primary_button.dart';
import 'update_format.dart';
import 'update_messages.dart';
import 'update_progress_bar.dart';
import 'update_release_links.dart';

/// Shows [UpdateSheet]: a bottom sheet on phones, a centred dialog from 600 dp
/// up (DESIGN sections 8.10 and 8.11). [context] must sit below the app's
/// `Navigator`; `UpdateGate` passes the navigator's overlay context.
///
/// Completes when the sheet is closed. Closing it never stops a download:
/// the banner keeps showing it.
Future<void> showUpdateSheet(
  BuildContext context, {
  required UpdateController controller,
  UrlOpener? openUrl,
  VoidCallback? onLater,
  AppVersion? installed,
}) {
  final sheet = UpdateSheet(
    controller: controller,
    openUrl: openUrl,
    onLater: onLater,
    installed: installed,
  );
  if (MediaQuery.sizeOf(context).width >= AppLayout.compact) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.dialogRich),
          child: sheet,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => sheet,
  );
}

/// Everything about one update, one step at a time: what is new, the
/// buttons for the step the controller is in, progress, and plain-language
/// errors. It only ever calls the controller when the user taps a button;
/// nothing here downloads or installs by itself.
///
/// States ([UpdateStatus]): available (Update now / Later / Skip this
/// version), downloading (progress, Cancel), verifying, readyToInstall
/// (Install, with the Android permission and failure explanations),
/// installing ("Closing to install..." on Windows), checking, upToDate and
/// error. The sheet closes itself when the controller goes idle (after "Skip
/// this version").
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({
    super.key,
    required this.controller,
    this.openUrl,
    this.onLater,
    this.installed,
  });

  final UpdateController controller;

  /// Opens the release page in a browser; null where the app cannot (then only
  /// "Copy link" is offered). Defaults to [platformUrlOpener].
  final UrlOpener? openUrl;

  /// Called when the user taps "Later" (the gate hides its banner).
  final VoidCallback? onLater;

  /// The running version, for "You have 0.2.0". Defaults to
  /// [AppVersion.current].
  final AppVersion? installed;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  bool _closing = false;

  UpdateController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
    _onChanged();
  }

  @override
  void didUpdateWidget(UpdateSheet old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    super.dispose();
  }

  /// Nothing left to show (skipped, or a message was closed): leave.
  void _onChanged() {
    if (_c.status != UpdateStatus.idle || _closing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _c.status == UpdateStatus.idle) _close();
    });
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  void _later() {
    widget.onLater?.call();
    _close();
  }

  void _closeMessage() {
    _c.dismiss();
    _close();
  }

  Future<void> _retry() async {
    // A failed download or install goes back to "available" and downloads
    // again; a failed check is simply asked again.
    if (_c.manifest != null) {
      _c.dismiss();
      await _c.startDownload();
    } else {
      await _c.checkNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final c = _c;
    final status = c.status;
    final failure = status == UpdateStatus.error
        ? describeUpdateFailure(l, c.failure ?? UpdateFailure.internal)
        : null;
    final outcome = c.installOutcome;

    final title = switch (status) {
      UpdateStatus.idle || UpdateStatus.available => l.updateAvailable,
      UpdateStatus.checking => l.updateChecking,
      UpdateStatus.downloading => l.updateDownloading,
      UpdateStatus.verifying => l.updateVerifying,
      UpdateStatus.readyToInstall => l.updateReadyTitle,
      UpdateStatus.installing =>
        windows ? l.updateInstallingWindows : l.updateInstalling,
      UpdateStatus.upToDate => l.updateUpToDate,
      UpdateStatus.error => failure!.title,
    };

    final showFacts =
        c.manifest != null &&
        status != UpdateStatus.error &&
        status != UpdateStatus.checking &&
        status != UpdateStatus.upToDate &&
        status != UpdateStatus.idle;

    final body = <Widget>[];
    final actions = <Widget>[];
    switch (status) {
      case UpdateStatus.idle:
        break;
      case UpdateStatus.checking:
        body.add(const UpdateProgressBar());
        actions.add(
          OutlinedButton(onPressed: _c.cancel, child: Text(l.cancel)),
        );
      case UpdateStatus.available:
        body.add(_notes(context, l));
        body.add(
          Text(l.updateSkipNote, style: tt.bodySmall!.copyWith(color: t.muted)),
        );
        actions.addAll([
          TextButton(
            onPressed: () => unawaited(c.skipThisVersion()),
            child: Text(l.updateSkipVersion),
          ),
          OutlinedButton(onPressed: _later, child: Text(l.updateLater)),
          PrimaryButton(
            onPressed: () => unawaited(c.startDownload()),
            icon: const Icon(Icons.download_rounded),
            child: Text(l.updateNow),
          ),
        ]);
      case UpdateStatus.downloading:
        final size = c.asset?.size;
        body.add(
          UpdateProgressBar(value: c.progress ?? 0, label: l.updateDownloading),
        );
        body.add(
          Semantics(
            liveRegion: true,
            child: Text(
              size == null
                  ? '${updatePercent(c.progress)}%'
                  : l.updateDownloadProgress(
                      updatePercent(c.progress).toString(),
                      formatUpdateSize(l, size),
                    ),
              style: tt.bodyMedium!.copyWith(color: t.soft),
            ),
          ),
        );
        body.add(
          Text(
            l.updateDownloadBackground,
            style: tt.bodySmall!.copyWith(color: t.muted),
          ),
        );
        actions.add(
          OutlinedButton(
            onPressed: c.cancel,
            child: Text(l.updateCancelDownload),
          ),
        );
      case UpdateStatus.verifying:
        body.add(UpdateProgressBar(label: l.updateVerifying));
        body.add(
          Text(
            l.updateVerifyingNote,
            style: tt.bodyMedium!.copyWith(color: t.soft),
          ),
        );
      case UpdateStatus.readyToInstall:
        _ready(context, l, windows, outcome, body, actions);
      case UpdateStatus.installing:
        body.add(UpdateProgressBar(label: title));
        body.add(
          Text(
            windows ? l.updateReadyWindows : l.updateReadyAndroid,
            style: tt.bodyMedium!.copyWith(color: t.soft),
          ),
        );
      case UpdateStatus.upToDate:
        body.add(
          _Callout(
            tone: _Tone.good,
            icon: Icons.check_circle_outline,
            text: l.updateUpToDate,
          ),
        );
        actions.add(PrimaryButton(onPressed: _closeMessage, child: Text(l.ok)));
      case UpdateStatus.error:
        body.add(
          _Callout(
            tone: _Tone.error,
            icon: Icons.error_outline,
            text: failure!.body,
          ),
        );
        if (failure.offerReleasePage) {
          body.add(UpdateReleaseLinks(openUrl: widget.openUrl));
        }
        actions.add(TextButton(onPressed: _closeMessage, child: Text(l.close)));
        if (failure.canRetry) {
          actions.add(
            PrimaryButton(
              onPressed: () => unawaited(_retry()),
              icon: const Icon(Icons.refresh),
              child: Text(l.updateRetry),
            ),
          );
        }
    }

    // The title and the buttons stay in place; only the middle scrolls, so
    // the buttons are on screen even with long notes, large text or a short
    // window.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: 10),
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(title, style: tt.titleLarge),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _close,
                  tooltip: l.close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showFacts) _facts(context, l),
                  for (final w in body) ...[const SizedBox(height: 16), w],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 24),
            child: actions.isEmpty
                ? const SizedBox.shrink()
                : _ActionBar(actions: actions),
          ),
        ],
      ),
    );
  }

  /// The readyToInstall step and what the installer said last.
  void _ready(
    BuildContext context,
    AppLocalizations l,
    bool windows,
    InstallOutcome? outcome,
    List<Widget> body,
    List<Widget> actions,
  ) {
    final tt = Theme.of(context).textTheme;
    final t = context.tokens;
    final installLabel = windows ? l.updateInstallWindows : l.updateInstall;
    var release = false;
    var retryLabel = installLabel;
    switch (outcome) {
      case InstallOutcome.started:
        body.add(
          _Callout(
            tone: _Tone.info,
            icon: Icons.open_in_new,
            text: l.updateInstallerOpen,
          ),
        );
        retryLabel = l.updateInstallerReopen;
      case InstallOutcome.permissionRequired:
        body.add(
          _Callout(
            tone: _Tone.warn,
            icon: Icons.security,
            title: l.updatePermissionTitle,
            text: l.updatePermissionBody,
          ),
        );
      case InstallOutcome.failed:
        body.add(
          _Callout(
            tone: _Tone.error,
            icon: Icons.error_outline,
            text: windows
                ? l.updateInstallFailedWindows
                : l.updateInstallFailedAndroid,
          ),
        );
        release = true;
        retryLabel = l.updateRetry;
      case InstallOutcome.unsupported:
        body.add(
          _Callout(
            tone: _Tone.error,
            icon: Icons.block,
            text: l.updateInstallUnsupported,
          ),
        );
        release = true;
      case InstallOutcome.cancelled || null:
        body.add(
          Text(
            l.updateReadyNote,
            style: tt.bodyMedium!.copyWith(color: t.soft),
          ),
        );
        body.add(
          Text(
            windows ? l.updateReadyWindows : l.updateReadyAndroid,
            style: tt.bodyMedium!.copyWith(color: t.soft),
          ),
        );
    }
    if (release) {
      body.add(UpdateReleaseLinks(openUrl: widget.openUrl));
    } else {
      body.add(_notes(context, l));
    }
    actions.add(OutlinedButton(onPressed: _later, child: Text(l.updateLater)));
    if (outcome != InstallOutcome.unsupported) {
      actions.add(
        PrimaryButton(
          onPressed: () => unawaited(_c.installUpdate()),
          icon: Icon(
            outcome == InstallOutcome.failed
                ? Icons.refresh
                : windows
                ? Icons.restart_alt
                : Icons.system_update_alt,
          ),
          child: Text(retryLabel),
        ),
      );
    }
  }

  /// Version, installed version, size and release date as read-only tags.
  Widget _facts(BuildContext context, AppLocalizations l) {
    final m = _c.manifest!;
    final installed = widget.installed ?? AppVersion.current;
    final size = _c.asset?.size;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Tag(
          l.updateVersionNumber(isolateLtr(m.version.version)),
          strong: true,
        ),
        if (installed.enabled)
          _Tag(l.updateYourVersion(isolateLtr(installed.version))),
        if (size != null) _Tag(l.updateDownloadSize(formatUpdateSize(l, size))),
        _Tag(l.updateReleased(isolateLtr(formatUpdateDate(m.publishedAt)))),
      ],
    );
  }

  /// "What's new": the signed release notes as plain text, in the app's
  /// language when the release has them, else English, else whatever it has.
  Widget _notes(BuildContext context, AppLocalizations l) {
    final m = _c.manifest;
    if (m == null) return const SizedBox.shrink();
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final notes = m.notesFor(lang)?.trim();
    final text = notes == null || notes.isEmpty ? l.updateNoNotes : notes;
    // English notes inside an Arabic app (and the other way round) keep their
    // own direction, or their punctuation lands on the wrong side.
    final rtl = _hasRtlLetters(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.updateWhatsNew,
            style: tt.labelMedium!.copyWith(color: t.accent2),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: t.line2),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      text,
                      style: tt.bodyMedium!.copyWith(color: t.soft),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static final RegExp _rtlLetters = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');

  static bool _hasRtlLetters(String s) => _rtlLetters.hasMatch(s);
}

/// A small read-only tag (DESIGN section 8.14).
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.tagFill,
        borderRadius: BorderRadius.circular(AppRadius.tag),
        border: Border.all(color: strong ? t.accent2 : t.tagBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: strong ? t.accent2 : t.tagText),
        ),
      ),
    );
  }
}

enum _Tone { info, good, warn, error }

/// A tinted message box. Colour is never the only signal: every tone has its
/// own icon and the text says what happened.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.tone,
    required this.icon,
    required this.text,
    this.title,
  });

  final _Tone tone;
  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final (Color bg, Color fg) = switch (tone) {
      _Tone.info => (t.surface2, t.soft),
      _Tone.good => (t.goodContainer, t.good),
      _Tone.warn => (t.warnContainer, t.warn),
      _Tone.error => (t.errorContainer, t.onErrorContainer),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.controlAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: fg, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title!, style: tt.titleSmall!.copyWith(color: fg)),
                    Text(text, style: tt.bodyMedium!.copyWith(color: fg)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The buttons of a step. The last one in [actions] is the primary action.
///
/// On a narrow sheet (a phone) they stack at full width with the primary
/// button first, which is easy to hit with a thumb. From 480 dp up they sit in
/// a row at the end edge, ghost and text buttons first and the primary one
/// last (it mirrors in right-to-left layouts).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, a) in actions.reversed.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: a),
              ],
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: actions,
        );
      },
    );
  }
}
