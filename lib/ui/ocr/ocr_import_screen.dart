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
import '../theme/theme.dart';
import '../widgets/glass_bar.dart';
import '../widgets/max_width_body.dart';
import '../widgets/primary_button.dart';
import '../widgets/reveal.dart';
import '../widgets/secret_text.dart';
import '../widgets/surface_card.dart';
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
      animationStyle: ctx.motionStyle,
      builder: (c) => AlertDialog(
        // Centre: the dialog's icon slot is tight, which would stretch a
        // tile with a fixed size into a flat bar.
        icon: Center(
          child: OcrIconTile(
            icon: Icons.delete_outline_rounded,
            size: 56,
            color: c.tokens.error,
            fill: c.tokens.errorContainer,
          ),
        ),
        title: Text(l.deleteSourceImage, textAlign: TextAlign.center),
        content: Text(l.deleteSourceImageBody, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.keep),
          ),
          PrimaryButton(
            destructive: true,
            glow: false,
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
    final t = context.tokens;
    final r = _result;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    final bigText = MediaQuery.textScalerOf(context).scale(15) > 19;
    final pick = PrimaryButton(
      expanded: true,
      icon: const Icon(Icons.image_outlined),
      onPressed: _busy ? null : () => _pick(camera: false),
      child: Text(l.pickImage),
    );
    final camera = Platform.isWindows
        ? null
        : OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(l.takePhoto),
            onPressed: _busy ? null : () => _pick(camera: true),
          );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(title: Text(l.scanScreenshot)),
      body: ListView(
        padding: MaxWidthBody.insets(
          context,
          maxWidth: AppLayout.form,
          base: EdgeInsets.only(
            top: topInset,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
          ),
        ),
        children: [
          Reveal(
            child: SurfaceCard(
              featured: true,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_image == null && !_busy) ...[
                    // First visit: what this screen is for, in one line.
                    Row(
                      children: [
                        const OcrIconTile(
                          icon: Icons.document_scanner_outlined,
                          size: 48,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l.ocrReview,
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(color: t.soft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (camera == null)
                    pick
                  else
                    // Side by side only where each button can keep its label
                    // on one line.
                    LayoutBuilder(
                      builder: (context, c) => c.maxWidth >= 440 && !bigText
                          ? Row(
                              children: [
                                Expanded(child: pick),
                                const SizedBox(width: 12),
                                Expanded(child: camera),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                pick,
                                const SizedBox(height: 12),
                                camera,
                              ],
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (_busy) ...[const SizedBox(height: 16), const _ScanningCard()],
          if (_done && _nothing) ..._failureCard(l),
          if (_done && !_nothing && r != null) ..._found(l, r),
        ],
      ),
    );
  }

  /// Nothing was read: why, what to try, and a way forward.
  List<Widget> _failureCard(AppLocalizations l) {
    final t = context.tokens;
    return [
      const SizedBox(height: 16),
      Reveal(
        child: SurfaceCard(
          key: const ValueKey('ocr.failure'),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OcrIconTile(
                    icon: Icons.search_off_rounded,
                    color: t.warn,
                    fill: t.warnContainer,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        ocrFailureTitle(l, _failure),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              OcrFailureBody(error: _failure),
              const SizedBox(height: 18),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _createEntry,
                  label: Text(l.ocrFillByHand),
                ),
              ),
            ],
          ),
        ),
      ),
      OcrWhatWasRead(passes: _scan?.passes ?? const []),
    ];
  }

  /// What was found, the other readings, and every piece of text to pick
  /// from.
  List<Widget> _found(AppLocalizations l, OcrResult r) {
    final tt = Theme.of(context).textTheme;
    final user = r.username ?? r.email;
    const pad = EdgeInsetsDirectional.fromSTEB(72, 0, 16, 8);
    return [
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _field(Icons.person_outline_rounded, l.username, user),
              Padding(
                padding: pad,
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
              _divider(),
              _field(Icons.key_rounded, l.password, r.password),
              Padding(
                padding: pad,
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
              _divider(),
              _field(Icons.link_rounded, l.url, r.url),
              _divider(),
              _field(Icons.label_outline_rounded, l.name, r.title),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: PrimaryButton(
                  expanded: true,
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _createEntry,
                  child: Text(l.addEntry),
                ),
              ),
            ],
          ),
        ),
      ),
      if (r.chips.isNotEmpty) ...[
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(l.ocrChipsTitle, style: tt.titleMedium),
            ),
            const SizedBox(height: 4),
            Text(l.ocrTapChip, style: tt.bodySmall),
            const SizedBox(height: 2),
            Text(l.ocrAmbiguous, style: tt.bodySmall),
            const SizedBox(height: 10),
            OcrChips(
              chips: r.chips,
              onUse: _use,
              onCopy: (v) => copySecretWithToast(context, v),
            ),
          ],
        ),
      ],
      OcrWhatWasRead(passes: _scan?.passes ?? const []),
    ];
  }

  Widget _divider() => const Divider(indent: 72, endIndent: 16);

  /// One detected value: a small icon tile, its label and the value in
  /// monospace (always left-to-right, ambiguous characters highlighted).
  Widget _field(IconData icon, String label, String? value) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
      leading: OcrIconTile(icon: icon),
      title: Text(label, style: tt.bodySmall),
      subtitle: value == null
          ? Text('—', style: tt.bodyLarge!.copyWith(color: t.muted))
          : SecretText(value, style: tt.bodyLarge!.copyWith(color: t.ink)),
    );
  }
}

/// While the scanner works: a calm spinner on a glowing tile (no text: the
/// scan has no steps worth naming).
class _ScanningCard extends StatelessWidget {
  const _ScanningCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.tint,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.line2),
            boxShadow: [BoxShadow(color: t.buttonGlow, blurRadius: 28)],
          ),
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: t.accent2),
          ),
        ),
      ),
    );
  }
}
