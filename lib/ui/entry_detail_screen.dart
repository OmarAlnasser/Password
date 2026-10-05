import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'app_scope.dart';
import 'entry_edit_screen.dart';
import 'home_screen.dart';
import 'widgets/secret_text.dart';
import 'widgets/totp_view.dart';

class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _reveal = false;
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final session = context.services.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final e = session.byId(widget.entryId);
        if (e == null) return const Scaffold();
        final totp = parseTotp(e.totpSecret);
        final fmt = DateFormat.yMMMd(
          Localizations.localeOf(context).toString(),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(e.title),
            actions: [
              IconButton(
                icon: Icon(e.favorite ? Icons.star : Icons.star_border),
                tooltip: l.favorite,
                onPressed: () =>
                    session.saveEntry(e.edit(favorite: !e.favorite)),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: l.editEntry,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntryEditScreen(existing: e),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l.delete,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(l.deleteConfirm(e.title)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(l.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(l.delete),
                        ),
                      ],
                    ),
                  );
                  if (ok ?? false) {
                    await session.deleteEntry(e.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
          body: ListView(
            children: [
              if (e.username.isNotEmpty)
                ListTile(
                  title: Text(l.username),
                  subtitle: Text(e.username),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: l.copy,
                    onPressed: () => copySecretWithToast(context, e.username),
                  ),
                ),
              if (e.password.isNotEmpty)
                ListTile(
                  title: Text(l.password),
                  subtitle: SecretText(e.password, obscure: !_reveal),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _reveal ? Icons.visibility_off : Icons.visibility,
                        ),
                        tooltip: _reveal ? l.hide : l.show,
                        onPressed: () => setState(() => _reveal = !_reveal),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: l.copy,
                        onPressed: () =>
                            copySecretWithToast(context, e.password),
                      ),
                    ],
                  ),
                ),
              if (totp != null) TotpView(totp: totp),
              if (e.url.isNotEmpty)
                ListTile(
                  title: Text(l.url),
                  subtitle: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(e.url),
                  ),
                ),
              if (e.tags.isNotEmpty)
                ListTile(
                  title: Text(l.tags),
                  subtitle: Wrap(
                    spacing: 6,
                    children: [for (final t in e.tags) Chip(label: Text(t))],
                  ),
                ),
              if (e.notes.isNotEmpty)
                ListTile(title: Text(l.notes), subtitle: Text(e.notes)),
              if (e.history.isNotEmpty)
                ExpansionTile(
                  title: Text('${l.passwordHistory} (${e.history.length})'),
                  onExpansionChanged: (v) => setState(() => _showHistory = v),
                  children: [
                    for (final h in e.history)
                      ListTile(
                        title: SecretText(h.password, obscure: !_showHistory),
                        subtitle: Text(fmt.format(h.changedAt.toLocal())),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () =>
                              copySecretWithToast(context, h.password),
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
}
