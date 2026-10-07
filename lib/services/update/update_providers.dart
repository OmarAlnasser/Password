/// Wiring of the updater into the app: the one place that decides whether
/// there is an updater at all and which installer it uses. `main.dart` calls
/// [createUpdateController]; the UI only ever sees an `UpdateController?`.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sodium/sodium.dart';

import '../settings.dart';
import 'android_installer.dart';
import 'app_version.dart';
import 'update_config.dart';
import 'update_controller.dart';
import 'update_installer.dart';
import 'update_manifest.dart';
import 'update_service.dart';
import 'windows_installer.dart';

/// Name of the folder inside the app's data directory that holds downloaded
/// and staged packages. A folder of its own, next to (never inside) the vault
/// folder.
const String updateWorkFolderName = 'updates';

/// Builds the updater, or returns null where there is nothing to update:
///
/// * the Android autofill entry point ([forAutofill]) never updates anything;
/// * a development build (no `APP_VERSION`, see [AppVersion]) has no updater at
///   all, so the UI shows nothing;
/// * platforms without a package (iOS, macOS, Linux) have none either.
///
/// [prepareExit] must lock the vault and wipe its keys. It is awaited by the
/// installer right before the process exits (Windows) or the system installer
/// opens (Android), never earlier.
///
/// [version], [platform] and [installer] exist for tests.
UpdateController? createUpdateController({
  required Sodium sodium,
  required Directory supportDir,
  required AppSettings settings,
  required Future<void> Function() prepareExit,
  bool forAutofill = false,
  AppVersion? version,
  UpdatePlatform? platform,
  UpdateInstaller? installer,
}) {
  if (forAutofill) return null;
  final chosenPlatform = platform ?? UpdatePlatform.current;
  if (chosenPlatform == null) return null;
  final chosenVersion = version ?? AppVersion.current;
  if (!chosenVersion.enabled) return null;
  return UpdateController(
    service: UpdateService.create(
      sodium: sodium,
      workRoot: Directory(p.join(supportDir.path, updateWorkFolderName)),
      version: chosenVersion,
      platform: chosenPlatform,
    ),
    installer:
        installer ??
        switch (chosenPlatform) {
          UpdatePlatform.android => AndroidUpdateInstaller(),
          UpdatePlatform.windows => WindowsUpdateInstaller(),
        },
    settings: settings,
    prepareExit: prepareExit,
  );
}

/// Opens a web page in the user's browser. Returns false if it could not.
typedef UrlOpener = Future<bool> Function(Uri url);

/// The public page of the latest release. It is where a user can get the new
/// version by hand when an automatic install is not possible. Not a manifest
/// or package URL: those never reach the browser.
Uri get releasePageUri =>
    Uri.https('github.com', '/${UpdateConfig.defaultRepo}/releases/latest');

/// A way to open [releasePageUri] in the browser, or null on platforms where
/// the app has none (the UI then offers "Copy link" only).
///
/// Windows hands the address to the shell; Android asks the native side to
/// start the browser (no extra package: the installer's platform channel has
/// an `openReleasePage` call for it).
UrlOpener? get platformUrlOpener => Platform.isWindows
    ? _openOnWindows
    : Platform.isAndroid
    ? openReleasePageOnAndroid
    : null;

/// Opens [url] in the browser through the app's platform channel. Only an
/// [isReleasePageUrl] address goes over the channel (the native side checks
/// the same again). False when it is refused or there is no browser. [channel]
/// is for tests.
Future<bool> openReleasePageOnAndroid(Uri url, {MethodChannel? channel}) async {
  if (!isReleasePageUrl(url)) return false;
  try {
    final ok =
        await (channel ??
                const MethodChannel(AndroidUpdateInstaller.channelName))
            .invokeMethod<bool>('openReleasePage', {'url': url.toString()});
    return ok ?? false;
  } on Object {
    return false;
  }
}

/// True for an HTTPS address on github.com under this repository's
/// `releases` page and nothing else: no other host, no port, no credentials.
/// Only such an address is ever handed to the browser.
bool isReleasePageUrl(Uri url) =>
    url.scheme == 'https' &&
    url.host == 'github.com' &&
    !url.hasPort &&
    url.userInfo.isEmpty &&
    (url.path == '/${UpdateConfig.defaultRepo}/releases' ||
        url.path.startsWith('/${UpdateConfig.defaultRepo}/releases/'));

Future<bool> _openOnWindows(Uri url) async {
  // Whatever calls this, it cannot be used to start anything else.
  if (!isReleasePageUrl(url)) return false;
  try {
    // An argument list, never a command string, so nothing is parsed by cmd.
    await Process.start('rundll32.exe', [
      'url.dll,FileProtocolHandler',
      url.toString(),
    ], mode: ProcessStartMode.detached);
    return true;
  } on Object {
    return false;
  }
}
