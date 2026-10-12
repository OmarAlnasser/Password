import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:hisn/services/update/update_installer.dart';
import 'package:hisn/services/update/windows_installer.dart';
import 'package:hisn/services/update/windows_setup_installer.dart';

class _FakeProcess implements Process {
  @override
  int get pid => 4711;

  bool killed = false;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

class _StartCall {
  _StartCall(this.executable, this.arguments, this.workingDirectory, this.mode);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final ProcessStartMode mode;
}

/// A file that passes the checks: `MZ` and then [size] bytes in all.
Uint8List _setupBytes(int size) {
  final bytes = Uint8List(size);
  bytes[0] = 0x4d;
  bytes[1] = 0x5a;
  for (var i = 2; i < size; i++) {
    bytes[i] = (i * 7) & 0xff;
  }
  return bytes;
}

void main() {
  late Directory tmp;
  late Directory work;
  late Directory logDir;
  late List<String> events;
  late List<_StartCall> starts;
  late _FakeProcess process;

  /// What the fake setup does when started: by default it creates its log
  /// and writes `started` into the result file, as the setup's own code does
  /// as soon as it runs.
  late FutureOr<void> Function(_StartCall call) onStart;

  /// Makes the starter throw when set.
  Object? startError;

  File logFile() => File(p.join(logDir.path, 'update-setup.log'));
  File resultFile() => File(p.join(logDir.path, 'update-setup.result'));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('windows_setup_test_');
    work = Directory(p.join(tmp.path, 'private work'))..createSync();
    logDir = Directory(p.join(tmp.path, 'temp'))..createSync();
    events = [];
    starts = [];
    process = _FakeProcess();
    startError = null;
    onStart = (_) {
      logFile().writeAsStringSync('Setup started\n');
      resultFile().writeAsStringSync('started');
    };
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Process> starter(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    events.add('start');
    final call = _StartCall(
      executable,
      List.of(arguments),
      workingDirectory,
      mode,
    );
    starts.add(call);
    final error = startError;
    if (error != null) throw error;
    await onStart(call);
    return process;
  }

  WindowsSetupInstaller makeInstaller({
    bool isWindows = true,
    int minSetupBytes = 64,
    bool requirePeHeader = true,
    Duration setupStartTimeout = const Duration(milliseconds: 400),
    Future<void> Function(Process process)? stopProcess,
  }) => WindowsSetupInstaller(
    isWindows: isWindows,
    startProcess: starter,
    exitProcess: (code) => events.add('exit:$code'),
    logDirectory: logDir,
    // No SystemRoot: no real taskkill in tests.
    environment: const {},
    stopProcess: stopProcess,
    minSetupBytes: minSetupBytes,
    requirePeHeader: requirePeHeader,
    setupStartTimeout: setupStartTimeout,
    pollInterval: const Duration(milliseconds: 5),
  );

  File writeSetup({String name = 'app-windows-setup.exe', List<int>? bytes}) =>
      File(p.join(work.path, name))
        ..writeAsBytesSync(bytes ?? _setupBytes(256));

  Future<void> prepareExit() async => events.add('prepareExit');

  Future<InstallOutcome> run(WindowsSetupInstaller installer, [File? file]) =>
      installer.install(file ?? writeSetup(), prepareExit: prepareExit);

  group('happy path', () {
    test('checks, locks the vault, starts the setup, waits, exits', () async {
      final installer = makeInstaller();
      final setup = writeSetup();

      final outcome = await run(installer, setup);

      expect(outcome, InstallOutcome.started);
      expect(installer.lastError, isNull);
      // The order is the contract: lock the vault, then hand over, then go.
      expect(events, ['prepareExit', 'start', 'exit:0']);
      final call = starts.single;
      expect(call.executable, p.normalize(setup.absolute.path));
      expect(p.isAbsolute(call.executable), isTrue);
      expect(call.mode, ProcessStartMode.detached);
      expect(call.workingDirectory, logDir.path);
      expect(call.arguments, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/SP-',
        '/NOCANCEL',
        '/CLOSEAPPLICATIONS',
        '/relaunch=1',
        '/LOG=${p.join(logDir.path, 'update-setup.log')}',
        '/result=${p.join(logDir.path, 'update-setup.result')}',
      ]);
      // Handed over: the setup is left running, and the file is kept (the
      // controller and the next start clean up).
      expect(process.killed, isFalse);
      expect(setup.existsSync(), isTrue);
    });

    test('a relative path is started by its absolute path', () async {
      final setup = writeSetup();
      final relative = File(p.relative(setup.path));

      expect(await run(makeInstaller(), relative), InstallOutcome.started);

      expect(starts.single.executable, p.normalize(setup.absolute.path));
    });

    test('the extension may be upper case', () async {
      final outcome = await run(
        makeInstaller(),
        writeSetup(name: 'APP-SETUP.EXE'),
      );
      expect(outcome, InstallOutcome.started);
    });

    test('a path with spaces and quotes stays one argument', () async {
      final odd = Directory(p.join(tmp.path, 'temp "a" & b; \$x'))
        ..createSync();
      final installer = WindowsSetupInstaller(
        isWindows: true,
        startProcess: starter,
        exitProcess: (code) => events.add('exit:$code'),
        logDirectory: odd,
        minSetupBytes: 64,
        setupStartTimeout: const Duration(milliseconds: 400),
        pollInterval: const Duration(milliseconds: 5),
      );
      onStart = (_) =>
          File(p.join(odd.path, 'update-setup.result'))
              .writeAsStringSync('started');

      expect(await run(installer), InstallOutcome.started);

      final args = starts.single.arguments;
      expect(args, hasLength(9));
      expect(args[7], '/LOG=${p.join(odd.path, 'update-setup.log')}');
      expect(args[8], '/result=${p.join(odd.path, 'update-setup.result')}');
    });

    test('files of an earlier run are deleted before the start', () async {
      logFile().writeAsStringSync('old log');
      resultFile().writeAsStringSync('aborted');
      var sawOld = true;
      onStart = (_) {
        sawOld = logFile().existsSync() || resultFile().existsSync();
        logFile().writeAsStringSync('new log');
        resultFile().writeAsStringSync('started');
      };

      expect(await run(makeInstaller()), InstallOutcome.started);

      expect(sawOld, isFalse);
      expect(resultFile().readAsStringSync(), 'started');
    });

    test('the setup may report a little later', () async {
      onStart = (_) {
        Timer(
          const Duration(milliseconds: 60),
          () => resultFile().writeAsStringSync('started'),
        );
      };

      expect(await run(makeInstaller()), InstallOutcome.started);
      expect(events.last, 'exit:0');
    });

    test('an outcome written already also counts as running', () async {
      onStart = (_) => resultFile().writeAsStringSync('aborted');

      expect(await run(makeInstaller()), InstallOutcome.started);
    });

    test('the log alone is not enough', () async {
      // Inno Setup opens its log before its own checks (an earlier setup
      // still running, ...), which may end it before its code runs.
      onStart = (_) => logFile().writeAsStringSync('Setup started');
      final installer = makeInstaller(
        setupStartTimeout: const Duration(milliseconds: 80),
      );

      expect(await run(installer), InstallOutcome.failed);
      expect(installer.lastError, WindowsInstallError.helperNotReady);
      expect(events, isNot(contains('exit:0')));
    });

    test('buildArguments', () {
      expect(
        WindowsSetupInstaller.buildArguments(
          logFile: r'C:\T\update-setup.log',
          resultFile: r'C:\T\update-setup.result',
        ),
        [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/SP-',
          '/NOCANCEL',
          '/CLOSEAPPLICATIONS',
          '/relaunch=1',
          r'/LOG=C:\T\update-setup.log',
          r'/result=C:\T\update-setup.result',
        ],
      );
    });

    test('the defaults', () {
      final installer = WindowsSetupInstaller(isWindows: true);
      expect(installer.minSetupBytes, 1024 * 1024);
      expect(installer.requirePeHeader, isTrue);
      expect(installer.setupStartTimeout, const Duration(seconds: 60));
      expect(installer.pollInterval, const Duration(milliseconds: 200));
      expect(WindowsSetupInstaller.setupLogFileName, 'update-setup.log');
      expect(WindowsSetupInstaller.setupResultFileName, 'update-setup.result');
    });
  });

