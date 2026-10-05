import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import 'app_scope.dart';
import 'home_screen.dart';
import 'widgets/secret_text.dart';
import 'widgets/strength_bar.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key, this.returnResult = false});

  /// When true, "Use this password" pops with the generated value.
  final bool returnResult;

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  GeneratorOptions _o = const GeneratorOptions();
  String _value = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_value.isEmpty) _regen();
  }

  void _regen() => _value = context.services.generator.generate(_o);

  void _set(GeneratorOptions o) => setState(() {
    _o = o;
    _regen();
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final strength = context.services.strength.evaluate(_value);
    final bits = context.services.generator.entropyBits(_o).round();
    return Scaffold(
      appBar: AppBar(title: Text(l.generator)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SecretText(
                _value,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const SizedBox(height: 8),
          StrengthBar(result: strength),
          Text('≈ $bits bits', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(l.generate),
                  onPressed: () => setState(_regen),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(l.copy),
                  onPressed: () => copySecretWithToast(context, _value),
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: Text(l.passphrase),
            value: _o.passphrase,
            onChanged: (v) => _set(_o.copyWith(passphrase: v)),
          ),
          if (_o.passphrase) ...[
            ListTile(title: Text(l.words(_o.words))),
            Slider(
              min: 3,
              max: 12,
              divisions: 9,
              value: _o.words.toDouble(),
              onChanged: (v) => _set(_o.copyWith(words: v.round())),
            ),
          ] else ...[
            ListTile(title: Text(l.length(_o.length))),
            Slider(
              min: 8,
              max: 64,
              divisions: 56,
              value: _o.length.toDouble(),
              onChanged: (v) => _set(_o.copyWith(length: v.round())),
            ),
            CheckboxListTile(
              title: Text(l.lowercase),
              value: _o.lower,
              onChanged: (v) => _set(_o.copyWith(lower: v)),
            ),
            CheckboxListTile(
              title: Text(l.uppercase),
              value: _o.upper,
              onChanged: (v) => _set(_o.copyWith(upper: v)),
            ),
            CheckboxListTile(
              title: Text(l.digits),
              value: _o.digits,
              onChanged: (v) => _set(_o.copyWith(digits: v)),
            ),
            CheckboxListTile(
              title: Text(l.symbols),
              value: _o.symbols,
              onChanged: (v) => _set(_o.copyWith(symbols: v)),
            ),
            CheckboxListTile(
              title: Text(l.excludeAmbiguous),
              value: _o.excludeAmbiguous,
              onChanged: (v) => _set(_o.copyWith(excludeAmbiguous: v)),
            ),
          ],
          if (widget.returnResult)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_value),
                child: Text(l.useThis),
              ),
            ),
        ],
      ),
    );
  }
}
