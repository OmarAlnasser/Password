import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app_scope.dart';
import 'home_screen.dart';

/// Windows global-hotkey popup: type to filter, Enter copies the password of
/// the first match (Shift+Enter copies the username), Esc hides the window.
class QuickSearchScreen extends StatefulWidget {
  const QuickSearchScreen({super.key});

  @override
  State<QuickSearchScreen> createState() => _QuickSearchScreenState();
}

class _QuickSearchScreenState extends State<QuickSearchScreen> {
  final _q = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (mounted) Navigator.of(context).maybePop();
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final items = context.services.session.entries
        .where((e) => e.matches(_q.text.trim()))
        .take(8)
        .toList();
    if (_selected >= items.length) _selected = 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
          () =>
              _selected = (_selected + 1) % (items.isEmpty ? 1 : items.length),
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
          () => _selected = _selected == 0 ? items.length - 1 : _selected - 1,
        ),
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.quickSearch)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.search,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (_) => setState(() => _selected = 0),
                onSubmitted: (_) async {
                  if (items.isEmpty) return;
                  final e = items[_selected];
                  final shift = HardwareKeyboard.instance.isShiftPressed;
                  await copySecretWithToast(
                    context,
                    shift ? e.username : e.password,
                  );
                  await _close();
                },
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (var i = 0; i < items.length; i++)
                    ListTile(
                      selected: i == _selected,
                      title: Text(items[i].title),
                      subtitle: Text(items[i].username),
                      onTap: () async {
                        await copySecretWithToast(context, items[i].password);
                        await _close();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
