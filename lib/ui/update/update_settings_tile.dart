import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings.dart';
import '../../services/update/app_version.dart';
import '../../services/update/update_controller.dart';
import '../../services/update/update_failure.dart';
import '../../services/update/update_providers.dart';
import '../app_scope.dart';
import '../theme/tokens.dart';
import '../widgets/focus_ring.dart';
import '../widgets/icon_tile.dart';
import 'update_format.dart';
import 'update_messages.dart';
import 'update_sheet.dart';

/// The leading slot of the About rows: as wide as the brand mark above them
/// (48), with the standard 36 px icon tile centred in it, so the icons sit
/// under the mark and the text lines up with the app name.
const double _aboutLeading = 48;
const double _aboutGap = 16;

/// Gives the list tiles below it the About layout (see [_aboutLeading]).
Widget _aboutRows({required Widget child}) => ListTileTheme.merge(
  minLeadingWidth: _aboutLeading,
  horizontalTitleGap: _aboutGap,
  child: child,
);

Widget _aboutIcon(IconData icon) => SizedBox(
  width: _aboutLeading,
  child: Center(child: IconTile(icon: icon)),
);

/// The updates block of the settings screen: the "Check for updates
/// automatically" switch, the installed version, when the last check was, the
/// result of the last check and the "Check now" button. While a newer version
/// is on offer (or being downloaded) there is also a "View update" button that
/// opens the [UpdateSheet].
///
/// Drop it into the settings list (see `INTEGRATION.md`):
///
/// ```dart
/// const Divider(),
/// const UpdateSettingsTile(),
/// ```
///
/// It reads the controller and the settings from `AppScope`. Where there is no
/// updater it shows a single line in a development build ("Updates are off in
/// development builds", so a tester can tell why there is no Check now) and
/// nothing at all on platforms without updates, so it can stay in the list
/// unconditionally.
class UpdateSettingsTile extends StatelessWidget {
  const UpdateSettingsTile({
    super.key,
    this.controller,
    this.settings,
    this.openUrl,
    this.installed,
  });

  /// Defaults to `AppServices.updates`.
  final UpdateController? controller;

  /// Defaults to `AppServices.settings`.
  final AppSettings? settings;

  /// See [UpdateSheet.openUrl].
  final UrlOpener? openUrl;

  /// The running version; defaults to [AppVersion.current].
  final AppVersion? installed;

