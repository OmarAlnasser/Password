import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vaultsnap/l10n/app_localizations.dart';
import 'package:vaultsnap/services/settings.dart';
import 'package:vaultsnap/services/update/app_version.dart';
import 'package:vaultsnap/services/update/cancel_token.dart';
import 'package:vaultsnap/services/update/secure_downloader.dart';
import 'package:vaultsnap/services/update/update_config.dart';
import 'package:vaultsnap/services/update/update_controller.dart';
import 'package:vaultsnap/services/update/update_failure.dart';
import 'package:vaultsnap/services/update/update_installer.dart';
import 'package:vaultsnap/services/update/update_manifest.dart';
import 'package:vaultsnap/services/update/update_providers.dart';
import 'package:vaultsnap/services/update/update_service.dart';
import 'package:vaultsnap/services/update/update_verifier.dart';
import 'package:vaultsnap/services/update/update_workspace.dart';
import 'package:vaultsnap/services/update/windows_installer.dart';
import 'package:vaultsnap/ui/theme/app_theme.dart';
import 'package:vaultsnap/ui/update/update_banner.dart';
import 'package:vaultsnap/ui/update/update_gate.dart';
import 'package:vaultsnap/ui/widgets/app_shell.dart';

/// Settings that never touch the disk. The controller awaits `update`, and a
/// real file write would never finish inside `testWidgets`' fake clock.
class MemorySettings extends AppSettings {
  MemorySettings() : super(File('/virtual/settings.json'));

  /// How many times the settings were saved.
  int saves = 0;

  @override
  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    saves++;
    notifyListeners();
  }
}

/// A signed-looking manifest, parsed by the real parser.
UpdateManifest testManifest({
  String version = '0.3.0',
  Map<String, String>? notes,
  int androidSize = 42 * 1024 * 1024,
}) {
  final v = AppVersion.tryParse(version)!;
  final tag = 'v$version';
  Map<String, Object?> asset(String name, int size) => {
    'name': name,
    'url':
        'https://github.com/${UpdateConfig.defaultRepo}/releases/download/$tag/$name',
    'size': size,
    'sha256': 'ab' * 32,
  };
  final json = <String, Object?>{
    'schema': 1,
    'version': version,
    'build': v.build,
    'publishedAt': '2026-10-07T12:00:00Z',
    'notes': notes ?? {'en': 'Faster unlock.\nBug fixes.', 'ar': 'فتح أسرع.'},
    'assets': {
      'android': asset('android.apk', androidSize),
      'windows': asset('windows-x64.zip', 60 * 1024 * 1024),
    },
  };
  return UpdateManifest.parse(
    Uint8List.fromList(utf8.encode(jsonEncode(json))),
    UpdateConfig(),
  );
}

class _RejectingVerifier implements ManifestVerifier {
  @override
  bool verify(Uint8List message, Uint8List signature) => false;
}

/// An [UpdateService] that answers from a script instead of the network, and
/// can be held at any step. Nothing here touches the disk or the network.
class ScriptedUpdateService extends UpdateService {
  ScriptedUpdateService({
    AppVersion? version,
    UpdatePlatform platform = UpdatePlatform.android,
  }) : super(
         config: UpdateConfig(),
         downloader: SecureDownloader(
           MockClient((_) async => throw StateError('no network in UI tests')),
           UpdateConfig(),
         ),
         verifier: _RejectingVerifier(),
         workspace: UpdateWorkspace(Directory('/virtual/updates')),
         version: version ?? AppVersion.tryParse('0.2.0')!,
         platform: platform,
       );

  /// What the next [check] answers.
  UpdateCheckResult? nextCheck;

  /// While set, [check] waits for it.
  Completer<void>? checkGate;

  int checkCalls = 0;
  int? lastHighestSeen;

  int downloadCalls = 0;
  int verifyCalls = 0;
  int stageCalls = 0;
  int cleanupCalls = 0;
  final List<Directory?> discarded = [];

