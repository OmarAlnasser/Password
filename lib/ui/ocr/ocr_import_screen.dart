import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/vault_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../services/ocr/ocr_parser.dart';
import '../../services/ocr/ocr_scanner.dart';
import '../../services/vault_session.dart';
import '../app_scope.dart';
import '../entry_edit_screen.dart';
import '../home_screen.dart';
import '../widgets/secret_text.dart';
import 'ocr_widgets.dart';

/// An image to OCR.
class PickedImage {
  const PickedImage({
    required this.path,
    this.originalHandle,
    this.isTempCopy = true,
  });

  /// Readable local file (often a copy in the app cache).
  final String path;

  /// What to pass to `PlatformBridge.deleteSourceImage` to delete the
  /// user's original (content:// URI on Android, file path on Windows).
  final String? originalHandle;

  /// Whether [path] is our own copy that must always be deleted.
  final bool isTempCopy;
}

class OcrImportScreen extends StatefulWidget {
  const OcrImportScreen({super.key, this.initial});

  /// Set when an image was shared to the app.
  final PickedImage? initial;

  @override
  State<OcrImportScreen> createState() => _OcrImportScreenState();
}

class _OcrImportScreenState extends State<OcrImportScreen> {
  static const _native = MethodChannel('app.vaultsnap/platform');

  PickedImage? _image;
  ScanResult? _scan;
  OcrResult? _result;
  bool _busy = false;

  /// A scan has finished.
  bool _done = false;

  /// Nothing the user could use was read; [_failure] says why, when OCR
  /// itself failed.
  bool _nothing = false;
  ScanError? _failure;
  ScanCancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _process(widget.initial!),
      );
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _cleanupTemp();
    super.dispose();
  }

  /// Our cache copy of the screenshot is plaintext; delete it as soon as OCR
  /// is done and again when leaving the screen.
  void _cleanupTemp() {
    final img = _image;
    if (img != null && img.isTempCopy) {
      try {
        final f = File(img.path);
        if (f.existsSync()) f.deleteSync();
      } on Object {
        // best effort
      }
    }
  }

  Future<void> _pick({required bool camera}) async {
    PickedImage? picked;
    if (Platform.isWindows) {
      final r = await FilePicker.pickFiles(type: FileType.image);
      final path = r?.files.single.path;
      if (path != null) {
        picked = PickedImage(
          path: path,
          originalHandle: path,
          isTempCopy: false,
        );
      }
    } else if (Platform.isAndroid && !camera) {
      // Native picker that also returns the MediaStore URI so the original
      // can be deleted later (image_picker only returns a cache copy).
      final m = await _native.invokeMapMethod<String, String>('pickImage');
      if (m != null) {
        picked = PickedImage(path: m['path']!, originalHandle: m['uri']);
      }
    } else {
      final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (x != null) picked = PickedImage(path: x.path);
    }
    if (picked != null) await _process(picked);
  }

  Future<void> _process(PickedImage img) async {
    _cancel?.cancel();
    _cleanupTemp();
    final token = _cancel = ScanCancelToken();
    setState(() {
      _image = img;
      _busy = true;
      _done = false;
      _scan = null;
      _result = null;
    });
    ScanResult? scan;
    try {
      scan = await OcrScanner.forPlatform(context.services.bridge)
          .scan(img.path, cancel: token);
    } on Object {
      scan = null;
    } finally {
      // OCR is done; the text is in memory, the copy is no longer needed.
      // (The scanner removes its own enlarged copies.)
      if (img.isTempCopy) {
        try {
          File(img.path).deleteSync();
        } on Object {
          // best effort
        }
      }
    }
    // Left, or another image was picked meanwhile: that one reports.
    if (!mounted || token.isCancelled) return;
    setState(() {
      _busy = false;
      _done = true;
      _scan = scan;
      _result = scan?.best;
      _nothing = scan == null || ocrFoundNothing(scan);
      _failure = scan == null
          ? ScanError.failed
          : (_nothing ? ocrFailureOf(scan) : null);
    });
  }

  Future<void> _createEntry() async {
    final r = _result ?? const OcrResult(chips: []);
    final prefill = VaultEntry(
      id: VaultSession.newId(),
      title: r.title ?? '',
      username: r.username ?? r.email ?? '',
      password: r.password ?? '',
      url: r.url ?? '',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EntryEditScreen(prefill: prefill, onSaved: _offerDelete),
      ),
    );
  }

  Future<void> _offerDelete(BuildContext ctx) async {
    final handle = _image?.originalHandle;
    final l = ctx.l10n;
    final bridge = ctx.services.bridge;
    final messenger = ScaffoldMessenger.of(ctx);
    final yes = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(l.deleteSourceImage),
        content: Text(l.deleteSourceImageBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.keep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if ((yes ?? false) && handle != null) {
      if (await bridge.deleteSourceImage(handle)) {
        messenger.showSnackBar(SnackBar(content: Text(l.imageDeleted)));
      }
    }
  }

  /// Puts a piece of the text that was read into [field].
  void _use(String value, OcrField field) {
    final r = _result;
    if (r == null) return;
    setState(() {
      _result = switch (field) {
        OcrField.username => r.copyWith(username: value),
        OcrField.password => r.copyWith(password: value),
        OcrField.link => r.copyWith(url: value),
        OcrField.name => r.copyWith(title: value),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(l.scanScreenshot)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(l.pickImage),
                onPressed: _busy ? null : () => _pick(camera: false),
              ),
              if (!Platform.isWindows)
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(l.takePhoto),
                  onPressed: _busy ? null : () => _pick(camera: true),
                ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_done && _nothing) ..._failureCard(l),
          if (_done && !_nothing && r != null) ..._found(l, r),
        ],
      ),
    );
  }

  /// Nothing was read: why, what to try, and a way forward.
  List<Widget> _failureCard(AppLocalizations l) => [
    const SizedBox(height: 16),
    Card(
      key: const ValueKey('ocr.failure'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ocrFailureTitle(l, _failure),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            OcrFailureBody(error: _failure),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _createEntry,
              child: Text(l.ocrFillByHand),
            ),
          ],
        ),
      ),
    ),
    OcrWhatWasRead(passes: _scan?.passes ?? const []),
  ];

  /// What was found, the other readings, and every piece of text to pick
  /// from.
  List<Widget> _found(AppLocalizations l, OcrResult r) {
    final theme = Theme.of(context);
    final user = r.username ?? r.email;
    return [
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            _field(l.username, user),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OcrCandidates(
                  values: r.emailCandidates,
                  current: user ?? '',
                  onPick: (v) => setState(
                    () => _result = r.copyWith(username: v, email: v),
                  ),
                ),
              ),
            ),
            _field(l.password, r.password),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OcrCandidates(
                  values: r.passwordCandidates,
                  current: r.password ?? '',
                  onPick: (v) =>
                      setState(() => _result = r.copyWith(password: v)),
                ),
              ),
            ),
            _field(l.url, r.url),
            _field(l.name, r.title),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: _createEntry,
                child: Text(l.addEntry),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(l.ocrChipsTitle, style: theme.textTheme.titleSmall),
      Text(l.ocrTapChip, style: theme.textTheme.bodySmall),
      Text(l.ocrAmbiguous, style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      OcrChips(
        chips: r.chips,
        onUse: _use,
        onCopy: (v) => copySecretWithToast(context, v),
      ),
      OcrWhatWasRead(passes: _scan?.passes ?? const []),
    ];
  }

  Widget _field(String label, String? value) => ListTile(
    title: Text(label),
    subtitle: value == null ? const Text('—') : SecretText(value),
  );
}
