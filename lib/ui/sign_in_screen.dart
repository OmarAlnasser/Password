import 'package:flutter/material.dart';

import 'app_scope.dart';

/// Sign in to a vault that already exists on the server (new device), or
/// enable sync for the local vault ([enableForLocal]).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.enableForLocal = false});

  final bool enableForLocal;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final s = context.services;
    final sync = s.sync;
    final l = context.l10n;
    if (sync == null) {
      setState(() => _error = l.syncFailed);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.enableForLocal) {
        await sync.enableSync(_email.text, _pw.text);
      } else {
        await sync.signInExisting(_email.text, _pw.text);
      }
      _pw.clear();
      await s.settings.update((x) => x.syncEmail = _email.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on Object {
      // One generic message: do not reveal whether the email exists or
      // which step failed.
      if (mounted) setState(() => _error = l.syncFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.enableForLocal ? l.enableSync : l.signInExisting),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: l.email),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: l.masterPassword,
              errorText: _error,
            ),
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.enableForLocal ? l.enableSync : l.unlock),
          ),
        ],
      ),
    );
  }
}
