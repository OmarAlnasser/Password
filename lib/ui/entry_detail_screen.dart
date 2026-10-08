import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../data/models/vault_entry.dart';
import '../services/password_generator.dart';
import 'app_scope.dart';
import 'entry_edit_screen.dart';
import 'home_screen.dart';
import 'theme/tokens.dart';
import 'theme/typography.dart';
import 'widgets/glass_bar.dart';
import 'widgets/primary_button.dart';
import 'widgets/reveal.dart';
import 'widgets/secret_text.dart';
import 'widgets/site_icon.dart';
import 'widgets/strength_bar.dart';
import 'widgets/surface_card.dart';
import 'widgets/totp_view.dart';

/// One entry on its own screen (phones, tablets, and the dashboard's links).
/// On a wide window the vault shows the same content in a pane next to the
/// list instead (see [EntryDetailView]).
class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    final session = context.services.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final e = session.byId(entryId);
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassBar(
            actions: [
              if (e != null)
                ...entryActions(
                  context,
                  e,
                  onDeleted: () => Navigator.of(context).maybePop(),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: e == null
              ? const SizedBox.shrink()
              : EntryDetailView(
                  entryId: entryId,
                  topInset:
                      MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                ),
        );
      },
    );
  }
}

/// The favourite, edit and delete buttons of an entry, for an app bar or the
/// header of the detail pane. Deleting asks first, then calls [onDeleted].
List<Widget> entryActions(
  BuildContext context,
  VaultEntry e, {
  required VoidCallback onDeleted,
}) {
  final l = context.l10n;
  final t = context.tokens;
  final session = context.services.session;
  return [
    IconButton(
      isSelected: e.favorite,
      icon: const Icon(Icons.star_border_rounded),
      selectedIcon: Icon(Icons.star_rounded, color: t.accent2),
      tooltip: l.favorite,
      onPressed: () => session.saveEntry(e.edit(favorite: !e.favorite)),
    ),
    IconButton(
      icon: const Icon(Icons.edit_outlined),
      tooltip: l.editEntry,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EntryEditScreen(existing: e)),
      ),
    ),
    IconButton(
      icon: const Icon(Icons.delete_outline_rounded),
      tooltip: l.delete,
      onPressed: () async {
        final ok = await _confirmDelete(context, e);
        if (!ok) return;
        await session.deleteEntry(e.id);
        if (context.mounted) onDeleted();
      },
    ),
  ];
}

Future<bool> _confirmDelete(BuildContext context, VaultEntry e) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(l.deleteConfirm(_isolate(c, e.title))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(l.cancel),
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
  return ok ?? false;
}

/// Keeps a Latin name that sits inside an Arabic sentence from dragging its
/// punctuation to the wrong side (DESIGN section 10, rule 3).
String _isolate(BuildContext context, String s) =>
    context.isArabic && s.isNotEmpty ? '\u2068$s\u2069' : s;

