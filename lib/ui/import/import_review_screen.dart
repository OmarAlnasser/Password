import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/vault_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../services/import/import_review.dart';
import '../app_scope.dart';
import '../widgets/site_icon.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(l.reviewImport)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: rows.length,
        itemBuilder: (context, i) => switch (rows[i]) {
          final ReviewItem item => _ItemTile(
            item: item,
            onInclude: _busy ? null : (v) => _setInclude(item, v),
            onTap: _busy ? null : () => _edit(item),
          ),
          final String site => _GroupHeader(group: _groups[site]!),
          _ => _Summary(items: items, skipped: widget.skipped),
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _busy || included == 0 ? null : _import,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.importN(included)),
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

/// Background and text colour of an action's chip.
(Color, Color) _actionColors(ColorScheme c, ReviewAction a) => switch (a) {
  ReviewAction.newEntry => (c.primaryContainer, c.onPrimaryContainer),
  ReviewAction.updateExisting => (c.tertiaryContainer, c.onTertiaryContainer),
  ReviewAction.mergedDuplicate => (
    c.secondaryContainer,
    c.onSecondaryContainer,
  ),
  ReviewAction.skipIdentical => (c.surfaceContainerHighest, c.onSurfaceVariant),
  ReviewAction.needsAttention => (c.errorContainer, c.onErrorContainer),
};

/// A small label chip (status or issue).
class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.colors, this.outlined = false});

  final String label;
  final (Color, Color) colors;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? null : bg,
        border: outlined ? Border.all(color: fg) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
        ),
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
    final theme = Theme.of(context);
    final counts = ImportReview.counts(items);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.importFound(items.length),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in ReviewAction.values)
                  if (counts[a]! > 0)
                    _Pill(
                      '${_actionLabel(l, a)}: ${counts[a]}',
                      colors: _actionColors(theme.colorScheme, a),
                    ),
              ],
            ),
            if (skipped > 0) ...[
              const SizedBox(height: 8),
              Text(l.importSkippedRows(skipped)),
            ],
            const SizedBox(height: 8),
            Text(l.importReviewHint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final List<ReviewItem> group;

  @override
  Widget build(BuildContext context) {
    final first = group.first;
    final name = first.siteName.isEmpty
        ? context.l10n.noWebsite
        : first.siteName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          SiteIcon(url: first.entry.url, title: name, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.titleSmall),
          ),
          Text('${group.length}'),
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
    final scheme = Theme.of(context).colorScheme;
    final e = item.entry;
    final existing = item.existing;
    return ListTile(
      leading: Checkbox(
        value: item.include,
        onChanged: onInclude == null ? null : (v) => onInclude!(v ?? false),
      ),
      title: Text(e.username.isEmpty ? l.noUsername : e.username),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.url.isNotEmpty)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(e.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          else if (e.title.isNotEmpty)
            Text(e.title),
          if (item.action == ReviewAction.updateExisting && existing != null)
            Text(l.reviewUpdates(existing.title)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _Pill(
                _actionLabel(l, item.action),
                colors: _actionColors(scheme, item.action),
              ),
              for (final issue in item.issues)
                _Pill(
                  _issueLabel(l, issue),
                  outlined: true,
                  colors: issue.isBlocking
                      ? (scheme.errorContainer, scheme.error)
                      : (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: onTap,
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
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(l.editLogin),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            decoration: InputDecoration(labelText: l.username),
          ),
          gap,
          TextField(
            controller: _pw,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            style: const TextStyle(fontFamily: 'monospace'),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l.password),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.swap_vert),
              label: Text(l.swapUserPassword),
              onPressed: _swap,
            ),
          ),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
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
        FilledButton(
          onPressed: () => Navigator.pop(context, _result()),
          child: Text(l.save),
        ),
      ],
    );
  }
}