  @override
  Widget build(BuildContext context) {
    final scope = controller == null || settings == null
        ? AppScope.of(context)
        : null;
    final c = controller ?? scope?.updates;
    final s = settings ?? scope?.settings;
    if (c == null || s == null || !c.enabled) return _withoutUpdater(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c, s]),
      builder: (context, _) => _build(context, c, s),
    );
  }

  /// No updater in this build. A development build says so; any other build
  /// (a platform without packages) shows nothing.
  Widget _withoutUpdater(BuildContext context) {
    if ((installed ?? AppVersion.current).enabled) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return _aboutRows(
      child: ListTile(
        contentPadding: IconTile.rowPadding,
        leading: _aboutIcon(Icons.system_update_alt_rounded),
        title: Text(l.updateSettingsGroup),
        subtitle: Text(l.updateDevOff),
      ),
    );
  }

  Widget _build(BuildContext context, UpdateController c, AppSettings s) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final version = installed ?? AppVersion.current;
    final status = c.status;
    final checking = status == UpdateStatus.checking;
    final offer = c.manifest != null && status != UpdateStatus.idle;

    final result = _result(context, l, t, c);
    final lastChecked = s.lastUpdateCheck > 0
        ? l.updateLastChecked(
            isolateLtr(
              formatUpdateStamp(
                DateTime.fromMillisecondsSinceEpoch(s.lastUpdateCheck),
              ),
            ),
          )
        : l.updateNeverChecked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
          child: Semantics(
            header: true,
            child: Text(
              l.updateSettingsGroup,
              style: tt.titleSmall!.copyWith(color: t.muted),
            ),
          ),
        ),
        _aboutRows(
          child: FocusRing(
            child: SwitchListTile(
              contentPadding: IconTile.rowPadding,
              secondary: _aboutIcon(Icons.autorenew_rounded),
              title: Text(l.updateAutoCheck),
              subtitle: Text(l.updateAutoCheckNote),
              value: s.checkUpdates,
              onChanged: (v) => unawaited(s.update((x) => x.checkUpdates = v)),
            ),
          ),
        ),
        Padding(
          // Under the text of the rows above: 16 + the 48 px slot + 16.
          padding: const EdgeInsetsDirectional.fromSTEB(80, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.updateVersionTitle,
                style: tt.bodyLarge!.copyWith(color: t.ink),
              ),
              Text(
                version.enabled
                    ? formatUpdateVersion(l, version.version, version.build)
                    : l.updateDevBuild,
                style: tt.bodyMedium!.copyWith(color: t.muted),
              ),
              const SizedBox(height: 4),
              Text(lastChecked, style: tt.bodySmall!.copyWith(color: t.muted)),
              if (result != null) ...[const SizedBox(height: 12), result],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: c.busy || status == UpdateStatus.readyToInstall
                        ? null
                        : () => unawaited(c.checkNow()),
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(l.updateCheckNow),
                  ),
                  if (offer)
                    FilledButton(
                      onPressed: () => unawaited(
                        showUpdateSheet(
                          context,
                          controller: c,
                          openUrl: openUrl,
                          installed: installed,
                        ),
                      ),
                      child: Text(l.updateViewUpdate),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The one-line result of the last check or step, with an icon: colour is
  /// never the only signal.
  Widget? _result(
    BuildContext context,
    AppLocalizations l,
    AppTokens t,
    UpdateController c,
  ) {
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final manifest = c.manifest;
    final (IconData icon, Color color, String text)? line = switch (c.status) {
      UpdateStatus.idle => null,
      UpdateStatus.checking => (Icons.sync, t.soft, l.updateChecking),
      UpdateStatus.available when manifest != null => (
        Icons.system_update_alt,
        t.accent2,
        l.updateVersionAvailable(isolateLtr(manifest.version.version)),
      ),
      UpdateStatus.available => null,
      UpdateStatus.downloading => (
        Icons.downloading,
        t.soft,
        l.updateBannerDownloading(updatePercent(c.progress).toString()),
      ),
      UpdateStatus.verifying => (Icons.sync, t.soft, l.updateVerifying),
      UpdateStatus.readyToInstall => (
        Icons.check_circle_outline,
        t.good,
        l.updateReadyTitle,
      ),
      UpdateStatus.installing => (
        Icons.sync,
        t.soft,
        windows ? l.updateInstallingWindows : l.updateInstalling,
      ),
      UpdateStatus.upToDate => (
        Icons.check_circle_outline,
        t.good,
        l.updateUpToDate,
      ),
      UpdateStatus.error => (
        Icons.error_outline,
        t.error,
        describeUpdateFailure(l, c.failure ?? UpdateFailure.internal).body,
      ),
    };
    if (line == null) return null;
    final (icon, color, text) = line;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: c.status == UpdateStatus.error ? t.error : t.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A "Version 0.2.0 (build 2000)" row for the About section; "Development
/// build" for builds without a version. Always shown (it is information, not
/// a feature of the updater).
class AboutVersionTile extends StatelessWidget {
  const AboutVersionTile({super.key, this.version});

  /// Defaults to [AppVersion.current].
  final AppVersion? version;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = version ?? AppVersion.current;
    return _aboutRows(
      child: ListTile(
        contentPadding: IconTile.rowPadding,
        leading: _aboutIcon(Icons.info_outline_rounded),
        title: Text(l.updateVersionTitle),
        subtitle: Text(
          v.enabled
              ? formatUpdateVersion(l, v.version, v.build)
              : l.updateDevBuild,
        ),
      ),
    );
  }
}