/// Arabic digits to Western ones: the app shows 0-9 in both languages
/// (DESIGN section 3.1), and `intl`'s Arabic dates use Arabic-Indic digits.
String _westernDigits(String s) {
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

/// An entry's name, notes or any other text a user typed. Its direction comes
/// from its first strong letter, not from the layout: Latin text in an Arabic
/// layout stays left-to-right (so a trailing full stop stays on its right) and
/// Arabic text in an English layout stays right-to-left. Either way the text
/// sits at the start edge of the *layout*. One line with an ellipsis by
/// default; [maxLines] null lets it wrap.
class EntryTitle extends StatelessWidget {
  const EntryTitle(this.text, {super.key, this.style, this.maxLines = 1});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  static final _rtlLetter = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
  static final _latinLetter = RegExp('[A-Za-z\u00C0-\u024F]');

  /// The direction of [text] by its first letter, or null with no letters.
  static TextDirection? directionOf(String text) {
    for (final ch in text.characters) {
      if (_rtlLetter.hasMatch(ch)) return TextDirection.rtl;
      if (_latinLetter.hasMatch(ch)) return TextDirection.ltr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final outer = Directionality.of(context);
    final own = directionOf(text) ?? outer;
    final child = Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      style: style,
      textAlign: own == outer
          ? TextAlign.start
          : (outer == TextDirection.rtl ? TextAlign.right : TextAlign.left),
    );
    if (own == outer) return child;
    return Directionality(textDirection: own, child: child);
  }
}

/// The content of an entry: a header with the large site icon, then grouped
/// cards (credentials, details, password history). It scrolls by itself.
///
/// Used by [EntryDetailScreen] and by the right pane of the two-pane vault
/// ([embedded]). Key it by entry id so a revealed password never carries over
/// to the next entry.
class EntryDetailView extends StatefulWidget {
  const EntryDetailView({
    super.key,
    required this.entryId,
    this.embedded = false,
    this.topInset = 0,
    this.onDeleted,
  });

  final String entryId;

  /// In a pane next to the list: content is centred in the pane, top
  /// aligned, and the header carries the favourite, edit and delete buttons,
  /// because there is no app bar of its own.
  final bool embedded;

  /// Space above the first card, for a glass app bar that the content
  /// scrolls under.
  final double topInset;

  /// After the entry was deleted from the header's button (embedded only).
  final VoidCallback? onDeleted;

  @override
  State<EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<EntryDetailView> {
  bool _reveal = false;
  bool _showHistory = false;

  VaultEntry? _strengthOf;
  StrengthResult? _strength;

  StrengthResult _strengthFor(VaultEntry e) {
    if (!identical(_strengthOf, e) || _strength == null) {
      final pw = e.password;
      // zxcvbn gets slow on very long input; the first 128 characters say
      // all there is to say about a password's strength.
      _strength = context.services.strength.evaluate(
        pw.length > 128 ? pw.substring(0, 128) : pw,
        userInputs: [e.username, e.title],
      );
      _strengthOf = e;
    }
    return _strength!;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final session = context.services.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final e = session.byId(widget.entryId);
        if (e == null) return const SizedBox.shrink();
        final totp = parseTotp(e.totpSecret);
        final fmt = DateFormat.yMMMd(
          Localizations.localeOf(context).toString(),
        );
        final divider = Divider(height: 1, thickness: 1, color: t.line);

        final credentials = <Widget>[
          if (e.username.isNotEmpty)
            _FieldRow(
              label: l.username,
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: l.copy,
                onPressed: () => copySecretWithToast(context, e.username),
              ),
              child: LtrText(
                e.username,
                maxLines: 3,
                style: tt.bodyMedium!.copyWith(
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 14.5,
                  color: t.ink,
                ),
              ),
            ),
          if (e.password.isNotEmpty)
            _PasswordRow(
              label: l.password,
              password: e.password,
              reveal: _reveal,
              strength: _strengthFor(e),
              onToggle: () => setState(() => _reveal = !_reveal),
            ),
          if (totp != null) TotpView(totp: totp),
        ];
        final details = <Widget>[
          if (e.url.isNotEmpty)
            _FieldRow(
              label: l.url,
              child: LtrText(
                e.url,
                maxLines: 3,
                style: tt.bodyMedium!.copyWith(
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 14,
                  color: t.ink,
                ),
              ),
            ),
          if (e.notes.isNotEmpty)
            _FieldRow(
              label: l.notes,
              child: EntryTitle(
                e.notes,
                maxLines: null,
                style: tt.bodyLarge!.copyWith(color: t.soft),
              ),
            ),
        ];

        Widget group(List<Widget> rows) => SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) divider,
                rows[i],
              ],
            ],
          ),
        );

        final cards = <Widget>[
          _Header(
            entry: e,
            actions: widget.embedded
                ? entryActions(context, e, onDeleted: widget.onDeleted ?? () {})
                : null,
          ),
          if (credentials.isNotEmpty) group(credentials),
          if (details.isNotEmpty) group(details),
          if (e.history.isNotEmpty)
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                leading: Icon(Icons.history_rounded, color: t.accent2),
                title: Text('${l.passwordHistory} (${e.history.length})'),
                onExpansionChanged: (v) => setState(() => _showHistory = v),
                childrenPadding: const EdgeInsetsDirectional.only(bottom: 8),
                children: [
                  for (final h in e.history)
                    _HistoryRow(
                      item: h,
                      obscure: !_showHistory,
                      date: _westernDigits(fmt.format(h.changedAt.toLocal())),
                    ),
                ],
              ),
            ),
        ];

        return LayoutBuilder(
          builder: (context, c) {
            final gutter = AppSpace.gutter(c.maxWidth);
            final bottom = MediaQuery.paddingOf(context).bottom + 32;
            // At most 640 wide and centred in the screen or in the pane, so
            // a wide pane has no dead strip on one side.
            final minSide = widget.embedded ? gutter + 4 : gutter;
            final side = math.max(minSide, (c.maxWidth - AppLayout.form) / 2);
            final padding = EdgeInsets.fromLTRB(
              side,
              widget.topInset,
              side,
              bottom,
            );
            // Not a lazy list: a card that scrolled away and came back must
            // not play its entrance again (the password card may be open).
            return SingleChildScrollView(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    Reveal(index: i, child: cards[i]),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The big card on top: site icon, name, host and tags.
class _Header extends StatelessWidget {
  const _Header({required this.entry, this.actions});

  final VaultEntry entry;

  /// Favourite, edit and delete, when the screen has no app bar of its own.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final e = entry;
    final name = e.title.isEmpty ? e.host : e.title;
    return SurfaceCard(
      featured: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SiteIcon(url: e.url, title: name, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (name.isNotEmpty)
                      Semantics(
                        header: true,
                        child: EntryTitle(
                          name,
                          maxLines: 3,
                          style: tt.headlineMedium,
                        ),
                      ),
                    if (e.title.isNotEmpty && e.host.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      LtrText(e.host, style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: 4),
                Row(mainAxisSize: MainAxisSize.min, children: actions!),
              ],
            ],
          ),
          if (e.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final tag in e.tags) _TagPill(tag)],
            ),
          ],
        ],
      ),
    );
  }
}

