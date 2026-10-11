import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../services/browser/browser_activity.dart';
import '../../services/browser/browser_bridge.dart';
import '../app_scope.dart';
import '../theme/theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/focus_ring.dart';
import '../widgets/glass_bar.dart';
import '../widgets/icon_tile.dart';
import '../widgets/max_width_body.dart';
import '../widgets/section_header.dart';
import '../widgets/surface_card.dart';

/// Settings > Browser extension (Windows): the switch, how to add the
/// extension to the browser, the paired browsers and the activity log.
class BrowserExtensionScreen extends StatelessWidget {
  const BrowserExtensionScreen({super.key, required this.bridge});

  final BrowserBridge bridge;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = bridge.settings;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, bridge, bridge.activity]),
      builder: (context, _) {
        final on = settings.browserExtension;
        final paired = settings.pairedBrowsers.reversed.toList();
        final unseen = bridge.activity.unseen;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(title: Text(l.browserExtension)),
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
              _Card(
                children: [
                  FocusRing(
                    child: SwitchListTile(
                      contentPadding: IconTile.rowPadding,
                      secondary: const IconTile(icon: Icons.extension_outlined),
                      title: Text(l.browserExtension),
                      subtitle: Text(l.browserExtensionHint),
                      value: on,
                      onChanged: (v) => _toggle(context, v),
                    ),
                  ),
                ],
              ),
              if (on) ...[
                const SizedBox(height: 24),
                _Header(l.browserSetupTitle),
                _SetupSteps(
                  folder: bridge.registration?.extensionFolder.path ?? '',
                ),
                const SizedBox(height: 24),
                _Header(l.pairedBrowsers),
                _Card(
                  children: [
                    if (paired.isEmpty)
                      ListTile(
                        contentPadding: IconTile.rowPadding,
                        leading: const IconTile(icon: Icons.link_off_rounded),
                        title: Text(l.noPairedBrowsers),
                      ),
                    for (final b in paired)
                      ListTile(
                        contentPadding: IconTile.rowPadding,
                        leading: const IconTile(icon: Icons.public_rounded),
                        title: Text(b.name.isEmpty ? l.browserUnknown : b.name),
                        subtitle: Text(
                          l.pairedOn(formatActivityDate(context, b.pairedAt)),
                        ),
                        trailing: TextButton(
                          onPressed: () => bridge.unpair(b.keyHash),
                          child: Text(l.unpairBrowser),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _Card(
                  children: [
                    FocusRing(
                      child: ListTile(
                        contentPadding: IconTile.rowPadding,
                        leading: const IconTile(icon: Icons.history_rounded),
                        title: Text(l.browserActivity),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (unseen > 0) Badge(label: Text('$unseen')),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: context.tokens.muted,
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                BrowserActivityScreen(log: bridge.activity),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggle(BuildContext context, bool on) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!on) {
      await bridge.disable();
      return;
    }
    final bool ok;
    try {
      ok = await bridge.enable();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.error)));
      return;
    }
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.browserExtensionMissing)),
      );
    }
  }
}

class _SetupSteps extends StatelessWidget {
  const _SetupSteps({required this.folder});

  final String folder;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final messenger = ScaffoldMessenger.of(context);

    Widget step(int n, String text, [List<Widget> extra = const []]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: t.surface2,
            child: Text('$n', style: tt.labelMedium),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(text, style: tt.bodyMedium),
                ),
                ...extra,
              ],
            ),
          ),
        ],
      ),
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          step(1, l.browserStep1, [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(l.copyAddress),
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: 'chrome://extensions'),
                  );
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.addressCopied)),
                  );
                },
              ),
            ),
          ]),
          step(2, l.browserStep2),
          step(3, l.browserStep3, [
            const SizedBox(height: 6),
            SelectableText(
              folder,
              textDirection: TextDirection.ltr,
              style: AppText.secret.copyWith(fontSize: 13, color: t.soft),
            ),
            if (folder.isNotEmpty && Platform.isWindows)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(l.openFolder),
                  onPressed: () =>
                      unawaited(Process.run('explorer.exe', [folder])),
                ),
              ),
          ]),
          step(4, l.browserStep4),
        ],
      ),
    );
  }
}

/// What the browser extension did, newest first. Opening it marks every line
/// as seen.
class BrowserActivityScreen extends StatefulWidget {
  const BrowserActivityScreen({super.key, required this.log});

  final BrowserActivityLog log;

  @override
  State<BrowserActivityScreen> createState() => _BrowserActivityScreenState();
}

