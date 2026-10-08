import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../data/models/vault_entry.dart';
import '../services/breach_checker.dart';
import 'app_scope.dart';
import 'entry_detail_screen.dart';
import 'theme/theme.dart';
import 'widgets/focus_ring.dart';
import 'widgets/glass_bar.dart';
import 'widgets/max_width_body.dart';
import 'widgets/primary_button.dart';
import 'widgets/reveal.dart';
import 'widgets/secret_text.dart';
import 'widgets/site_icon.dart';
import 'widgets/stat_tile.dart';
import 'widgets/surface_card.dart';

/// The security dashboard: one score for the whole vault on a ring, four
/// small stat tiles (weak, reused, old, breached) and, below them, the logins
/// behind each number in folding lists. The breach check is a button here and
/// never runs by itself.
///
/// All of it is worked out on the device from the decrypted vault; only the
/// breach check talks to the network (k-anonymity, see `hibpExplain`).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, int>? _breached;
  bool _checking = false;
  String? _error;

  final _weakKey = GlobalKey<_FindingCardState>();
  final _reusedKey = GlobalKey<_FindingCardState>();
  final _oldKey = GlobalKey<_FindingCardState>();
  final _breachedKey = GlobalKey<_FindingCardState>();

  Future<void> _checkBreaches() async {
    final s = context.services;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await SecurityAnalyzer(s.strength)
          .checkBreaches(s.session.entries, s.breaches);
      if (mounted) setState(() => _breached = r);
    } on Object {
      if (mounted) setState(() => _error = context.l10n.error);
    } finally {
      s.breaches.clearCache();
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Opens the list behind a stat tile and scrolls it into view.
  void _reveal(GlobalKey<_FindingCardState> key) {
    key.currentState?.open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: context.motion(AppMotion.page),
        curve: AppMotion.ease,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = context.services;
    final x = _Txt.of(context);
    final entries = s.session.entries;
    final report = SecurityAnalyzer(s.strength).analyze(entries);
    final byId = {for (final e in entries) e.id: e};
    final breached = _breached;
    final hibp = s.settings.hibpEnabled;
    final health = _Health.of(entries, report, breached);

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppLayout.expanded;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

    final reusedEntries = [for (final g in report.reused) ...g];
    final breachedEntries = [
      if (breached != null)
        for (final id in breached.keys) ?byId[id],
    ];

    final hero = health.total == 0
        ? _EmptyScore(text: x)
        : _ScoreCard(health: health, text: x);

    final stats = StatGrid(
      columns: wide ? 4 : 2,
      tiles: [
        StatTile(
          value: '${report.weak.length}',
          label: l.weakPasswords,
          valueColor: _numeral(context, report.weak.length),
          onTap: () => _reveal(_weakKey),
        ),
        StatTile(
          value: '${reusedEntries.length}',
          label: l.reusedPasswords,
          valueColor: _numeral(context, reusedEntries.length),
          onTap: () => _reveal(_reusedKey),
        ),
        StatTile(
          value: '${report.old.length}',
          label: l.oldPasswords,
          valueColor: _numeral(context, report.old.length),
          onTap: () => _reveal(_oldKey),
        ),
        if (hibp)
          StatTile(
            value: breached == null ? '—' : '${breached.length}',
            label: l.breachedPasswords,
            valueColor: breached == null
                ? context.tokens.muted
                : _numeral(context, breached.length, bad: true),
            onTap: breached == null ? null : () => _reveal(_breachedKey),
          ),
      ],
    );

    Widget finding(
      GlobalKey<_FindingCardState> key,
      String title,
      IconData icon,
      List<VaultEntry> items, {
      String Function(VaultEntry)? detail,
      bool bad = false,
    }) => _FindingCard(
      key: key,
      title: title,
      icon: icon,
      items: items,
      detail: detail,
      bad: bad,
      emptyText: l.allGood,
    );

    final lists = <Widget>[
      finding(
        _weakKey,
        l.weakPasswords,
        Icons.warning_amber_rounded,
        report.weak,
      ),
      finding(
        _reusedKey,
        l.reusedPasswords,
        Icons.copy_all_rounded,
        reusedEntries,
      ),
      finding(_oldKey, l.oldPasswords, Icons.history_rounded, report.old),
    ];

    final breachCard = hibp
        ? _BreachCard(
            checking: _checking,
            error: _error,
            onCheck: _checkBreaches,
          )
        : null;
    final breachedList = hibp && breached != null
        ? finding(
            _breachedKey,
            l.breachedPasswords,
            Icons.gpp_bad_outlined,
            breachedEntries,
            detail: (e) => '× ${breached[e.id]}',
            bad: true,
          )
        : null;

    Widget stack(List<Widget> children, {int from = 0}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Reveal(index: from + i, child: children[i]),
        ],
      ],
    );

    final Widget content;
    if (wide) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Each column is its own focus group, so Tab finishes one column
          // before it moves to the other.
          Expanded(
            flex: 5,
            child: FocusTraversalGroup(
              child: stack([hero, ?breachCard, ?breachedList]),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 7,
            child: FocusTraversalGroup(
              child: stack([stats, ...lists], from: 1),
            ),
          ),
        ],
      );
    } else {
      content = stack([hero, stats, ...lists, ?breachCard, ?breachedList]);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(title: Text(l.securityDashboard)),
      body: ListView(
        padding: MaxWidthBody.insets(
          context,
          maxWidth: wide ? AppLayout.page : AppLayout.form,
          base: EdgeInsets.only(
            top: topInset,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
          ),
        ),
        children: [content],
      ),
    );
  }

  /// The colour of a count: mint at zero, lavender otherwise (red for
  /// breached passwords). Never the only signal: the list says it too.
  Color _numeral(BuildContext context, int n, {bool bad = false}) {
    final t = context.tokens;
    if (n == 0) return t.good;
    return bad ? t.error : t.accent2;
  }
}

