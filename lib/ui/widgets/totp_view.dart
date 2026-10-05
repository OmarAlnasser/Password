import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/crypto/crypto.dart';
import '../app_scope.dart';
import '../home_screen.dart';
import 'secret_text.dart';

/// Parses a stored TOTP value (otpauth URI or bare Base32 secret).
Totp? parseTotp(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  try {
    return v.toLowerCase().startsWith('otpauth://')
        ? Totp.fromUri(v)
        : Totp.fromBase32(v);
  } on VaultCryptoException {
    return null;
  }
}

/// Current code with a countdown ring that refreshes every second.
class TotpView extends StatefulWidget {
  const TotpView({super.key, required this.totp});

  final Totp totp;

  @override
  State<TotpView> createState() => _TotpViewState();
}

class _TotpViewState extends State<TotpView> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.totp.now();
    final left = widget.totp.secondsRemaining();
    final pretty = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    return ListTile(
      title: Text(context.l10n.oneTimeCode),
      subtitle: SecretText(
        pretty,
        highlightAmbiguous: false,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      leading: SizedBox.square(
        dimension: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: left / widget.totp.period,
              color: left <= 5 ? Theme.of(context).colorScheme.error : null,
            ),
            Text('$left'),
          ],
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: context.l10n.copy,
        onPressed: () => copySecretWithToast(context, code),
      ),
    );
  }
}
