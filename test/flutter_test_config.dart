import 'dart:async';

import 'package:drift/drift.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Several tests keep more than one VaultDatabase open at once (one per
  // simulated device, each with its own file and executor). drift's
  // debug-only "created the database class multiple times" warning is a
  // false positive there and buries real failures in the CI log.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
