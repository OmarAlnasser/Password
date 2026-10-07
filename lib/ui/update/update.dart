/// The update UI in one import:
///
/// ```dart
/// import 'update/update.dart';
/// ```
///
/// * [UpdateGate]: wraps the app content (done in `lib/app.dart`).
/// * [UpdateSettingsTile], [AboutVersionTile]: for the settings screen.
/// * [UpdateSheet] / [showUpdateSheet] and [UpdateBanner]: used by the gate
///   and the settings tile; also usable on their own.
///
/// See `INTEGRATION.md` in this folder.
library;

export 'update_banner.dart';
export 'update_gate.dart';
export 'update_release_links.dart';
export 'update_settings_tile.dart';
export 'update_sheet.dart';