  group('refusals before anything happens', () {
    test('not Windows', () async {
      final installer = makeInstaller(isWindows: false);

      expect(await run(installer), InstallOutcome.unsupported);

      expect(events, isEmpty);
      expect(installer.lastError, isNull);
    });

    Future<void> expectBadPackage(File file, {String? reason}) async {
      final installer = makeInstaller();
      events.clear();

      expect(await run(installer, file), InstallOutcome.failed, reason: reason);

      expect(installer.lastError, WindowsInstallError.badPackage);
      expect(events, isEmpty, reason: 'vault untouched, nothing started');
      expect(starts, isEmpty);
    }

    test('a name that is not .exe', () async {
      for (final name in ['setup.zip', 'setup.exe.zip', 'setup', 'setup.msi']) {
        await expectBadPackage(writeSetup(name: name), reason: name);
      }
    });

    test('too small', () async {
      await expectBadPackage(writeSetup(bytes: _setupBytes(63)));
      await expectBadPackage(writeSetup(bytes: const []));
    });

    test('no MZ header', () async {
      final bytes = _setupBytes(256)..[0] = 0x50;
      await expectBadPackage(writeSetup(bytes: bytes));
    });

    test('the MZ check can be turned off for synthetic files', () async {
      final bytes = _setupBytes(256)..[1] = 0;
      final installer = makeInstaller(requirePeHeader: false);

      expect(
        await run(installer, writeSetup(bytes: bytes)),
        InstallOutcome.started,
      );
    });

    test('missing, a folder or a link', () async {
      await expectBadPackage(File(p.join(work.path, 'missing.exe')));

      final folder = Directory(p.join(work.path, 'folder.exe'))..createSync();
      await expectBadPackage(File(folder.path));

      final target = writeSetup(name: 'real.exe');
      final link = Link(p.join(work.path, 'link.exe'))..createSync(target.path);
      await expectBadPackage(File(link.path));
    });

    test('a log that cannot be deleted stops it before the vault', () async {
      // A folder by that name stands in for a log that stays in place.
      Directory(logFile().path).createSync();
      final installer = makeInstaller();

      expect(await run(installer), InstallOutcome.failed);

      expect(installer.lastError, WindowsInstallError.helperUnavailable);
      expect(events, isEmpty);
    });

    test('a result that cannot be deleted stops it before the vault', () async {
      Directory(resultFile().path).createSync();
      final installer = makeInstaller();

      expect(await run(installer), InstallOutcome.failed);

      expect(installer.lastError, WindowsInstallError.helperUnavailable);
      expect(events, isEmpty);
    });
  });

