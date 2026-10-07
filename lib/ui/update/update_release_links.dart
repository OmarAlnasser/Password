import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/update/update_providers.dart';

/// "Open release page" and "Copy link": the way out when an update cannot be
/// installed by the app itself (a protected folder, a different signing key,
/// a manifest this version cannot read).
///
/// The page is [releasePageUri], the public release list of the app's own
/// repository. "Open release page" only appears where the app can open a
/// browser ([UrlOpener], Windows today); "Copy link" is always there and
/// confirms in place for a few seconds (a snack bar would sit behind the
/// sheet's scrim).
class UpdateReleaseLinks extends StatefulWidget {
  const UpdateReleaseLinks({super.key, this.openUrl});

  /// Defaults to [platformUrlOpener].
  final UrlOpener? openUrl;

  @override
  State<UpdateReleaseLinks> createState() => _UpdateReleaseLinksState();
}

class _UpdateReleaseLinksState extends State<UpdateReleaseLinks> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    // The page is public; it is plain clipboard text, not a secret.
    await Clipboard.setData(ClipboardData(text: releasePageUri.toString()));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final open = widget.openUrl ?? platformUrlOpener;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (open != null)
          OutlinedButton.icon(
            onPressed: () => unawaited(open(releasePageUri)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(l.updateOpenReleasePage),
          ),
        Semantics(
          liveRegion: true,
          child: TextButton.icon(
            onPressed: () => unawaited(_copy()),
            icon: Icon(_copied ? Icons.check : Icons.link, size: 18),
            label: Text(_copied ? l.updateLinkCopied : l.updateCopyLink),
          ),
        ),
      ],
    );
  }
}
