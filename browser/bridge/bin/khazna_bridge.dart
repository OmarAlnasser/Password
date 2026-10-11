import 'dart:io';

import 'package:khazna_bridge/bridge_host.dart';
import 'package:khazna_bridge/bridge_protocol.dart';

/// The browser helper: Chrome's native messaging host for the Khazna
/// extension. Built as khazna_bridge.exe next to the app's exe
/// (tool/bundle_browser.py). See `runBridgeHost`.
Future<void> main(List<String> args) async {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  exitCode = await runBridgeHost(
    input: stdin,
    output: stdout,
    args: args,
    directory: bridgeDirectory(),
    launchApp: () async {
      await Process.start(
        '$exeDir${Platform.pathSeparator}hisn.exe',
        const [],
        mode: ProcessStartMode.detached,
      );
    },
  );
  // Do not wait for stdin: Chrome keeps it open.
  exit(exitCode);
}