  group('hand-over', () {
    test('prepareExit throws: nothing is started', () async {
      final installer = makeInstaller();

      final outcome = await installer.install(
        writeSetup(),
        prepareExit: () async {
          events.add('prepareExit');
          throw StateError('locked out');
        },
      );

      expect(outcome, InstallOutcome.failed);
      expect(installer.lastError, WindowsInstallError.prepareExitFailed);
      expect(events, ['prepareExit']);
      expect(starts, isEmpty);
    });

    test('the setup cannot be started', () async {
      startError = const ProcessException('setup.exe', [], 'blocked', 5);
      final installer = makeInstaller();

      expect(await run(installer), InstallOutcome.failed);

      expect(installer.lastError, WindowsInstallError.helperUnavailable);
      expect(events, ['prepareExit', 'start']);
    });

    test('not running in time: stopped, failed, app keeps running', () async {
      onStart = (_) {};
      final installer = makeInstaller(
        setupStartTimeout: const Duration(milliseconds: 80),
      );

      expect(await run(installer), InstallOutcome.failed);

      expect(installer.lastError, WindowsInstallError.helperNotReady);
      expect(events, ['prepareExit', 'start']);
      expect(events, isNot(contains('exit:0')));
      expect(process.killed, isTrue);
    });

    test('not running in time: the whole process tree is stopped', () async {
      onStart = (_) {};
      final stopped = <int>[];
      final installer = makeInstaller(
        setupStartTimeout: const Duration(milliseconds: 80),
        stopProcess: (process) async => stopped.add(process.pid),
      );

      expect(await run(installer), InstallOutcome.failed);

      expect(stopped, [4711]);
      // And the loader itself, in case the tree kill missed it.
      expect(process.killed, isTrue);
    });

    test('a failing tree kill still stops the loader', () async {
      onStart = (_) {};
      final installer = makeInstaller(
        setupStartTimeout: const Duration(milliseconds: 80),
        stopProcess: (_) async => throw const ProcessException('x', []),
      );

      expect(await run(installer), InstallOutcome.failed);
      expect(process.killed, isTrue);
    });

    test('a handed-over setup is not stopped', () async {
      final stopped = <int>[];
      final installer = makeInstaller(
        stopProcess: (process) async => stopped.add(process.pid),
      );

      expect(await run(installer), InstallOutcome.started);
      expect(stopped, isEmpty);
      expect(process.killed, isFalse);
    });

    test('a second call while one runs is refused', () async {
      final gate = Completer<void>();
      final installer = makeInstaller();
      final first = installer.install(
        writeSetup(),
        prepareExit: () async {
          events.add('prepareExit');
          await gate.future;
        },
      );

      expect(
        await installer.install(
          writeSetup(name: 'other.exe'),
          prepareExit: prepareExit,
        ),
        InstallOutcome.failed,
      );
      // The refused call did not touch the first one's state.
      expect(installer.lastError, isNull);

      gate.complete();
      expect(await first, InstallOutcome.started);
      expect(events, ['prepareExit', 'start', 'exit:0']);
      expect(starts, hasLength(1));
    });

    test('lastError is cleared by a later success', () async {
      final installer = makeInstaller();
      await run(installer, writeSetup(name: 'bad.zip'));
      expect(installer.lastError, WindowsInstallError.badPackage);

      expect(await run(installer), InstallOutcome.started);
      expect(installer.lastError, isNull);
    });
  });
}