// -----------------------------------------------------------------------------
// The score
// -----------------------------------------------------------------------------

/// What the vault looks like in numbers: the score and who counts against it.
class _Health {
  const _Health({
    required this.total,
    required this.flagged,
    required this.score,
  });

  /// Logins that have a password.
  final int total;

  /// Logins with at least one finding.
  final int flagged;

  /// 0 to 100.
  final int score;

  /// The index into the five strength labels and colours.
  int get level => score >= 90
      ? 4
      : score >= 75
      ? 3
      : score >= 55
      ? 2
      : score >= 35
      ? 1
      : 0;

  /// A login counts against the score by its worst finding: weak and breached
  /// passwords fully, reused ones a little less, old ones least.
  factory _Health.of(
    List<VaultEntry> entries,
    SecurityReport report,
    Map<String, int>? breached,
  ) {
    final weight = <String, double>{};
    void flag(Iterable<VaultEntry> items, double w) {
      for (final e in items) {
        weight[e.id] = math.max(weight[e.id] ?? 0, w);
      }
    }

    flag(report.weak, 1);
    flag([for (final g in report.reused) ...g], 0.6);
    flag(report.old, 0.35);
    for (final id in breached?.keys ?? const <String>[]) {
      weight[id] = 1;
    }
    final total = entries.where((e) => e.password.isNotEmpty).length;
    if (total == 0) return const _Health(total: 0, flagged: 0, score: 100);
    final penalty = weight.values.fold<double>(0, (a, b) => a + b);
    final score = (100 * (1 - penalty / total)).round().clamp(0, 100);
    return _Health(total: total, flagged: weight.length, score: score);
  }
}

/// The hero: the score on a ring, what it means and how many logins need a
/// look.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.health, required this.text});

  final _Health health;
  final _Txt text;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final labels = [
      l.strength0,
      l.strength1,
      l.strength2,
      l.strength3,
      l.strength4,
    ];
    final level = health.level;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.scoreTitle,
          style: tt.labelMedium!.copyWith(
            color: t.accent2,
            letterSpacing: context.isArabic ? 0 : 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          child: Text(
            labels[level],
            style: tt.headlineSmall!.copyWith(color: t.rampText[level]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          health.flagged == 0
              ? l.allGood
              : text.attention(health.flagged, health.total),
          style: tt.bodyMedium!.copyWith(color: t.soft),
        ),
      ],
    );
    final bigText = MediaQuery.textScalerOf(context).scale(14) > 19;
    return SurfaceCard(
      featured: true,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, c) {
          // A smaller ring keeps it beside the text on a small phone.
          final ring = _ScoreRing(
            score: health.score,
            level: level,
            size: c.maxWidth < 340 ? 112 : 132,
          );
          if (c.maxWidth < 280 || bigText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ring,
                const SizedBox(height: 16),
                Align(alignment: AlignmentDirectional.centerStart, child: info),
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: 20),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }
}

/// The ring itself. The arc and the number count up once when the screen
/// appears (instantly with "reduce motion"); the colour is the strength ramp
/// step of the score, and the label next to the ring says the same in words.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.level, this.size = 132});

  final int score;
  final int level;

  /// Side of the square the ring is drawn in.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      container: true,
      label: '${_Txt.of(context).scoreTitle}: $score / 100',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: score / 100),
          duration: context.motion(const Duration(milliseconds: 1100)),
          curve: AppMotion.ease,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
              progress: v,
              color: t.ramp[level],
              track: t.surface3,
              glow: t.isDark,
              mirror: rtl,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(v * 100).round()}',
                    textScaler: TextScaler.noScaling,
                    style: AppText.numeral.copyWith(
                      fontSize: size * 0.32,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    '/ 100',
                    // "/ 100" reads left to right in Arabic too.
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.noScaling,
                    style: AppText.numeral.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.glow,
    required this.mirror,
  });

  final double progress;
  final Color color;
  final Color track;
  final bool glow;

  /// Right-to-left layouts fill the ring from the start edge, so the arc runs
  /// the other way round.
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 4);
    if (mirror) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep < 0.01) return;
    if (glow) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweep, 0.02),
          colors: [Color.lerp(color, track, 0.45)!, color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.glow != glow ||
      old.mirror != mirror;
}