class _BrowserActivityScreenState extends State<BrowserActivityScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: marking notifies, which must not happen while
    // this screen is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _seen());
    widget.log.addListener(_seen);
  }

  @override
  void dispose() {
    widget.log.removeListener(_seen);
    super.dispose();
  }

  // Lines that arrive while the screen is open are seen too.
  void _seen() {
    if (widget.log.unseen > 0) unawaited(widget.log.markSeen());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final events = widget.log.events;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(
            title: Text(l.browserActivity),
            actions: [
              if (events.isNotEmpty)
                TextButton(
                  onPressed: widget.log.clear,
                  child: Text(l.clearActivity),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: events.isEmpty
              ? EmptyState(
                  icon: Icons.history_rounded,
                  title: l.browserActivity,
                  message: l.browserActivityEmpty,
                )
              : ListView(
                  padding: MaxWidthBody.insets(
                    context,
                    maxWidth: AppLayout.form,
                    base: EdgeInsets.only(
                      top: topInset,
                      bottom: MediaQuery.paddingOf(context).bottom + 32,
                    ),
                  ),
                  children: [
                    _Card(
                      children: [
                        for (final e in events)
                          ListTile(
                            contentPadding: IconTile.rowPadding,
                            leading: IconTile(icon: _icon(e.kind)),
                            title: Text(_describe(context, e)),
                            subtitle: Text(
                              [
                                _iso(
                                  context,
                                  formatActivityDate(context, e.at, time: true),
                                ),
                                if (e.browser.isNotEmpty) e.browser,
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  static IconData _icon(BrowserActivityKind k) => switch (k) {
    BrowserActivityKind.filled => Icons.input_rounded,
    BrowserActivityKind.saved => Icons.add_circle_outline_rounded,
    BrowserActivityKind.updated => Icons.sync_lock_outlined,
    BrowserActivityKind.paired => Icons.link_rounded,
  };

  /// Keeps a date or a Latin name in an Arabic line from being reordered
  /// (DESIGN section 10).
  static String _iso(BuildContext context, String s) =>
      context.isArabic && s.isNotEmpty ? '\u2068$s\u2069' : s;

  static String _describe(BuildContext context, BrowserActivity e) {
    final l = context.l10n;
    String iso(String s) => _iso(context, s);
    final title = iso(e.title.isEmpty ? e.host : e.title);
    return switch (e.kind) {
      BrowserActivityKind.filled => l.activityFilled(title, iso(e.host)),
      BrowserActivityKind.saved => l.activitySaved(iso(e.host)),
      BrowserActivityKind.updated => l.activityUpdated(title),
      BrowserActivityKind.paired => l.activityPaired(
        e.browser.isEmpty ? l.browserUnknown : iso(e.browser),
      ),
    };
  }
}

/// A date (and with [time], the time) in the app's language, with Western
/// digits (DESIGN section 3.1).
String formatActivityDate(
  BuildContext context,
  DateTime at, {
  bool time = false,
}) {
  final locale = Localizations.localeOf(context).toString();
  final local = at.toLocal();
  var s = DateFormat.yMMMd(locale).format(local);
  if (time) s = '$s ${DateFormat.Hm(locale).format(local)}';
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
    child: SectionHeader(title: title, size: SectionHeaderSize.group),
  );
}

/// A card of rows with a hairline between them.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: EdgeInsets.zero,
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 66),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Asks the user to allow a browser extension that wants to pair
/// ([BrowserBridge.pendingPairing]). Sits above the app's `Navigator`, like
/// `UpdateGate`, and shows the question as a dialog inside it.
class BrowserPairingGate extends StatefulWidget {
  const BrowserPairingGate({
    super.key,
    required this.bridge,
    required this.navigatorKey,
    required this.child,
  });

  final BrowserBridge? bridge;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<BrowserPairingGate> createState() => _BrowserPairingGateState();
}

class _BrowserPairingGateState extends State<BrowserPairingGate> {
  PairingRequest? _showing;

  @override
  void initState() {
    super.initState();
    widget.bridge?.addListener(_changed);
  }

  @override
  void didUpdateWidget(BrowserPairingGate old) {
    super.didUpdateWidget(old);
    if (old.bridge != widget.bridge) {
      old.bridge?.removeListener(_changed);
      widget.bridge?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.bridge?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final bridge = widget.bridge;
    final request = bridge?.pendingPairing;
    final nav = widget.navigatorKey.currentState;
    if (request == null) {
      // Answered elsewhere, timed out or the browser went away.
      if (_showing != null) {
        _showing = null;
        nav?.popUntil((r) => r is! DialogRoute || !r.isCurrent);
      }
      return;
    }
    if (identical(request, _showing) || nav == null || bridge == null) return;
    _showing = request;
    unawaited(
      showDialog<bool>(
        context: nav.context,
        barrierDismissible: false,
        animationStyle: nav.context.motionStyle,
        builder: (ctx) => _PairDialog(request: request),
      ).then((allow) {
        if (identical(_showing, request)) _showing = null;
        if (identical(bridge.pendingPairing, request)) {
          bridge.answerPairing(allow ?? false);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PairDialog extends StatelessWidget {
  const _PairDialog({required this.request});

  final PairingRequest request;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final browser = request.browser.isEmpty
        ? l.browserUnknown
        : (context.isArabic
              ? '\u2068${request.browser}\u2069'
              : request.browser);
    return AlertDialog(
      icon: const Center(child: IconTile(icon: Icons.extension_outlined)),
      title: Text(l.pairTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.pairBody(browser)),
          const SizedBox(height: 16),
          Text(
            request.code,
            textDirection: TextDirection.ltr,
            style: AppText.secret.copyWith(
              fontSize: 28,
              letterSpacing: 4,
              color: t.accent2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.pairDeny),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.pairAllow),
        ),
      ],
    );
  }
}