  /// While set, [verify] waits for it.
  Completer<void>? verifyGate;

  /// When set, [verify] throws it.
  UpdateFailure? verifyFailure;

  DownloadProgress? _onProgress;
  Completer<DownloadedUpdate>? _download;
  UpdateAvailable? _downloading;

  UpdateAvailable offer([UpdateManifest? manifest]) {
    final m = manifest ?? testManifest();
    return UpdateAvailable(m, m.assetFor(platform!)!);
  }

  /// Sets [nextCheck] to an available update.
  UpdateAvailable offerUpdate([UpdateManifest? manifest]) {
    final o = offer(manifest);
    nextCheck = o;
    return o;
  }

  @override
  Future<UpdateCheckResult> check({
    int highestSeenBuild = 0,
    CancelToken? cancel,
  }) async {
    checkCalls++;
    lastHighestSeen = highestSeenBuild;
    final gate = checkGate;
    if (gate != null) {
      await Future.any([gate.future, ?cancel?.whenCancelled]);
      if (cancel?.isCancelled ?? false) {
        return const UpdateFailed(UpdateFailure.cancelled);
      }
    }
    return nextCheck ?? const UpdateDisabled();
  }

  @override
  Future<DownloadedUpdate> download(
    UpdateAvailable update, {
    DownloadProgress? onProgress,
    CancelToken? cancel,
  }) {
    downloadCalls++;
    _onProgress = onProgress;
    _downloading = update;
    final done = _download = Completer<DownloadedUpdate>();
    cancel?.whenCancelled.then((_) {
      if (!done.isCompleted) {
        done.completeError(const UpdateException(UpdateFailure.cancelled));
      }
    });
    return done.future;
  }

  /// Reports download progress to the controller.
  void emitProgress(int received, int total) =>
      _onProgress?.call(received, total);

  /// The download ends well.
  void finishDownload() {
    final u = _downloading!;
    _download!.complete(
      DownloadedUpdate(
        manifest: u.manifest,
        asset: u.asset,
        file: File('/virtual/downloads/${u.asset.name}'),
        directory: Directory('/virtual/downloads'),
      ),
    );
  }

  /// The download ends with [reason].
  void failDownload(UpdateFailure reason) =>
      _download!.completeError(UpdateException(reason));

  @override
  Future<void> verify(DownloadedUpdate download) async {
    verifyCalls++;
    await verifyGate?.future;
    final f = verifyFailure;
    if (f != null) throw UpdateException(f);
  }

  @override
  Future<StagedUpdate> stageForInstall(DownloadedUpdate download) async {
    stageCalls++;
    return StagedUpdate(
      file: File('/virtual/staged/${download.asset.name}'),
      directory: Directory('/virtual/staged'),
    );
  }

  @override
  Future<void> discard(Directory? directory) async => discarded.add(directory);

  @override
  Future<void> cleanup() async => cleanupCalls++;
}

/// An installer that records the hand-over and can be held.
class RecordingInstaller implements UpdateInstaller {
  RecordingInstaller({this.outcome = InstallOutcome.started});

  InstallOutcome outcome;

  /// While set, [install] waits for it (after `prepareExit`).
  Completer<void>? gate;

  /// False plays an installer that refuses before it locks the vault (the
  /// Android installer without the "install unknown apps" permission).
  bool callPrepareExit = true;

  int installs = 0;
  int exits = 0;

  @override
  Future<InstallOutcome> install(
    File package, {
    required Future<void> Function() prepareExit,
  }) async {
    installs++;
    if (callPrepareExit) {
      await prepareExit();
      exits++;
    }
    await gate?.future;
    return outcome;
  }
}