/// No password to judge yet: a calm card instead of a score of 100.
class _EmptyScore extends StatelessWidget {
  const _EmptyScore({required this.text});

  final _Txt text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      featured: true,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _IconTile(
            icon: Icons.shield_outlined,
            size: 56,
            color: t.accent2,
            fill: t.tint,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(text.emptyTitle, style: tt.titleMedium),
                ),
                const SizedBox(height: 4),
                Text(
                  text.emptyBody,
                  style: tt.bodyMedium!.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The lists
// -----------------------------------------------------------------------------

/// A folding list of the logins behind one number. A stat tile opens it.
class _FindingCard extends StatefulWidget {
  const _FindingCard({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyText,
    this.detail,
    this.bad = false,
  });

  final String title;
  final IconData icon;
  final List<VaultEntry> items;
  final String emptyText;

  /// Second line of a row instead of the username.
  final String Function(VaultEntry)? detail;

  /// Red instead of amber (breached passwords).
  final bool bad;

  @override
  State<_FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<_FindingCard> {
  bool _open = false;

  void open() {
    if (!_open) setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final items = widget.items;
    final clean = items.isEmpty;
    final Color tone = clean ? t.good : (widget.bad ? t.error : t.warn);
    final Color toneFill = clean
        ? t.goodContainer
        : (widget.bad ? t.errorContainer : t.warnContainer);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              child: FocusRing(
                radius: AppRadius.control,
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      14,
                      12,
                      8,
                      12,
                    ),
                    child: Row(
                      children: [
                        _IconTile(
                          icon: clean
                              ? Icons.check_circle_outline_rounded
                              : widget.icon,
                          color: tone,
                          fill: toneFill,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.title, style: tt.titleMedium),
                        ),
                        const SizedBox(width: 8),
                        _CountPill(count: items.length, color: tone),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: context.motion(AppMotion.fast),
                          child: Icon(Icons.expand_more_rounded, color: t.soft),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: context.motion(AppMotion.page),
              curve: AppMotion.ease,
              alignment: AlignmentDirectional.topStart,
              child: _open
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: t.line),
                        if (clean)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              widget.emptyText,
                              style: tt.bodyMedium!.copyWith(color: t.soft),
                            ),
                          )
                        else
                          for (final e in items)
                            _EntryRow(entry: e, detail: widget.detail?.call(e)),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// The number of logins in a list, as a small pill in the list's colour.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: t.surface2,
        shape: StadiumBorder(side: BorderSide(color: t.line2)),
      ),
      child: Text(
        '$count',
        style: AppText.numeral.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// One login in a list: its icon, name and username (or [detail]); a tap
/// opens it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, this.detail});

  final VaultEntry entry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final sub = detail ?? entry.username;
    final title = entry.title.isEmpty ? '—' : entry.title;
    return FocusRing(
      radius: AppRadius.control,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EntryDetailScreen(entryId: entry.id),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
            child: Row(
              children: [
                SiteIcon(url: entry.url, title: entry.title, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EntryTitle(title, style: tt.titleMedium),
                      if (sub.isNotEmpty) LtrText(sub),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The breach check
// -----------------------------------------------------------------------------

/// What the check sends (nothing that identifies a password) and the button
/// that runs it. A failure is said in words with an icon, under the button.
class _BreachCard extends StatelessWidget {
  const _BreachCard({
    required this.checking,
    required this.error,
    required this.onCheck,
  });

  final bool checking;
  final String? error;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconTile(
                icon: Icons.privacy_tip_outlined,
                color: t.accent2,
                fill: t.tint,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l.hibpExplain,
                    style: tt.bodyMedium!.copyWith(color: t.soft),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            expanded: true,
            icon: checking
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.onStrong,
                    ),
                  )
                : const Icon(Icons.travel_explore_rounded),
            onPressed: checking ? null : onCheck,
            child: Text(l.checkBreaches),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.errorContainer,
                  borderRadius: AppRadius.controlAll,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: t.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: tt.bodyMedium!.copyWith(
                          color: t.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small pieces
// -----------------------------------------------------------------------------

/// A rounded tile with an icon: the mark of a card.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.color,
    required this.fill,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final Color fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(lerpDouble(8, 16, size / 56)!),
          border: Border.all(color: context.tokens.line2),
        ),
        child: Icon(icon, size: size * 0.52, color: color),
      ),
    );
  }
}

/// The few words only this screen needs. They are written here, in both
/// languages, until they move into `lib/l10n/*.arb` with the others.
class _Txt {
  const _Txt(this.ar);

  factory _Txt.of(BuildContext context) => _Txt(context.isArabic);

  final bool ar;

  String get scoreTitle => ar ? 'درجة الأمان' : 'Security score';

  String attention(int n, int total) => ar
      ? '$n من $total حسابات تحتاج إلى انتباه'
      : '$n of $total logins need a look';

  String get emptyTitle =>
      ar ? 'لا توجد كلمات مرور للفحص بعد' : 'No passwords to check yet';

  String get emptyBody => ar
      ? 'أضف حسابًا وستظهر درجة الأمان هنا.'
      : 'Add a login and your security score shows up here.';
}