/// A read-only tag (DESIGN section 8.14): 6 px radius, faint violet fill.
class _TagPill extends StatelessWidget {
  const _TagPill(this.tag);

  final String tag;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // Sized to the text: a Container with an alignment would stretch to
      // the full width of the Wrap.
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: t.tagFill,
        borderRadius: BorderRadius.circular(AppRadius.tag),
        border: Border.all(color: t.tagBorder),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          tag,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: t.tagText, letterSpacing: 0),
        ),
      ),
    );
  }
}

/// A labelled value inside a card, with an optional button at the end.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        16,
        12,
        trailing == null ? 16 : 4,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: tt.bodySmall),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// The password in its secret box, with reveal and copy, and its strength.
class _PasswordRow extends StatelessWidget {
  const _PasswordRow({
    required this.label,
    required this.password,
    required this.reveal,
    required this.strength,
    required this.onToggle,
  });

  final String label;
  final String password;
  final bool reveal;
  final StrengthResult strength;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 8),
          SecretBox(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SecretText(
                      password,
                      obscure: !reveal,
                      style: AppText.secret.copyWith(color: t.ink),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    reveal
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 22,
                  ),
                  tooltip: reveal ? l.hide : l.show,
                  onPressed: onToggle,
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: l.copy,
                  onPressed: () => copySecretWithToast(context, password),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          StrengthBar(result: strength),
        ],
      ),
    );
  }
}

/// One old password: masked until the history is opened, with its date.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.obscure,
    required this.date,
  });

  final PasswordHistoryItem item;
  final bool obscure;
  final String date;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SecretText(
                  item.password,
                  obscure: obscure,
                  style: AppText.secret.copyWith(fontSize: 15, color: t.ink),
                ),
                Text(date, style: tt.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: l.copy,
            onPressed: () => copySecretWithToast(context, item.password),
          ),
        ],
      ),
    );
  }
}
