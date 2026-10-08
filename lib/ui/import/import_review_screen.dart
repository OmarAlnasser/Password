import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/vault_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../services/import/import_review.dart';
import '../app_scope.dart';
import '../theme/theme.dart';
import '../widgets/focus_ring.dart';
import '../widgets/glass_bar.dart';
import '../widgets/max_width_body.dart';
import '../widgets/primary_button.dart';
import '../widgets/reveal.dart';
import '../widgets/site_icon.dart';
import '../widgets/surface_card.dart';
import '../widgets/secret_text.dart';

/// Shows what a CSV import (Chrome, Bitwarden) would do before anything is
/// saved: logins grouped by site, what happens to each one and what looks
/// wrong with it. The user ticks what to import and can fix a login by
/// tapping it.
///
/// Pops with the number of entries saved, or null when left without
/// importing.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({
    super.key,
    required this.imported,
    this.skipped = 0,
  });

  /// Logins parsed from the file (`ImportExport.importCsv`).
  final List<VaultEntry> imported;

  /// Rows of the file that were not logins, for the summary.
  final int skipped;

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  /// The rows as the user has fixed them so far.
  late List<VaultEntry> _rows = [...widget.imported];

  /// Ticks the user changed, by row entry id, so they survive running the
  /// review again after an edit.
  final _choices = <String, bool>{};
  List<ReviewItem>? _items;
  Map<String, List<ReviewItem>> _groups = const {};
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null) _review();
  }

  void _review() {
    final items = ImportReview.review(_rows, context.services.session.entries);
    for (final item in items) {
      for (final i in item.rows) {
        final choice = _choices[_rows[i].id];
        if (choice != null) {
          item.include = choice;
          break;
        }
      }
    }
    _items = items;
    _groups = ImportReview.group(items);
  }

  void _setInclude(ReviewItem item, bool include) => setState(() {
    item.include = include;
    for (final i in item.rows) {
      _choices[_rows[i].id] = include;
    }
  });

  /// Replaces the rows of [item] with the user's corrected login and reviews
  /// the file again (the fix may change its status or merge it).
  Future<void> _edit(ReviewItem item) async {
    final edited = await showDialog<VaultEntry>(
      context: context,
      animationStyle: context.motionStyle,
      builder: (_) => _EditLoginDialog(entry: item.entry),
    );
    if (edited == null || !mounted) return;
    final keep = item.rows.reduce(math.min);
    final drop = {...item.rows}..remove(keep);
    setState(() {
      _rows = [
        for (var i = 0; i < _rows.length; i++)
          if (i == keep) edited else if (!drop.contains(i)) _rows[i],
      ];
      // Fixed by hand: the user wants it.
      _choices[edited.id] = true;
      _review();
    });
  }

  Future<void> _import() async {
    final s = context.services;
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // Against the vault as it is now, in case a sync changed it meanwhile.
      final entries = ImportReview.apply(_items!, current: s.session.entries);
      await s.session.saveEntries(entries);
      s.prefetchIcons();
      navigator.pop(entries.length);
    } on Object {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l.error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final items = _items!;
    final included = items.where((i) => i.include).length;
    // Flat list for the builder: the summary, then each group header
    // (String) followed by its items.
    final rows = <Object?>[
      null,
      for (final MapEntry(key: site, value: group) in _groups.entries) ...[
        site,
        ...group,
      ],
    ];
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(title: Text(l.reviewImport)),
      body: ListView.builder(
        padding: MaxWidthBody.insets(
          context,
          maxWidth: AppLayout.form,
          base: EdgeInsets.only(top: topInset, bottom: 16),
        ),
        itemCount: rows.length,
        itemBuilder: (context, i) => switch (rows[i]) {
          final ReviewItem item => Reveal(
            enabled: i < 8,
            index: i,
            child: _ItemTile(
              item: item,
              onInclude: _busy ? null : (v) => _setInclude(item, v),
              onTap: _busy ? null : () => _edit(item),
            ),
          ),
          final String site => _GroupHeader(group: _groups[site]!),
          _ => Reveal(
            child: _Summary(items: items, skipped: widget.skipped),
          ),
        },
      ),
      // The one action of the screen, always in reach.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bg2,
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          // heightFactor 1: the bar is as high as its button, not the page.
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppLayout.form + 2 * AppSpace.gutterOf(context),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpace.gutterOf(context),
                  vertical: 12,
                ),
                child: PrimaryButton(
                  expanded: true,
                  onPressed: _busy || included == 0 ? null : _import,
                  child: _busy
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.onStrong,
                          ),
                        )
                      : Text(l.importN(included)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _actionLabel(AppLocalizations l, ReviewAction a) => switch (a) {
  ReviewAction.newEntry => l.reviewNew,
  ReviewAction.updateExisting => l.reviewUpdate,
  ReviewAction.mergedDuplicate => l.reviewMerged,
  ReviewAction.skipIdentical => l.reviewSkip,
  ReviewAction.needsAttention => l.reviewAttention,
};

String _issueLabel(AppLocalizations l, ReviewIssue i) => switch (i) {
  ReviewIssue.missingPassword => l.issueMissingPassword,
  ReviewIssue.missingUsername => l.issueMissingUsername,
  ReviewIssue.invalidEmail => l.issueInvalidEmail,
  ReviewIssue.usernameIsUrl => l.issueUsernameIsUrl,
  ReviewIssue.passwordLooksLikeEmail => l.issuePasswordLooksLikeEmail,
  ReviewIssue.usernameLooksLikePassword => l.issueUsernameLooksLikePassword,
  ReviewIssue.invalidUrl => l.issueInvalidUrl,
  ReviewIssue.insecureHttp => l.issueInsecureHttp,
  ReviewIssue.duplicateInFile => l.issueDuplicateInFile,
  ReviewIssue.existsWithDifferentPassword => l.issueExistsWithDifferentPassword,
};

/// How a chip looks: fill, outline, and text/icon colour.
class _Tone {
  const _Tone(this.fill, this.border, this.fg);

  final Color fill;
  final Color border;
  final Color fg;
}

/// The portfolio's chip style per action: a violet pill for new logins, amber
/// for an update, the read-only tag look for merged duplicates, a quiet one
/// for what is already saved and red for what needs attention. Each also has
/// its own icon, so colour is never the only signal.
(_Tone, IconData) _actionStyle(AppTokens t, ReviewAction a) => switch (a) {
  ReviewAction.newEntry => (
    _Tone(t.selected, t.selectedBorder, t.accent2),
    Icons.add_circle_outline_rounded,
  ),
  ReviewAction.updateExisting => (
    _Tone(t.warnContainer, t.warn.withValues(alpha: 0.45), t.warn),
    Icons.update_rounded,
  ),
  ReviewAction.mergedDuplicate => (
    _Tone(t.tagFill, t.tagBorder, t.tagText),
    Icons.call_merge_rounded,
  ),
  ReviewAction.skipIdentical => (
    _Tone(t.surface2, t.line2, t.muted),
    Icons.check_circle_outline_rounded,
  ),
  ReviewAction.needsAttention => (
    _Tone(t.errorContainer, t.error.withValues(alpha: 0.5), t.onErrorContainer),
    Icons.warning_amber_rounded,
  ),
};

/// A small label pill (status or issue).
class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.tone, required this.icon});

  final String label;
  final _Tone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 11, 4),
      decoration: ShapeDecoration(
        color: tone.fill,
        shape: StadiumBorder(side: BorderSide(color: tone.border)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 15, color: tone.fg)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: tt.labelMedium!.copyWith(
                color: tone.fg,
                fontSize: context.isArabic ? 13 : 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items, required this.skipped});

  final List<ReviewItem> items;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final counts = ImportReview.counts(items);
    return SurfaceCard(
      featured: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.importFound(items.length), style: tt.titleLarge),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in ReviewAction.values)
                if (counts[a]! > 0)
                  _Pill(
                    '${_actionLabel(l, a)}: ${counts[a]}',
                    tone: _actionStyle(t, a).$1,
                    icon: _actionStyle(t, a).$2,
                  ),
            ],
          ),
          if (skipped > 0) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: t.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.importSkippedRows(skipped),
                    style: tt.bodyMedium!.copyWith(color: t.soft),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(l.importReviewHint, style: tt.bodySmall),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final List<ReviewItem> group;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final first = group.first;
    final name = first.siteName.isEmpty
        ? context.l10n.noWebsite
        : first.siteName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          SiteIcon(url: first.entry.url, title: name, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                name,
                style: tt.titleSmall!.copyWith(color: t.ink, fontSize: 15),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: t.surface,
              shape: StadiumBorder(side: BorderSide(color: t.line2)),
            ),
            child: Text(
              '${group.length}',
              style: AppText.numeral.copyWith(
                fontSize: 13,
                color: t.soft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, this.onInclude, this.onTap});

  final ReviewItem item;
  final ValueChanged<bool>? onInclude;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final e = item.entry;
    final existing = item.existing;
    final (tone, icon) = _actionStyle(t, item.action);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // A ticked login is a selected row: tinted fill, lighter border.
      child: SurfaceCard(
        selected: item.include,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: FocusRing(
            radius: AppRadius.card,
            child: ListTile(
              contentPadding: const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 8),
              // Named after the login, so a screen reader says which one it
              // ticks ("name@example.com, example.com, checked").
              leading: MergeSemantics(
                child: Semantics(
                  label: [
                    e.username.isEmpty ? l.noUsername : e.username,
                    if (e.url.isNotEmpty) e.url else e.title,
                  ].where((x) => x.isNotEmpty).join(', '),
                  child: Checkbox(
                    value: item.include,
                    onChanged: onInclude == null
                        ? null
                        : (v) => onInclude!(v ?? false),
                  ),
                ),
              ),
              title: e.username.isEmpty
                  ? Text(
                      l.noUsername,
                      style: tt.bodyMedium!.copyWith(color: t.muted),
                    )
                  : LtrText(
                      e.username,
                      style: TextStyle(color: t.ink, fontSize: 14),
                    ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.url.isNotEmpty)
                    LtrText(e.url)
                  else if (e.title.isNotEmpty)
                    Text(e.title),
                  if (item.action == ReviewAction.updateExisting &&
                      existing != null) ...[
                    const SizedBox(height: 2),
                    Text(l.reviewUpdates(existing.title)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Pill(
                        _actionLabel(l, item.action),
                        tone: tone,
                        icon: icon,
                      ),
                      for (final issue in item.issues)
                        _Pill(
                          _issueLabel(l, issue),
                          icon: issue.isBlocking
                              ? Icons.error_outline_rounded
                              : Icons.info_outline_rounded,
                          tone: _Tone(
                            Colors.transparent,
                            issue.isBlocking
                                ? t.error.withValues(alpha: 0.6)
                                : t.line2,
                            issue.isBlocking ? t.error : t.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: Icon(Icons.edit_outlined, size: 20, color: t.muted),
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixes one imported login: every field, plus a swap for the common case of
/// username and password in each other's columns.
class _EditLoginDialog extends StatefulWidget {
  const _EditLoginDialog({required this.entry});

  final VaultEntry entry;

  @override
  State<_EditLoginDialog> createState() => _EditLoginDialogState();
}

class _EditLoginDialogState extends State<_EditLoginDialog> {
  late final _title = TextEditingController(text: widget.entry.title);
  late final _user = TextEditingController(text: widget.entry.username);
  late final _pw = TextEditingController(text: widget.entry.password);
  late final _url = TextEditingController(text: widget.entry.url);
  late final _notes = TextEditingController(text: widget.entry.notes);

  @override
  void dispose() {
    for (final c in [_title, _user, _pw, _url, _notes]) {
      c
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  void _swap() => setState(() {
    final user = _user.text;
    _user.text = _pw.text;
    _pw.text = user;
  });

  /// The login with the user's values; everything else (history of merged
  /// rows, tags, TOTP, dates) is kept.
  VaultEntry _result() {
    final e = widget.entry;
    final pw = _pw.text;
    return VaultEntry(
      id: e.id,
      title: _title.text.trim(),
      username: _user.text.trim(),
      password: pw,
      url: _url.text.trim(),
      notes: _notes.text,
      tags: e.tags,
      favorite: e.favorite,
      totpSecret: e.totpSecret,
      history: [
        for (final h in e.history)
          if (h.password != pw) h,
      ],
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      passwordChangedAt: e.passwordChangedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    const gap = SizedBox(height: 14);
    // Latin-only fields: left to right in Arabic too, at the start edge.
    final latinAlign = Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left;
    final mono = AppText.secret.copyWith(
      fontSize: 15,
      letterSpacing: 0.3,
      color: t.ink,
    );
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.tint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line2),
            ),
            child: Icon(Icons.edit_outlined, size: 20, color: t.accent2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(l.editLogin)),
        ],
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The dialog's own padding clips a floating label at the top.
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: l.title),
          ),
          gap,
          TextField(
            controller: _user,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            // Read left to right in Arabic too: bidi would move a trailing
            // "!" to the front.
            textDirection: TextDirection.ltr,
            textAlign: latinAlign,
            style: mono,
            decoration: InputDecoration(labelText: l.username),
          ),
          gap,
          TextField(
            controller: _pw,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            style: mono,
            textDirection: TextDirection.ltr,
            textAlign: latinAlign,
            decoration: InputDecoration(labelText: l.password),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.swap_vert_rounded),
              label: Text(l.swapUserPassword),
              onPressed: _swap,
            ),
          ),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            textAlign: latinAlign,
            style: mono,
            decoration: InputDecoration(labelText: l.url),
          ),
          gap,
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 4,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(labelText: l.notes),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        PrimaryButton(
          glow: false,
          onPressed: () => Navigator.pop(context, _result()),
          child: Text(l.save),
        ),
      ],
    );
  }
}
