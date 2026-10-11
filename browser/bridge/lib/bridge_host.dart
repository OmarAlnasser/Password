import 'dart:async';
import 'dart:io';

import 'bridge_protocol.dart';

/// The browser helper (bin/khazna_bridge.dart): what Chrome starts for the
/// extension's native messaging port.
///
/// With the app running it connects to the app's loopback port (from
/// [endpointFile]), proves it may by sending the app's per-run token, and
/// then copies bytes both ways until either side closes. It never reads the
/// messages: the app checks every one.
///
/// Without the app it answers the first message on its own and exits:
/// `{"t": "open"}` starts the app ([launchApp]), anything else gets
/// `{"ok": false, "error": "app_not_running"}`. Exiting at once matters: the
/// updater waits for every process in the install folder to end.
///
/// Returns the exit code.
Future<int> runBridgeHost({
  required Stream<List<int>> input,
  required IOSink output,
  required List<String> args,
  required Directory? directory,
  Future<void> Function()? launchApp,
  Duration connectTimeout = const Duration(seconds: 2),
}) async {
  // Chrome passes the caller's origin first. Only our extension may start the
  // helper (allowed_origins in the manifest); check it anyway.
  if (args.isEmpty || args.first != extensionOrigin) return 2;

  final socket = await _connect(directory, connectTimeout);
  if (socket == null) {
    return _answerAlone(input, output, launchApp);
  }
  return _relay(socket.$1, socket.$2, input, output);
}

Future<(Socket, BridgeEndpoint)?> _connect(
  Directory? dir,
  Duration timeout,
) async {
  if (dir == null) return null;
  final BridgeEndpoint? endpoint;
  try {
    endpoint = BridgeEndpoint.tryParse(await endpointFile(dir).readAsString());
  } on FileSystemException {
    return null;
  }
  if (endpoint == null) return null;
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint.port,
      timeout: timeout,
    );
    return (socket, endpoint);
  } on SocketException {
    // A stale file from an app that crashed.
    return null;
  }
}

Future<int> _relay(
  Socket socket,
  BridgeEndpoint endpoint,
  Stream<List<int>> input,
  IOSink output,
) async {
  socket.setOption(SocketOption.tcpNoDelay, true);
  socket.add(encodeFrame({'t': 'bridge', 'token': endpoint.token}));

  final done = Completer<int>();
  void finish(int code) {
    if (!done.isCompleted) done.complete(code);
  }

  final fromBrowser = input.listen(
    socket.add,
    onDone: () => finish(0),
    onError: (Object _) => finish(1),
    cancelOnError: true,
  );
  final fromApp = socket.listen(
    output.add,
    onDone: () => finish(0),
    onError: (Object _) => finish(1),
    cancelOnError: true,
  );

  final code = await done.future;
  await fromBrowser.cancel();
  await fromApp.cancel();
  socket.destroy();
  try {
    await output.flush();
  } on Object {
    // Chrome closed the pipe.
  }
  return code;
}

Future<int> _answerAlone(
  Stream<List<int>> input,
  IOSink output,
  Future<void> Function()? launchApp,
) async {
  final decoder = FrameDecoder();
  final done = Completer<int>();
  late final StreamSubscription<List<int>> sub;
  sub = input.listen(
    (chunk) async {
      if (done.isCompleted) return;
      final List<Map<String, Object?>> frames;
      try {
        frames = decoder.add(chunk);
      } on FrameException {
        done.complete(1);
        return;
      }
      if (frames.isEmpty) return;
      final msg = frames.first;
      final id = msg['id'];
      Map<String, Object?> reply;
      if (msg['t'] == 'open' && launchApp != null) {
        try {
          await launchApp();
          reply = {'id': ?id, 'ok': true, 'launched': true};
        } on Object {
          reply = {'id': ?id, 'ok': false, 'error': 'launch_failed'};
        }
      } else {
        reply = {'id': ?id, 'ok': false, 'error': 'app_not_running'};
      }
      if (done.isCompleted) return;
      output.add(encodeFrame(reply));
      done.complete(0);
    },
    onDone: () {
      if (!done.isCompleted) done.complete(0);
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(1);
    },
    cancelOnError: true,
  );
  final code = await done.future;
  await sub.cancel();
  try {
    await output.flush();
  } on Object {
    // Chrome closed the pipe.
  }
  return code;
}