/// A controller and everything around it, for one test.
class UpdateRig {
  UpdateRig({
    bool enabled = true,
    UpdatePlatform platform = UpdatePlatform.android,
    InstallOutcome outcome = InstallOutcome.started,
    DateTime? start,
    AppSettings? settings,
    Future<void> Function()? onPrepareExit,
  }) : now = start ?? DateTime.utc(2026, 10, 7, 12),
       service = ScriptedUpdateService(
         version: enabled ? AppVersion.tryParse('0.2.0') : AppVersion.none,
         platform: platform,
       ),
       installer = RecordingInstaller(outcome: outcome),
       settings = settings ?? MemorySettings() {
    controller = UpdateController(
      service: service,
      installer: installer,
      settings: this.settings,
      prepareExit: () async {
        locks++;
        await onPrepareExit?.call();
      },
      clock: () => now,
    );
  }

  final ScriptedUpdateService service;
  final RecordingInstaller installer;
  final AppSettings settings;
  late final UpdateController controller;
  DateTime now;

  /// How many times the vault was locked for an install.
  int locks = 0;

  static final AppVersion installed = AppVersion.tryParse('0.2.0')!;

  void dispose() => controller.dispose();
}

/// The route the tests run on: a page with a counter (to prove the page below
/// the banner is not rebuilt from scratch) and an app bar.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: Center(
      child: FilledButton(
        onPressed: () => setState(() => count++),
        child: Text('count $count'),
      ),
    ),
  );
}

/// Pumps the app the way `lib/app.dart` builds it: `MaterialApp` with the real
/// theme, localisations and `AppShell`, and an [UpdateGate] in `builder`,
/// above the `Navigator`.
Future<GlobalKey<NavigatorState>> pumpUpdateApp(
  WidgetTester tester, {
  required UpdateController? controller,
  Widget home = const HomePage(),
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  TargetPlatform platform = TargetPlatform.android,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool disableAnimations = false,
  Listenable? triggers,
  Duration startDelay = Duration.zero,
  Duration settleDelay = const Duration(seconds: 12),
  UrlOpener? openUrl,
  Future<WindowsUpdateHelperResult> Function()? readHelperResult,
  bool gate = true,
  Widget Function(Widget app)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  Widget app = MaterialApp(
    navigatorKey: navigator,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    darkTheme: AppTheme.dark(locale),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: AppShell(
        // AppShell builds its own theme, so the platform the test wants is
        // applied under it.
        child: Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(platform: platform),
            child: gate
                ? UpdateGate(
                    controller: controller,
                    navigatorKey: navigator,
                    triggers: triggers,
                    startDelay: startDelay,
                    settleDelay: settleDelay,
                    openUrl: openUrl,
                    installed: UpdateRig.installed,
                    readHelperResult: readHelperResult,
                    child: child!,
                  )
                : child!,
          ),
        ),
      ),
    ),
  );
  if (wrap != null) app = wrap(app);
  await tester.pumpWidget(app);
  return navigator;
}

/// Wraps the page in the same shell for widgets that are not routed (the
/// settings tile): theme, localisations, a `Scaffold` and scrolling.
Future<void> pumpTile(
  WidgetTester tester,
  Widget tile, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  TargetPlatform platform = TargetPlatform.android,
  Size size = const Size(390, 844),
  double textScale = 1,
  Widget Function(Widget app)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    darkTheme: AppTheme.dark(locale),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppShell(
        child: Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(platform: platform),
            child: child!,
          ),
        ),
      ),
    ),
    home: Scaffold(body: ListView(children: [tile])),
  );
  if (wrap != null) app = wrap(app);
  await tester.pumpWidget(app);
}

/// Records what the app puts on the clipboard.
List<String> recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// A fake browser: records the addresses it was asked to open.
class RecordingOpener {
  final List<Uri> opened = [];
  bool result = true;

  Future<bool> call(Uri url) async {
    opened.add(url);
    return result;
  }
}

/// The banner at the top of the app.
Finder bannerFinder() => find.byType(UpdateBanner);

/// A text whose content, without the invisible left-to-right isolates the UI
/// puts around versions and dates, contains [text].
Finder textLike(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '')
          .replaceAll(RegExp('[\u{2066}\u{2069}]'), '')
          .contains(text),
  description: 'text like "$text"',
);
