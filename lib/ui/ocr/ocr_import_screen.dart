import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/vault_entry.dart';
import '../../services/ocr/ocr_engine.dart';
import '../../services/ocr/ocr_parser.dart';
import '../../services/vault_session.dart';
import '../app_scope.dart';
import '../entry_edit_screen.dart';
import '../home_screen.dart';
import '../widgets/secret_text.dart';

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
  OcrResult? _result;
  bool _busy = false;
  String? _error;

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
    _cleanupTemp();
    setState(() {
      _image = img;
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final lines = await OcrEngine.forPlatform(context.services.bridge)
          .recognize(img.path);
      final r = OcrCredentialParser().parse(lines);
      if (!mounted) return;
      setState(() {
        _result = r;
        if (r.chips.isEmpty) _error = context.l10n.ocrNoText;
      });
    } on Object {
      if (mounted) setState(() => _error = context.l10n.error);
    } finally {
      // OCR is done; the text is in memory, the copy is no longer needed.
      if (img.isTempCopy) {
        try {
          File(img.path).deleteSync();
        } on Object {
          // best effort
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createEntry() async {
    final r = _result!;
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

  void _useAs(String value) async {
    final l = context.l10n;
    final r = _result!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l.ocrUseAs)),
            for (final (k, label) in [
              ('user', l.username),
              ('pass', l.password),
              ('url', l.url),
              ('title', l.title),
            ])
              ListTile(title: Text(label), onTap: () => Navigator.pop(c, k)),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      _result = OcrResult(
        chips: r.chips,
        email: r.email,
        title: choice == 'title' ? value : r.title,
        username: choice == 'user' ? value : r.username,
        password: choice == 'pass' ? value : r.password,
        url: choice == 'url' ? value : r.url,
      );
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
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (r != null && r.chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _field(l.username, r.username),
                  _field(l.password, r.password),
                  _field(l.url, r.url),
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
            Text(l.ocrTapChip, style: Theme.of(context).textTheme.bodySmall),
            Text(l.ocrAmbiguous, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in r.chips)
                  GestureDetector(
                    onLongPress: () => _useAs(chip),
                    child: ActionChip(
                      label: SecretText(chip),
                      onPressed: () => copySecretWithToast(context, chip),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String? value) => ListTile(
    title: Text(label),
    subtitle: value == null ? const Text('—') : SecretText(value),
  );
}
