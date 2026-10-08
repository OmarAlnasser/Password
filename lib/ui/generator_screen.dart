import 'package:flutter/material.dart';

import '../services/password_generator.dart';
import 'app_scope.dart';
import 'home_screen.dart';
import 'ocr/ocr_widgets.dart' show PillSegment, PillSegments;
import 'theme/theme.dart';
import 'widgets/focus_ring.dart';
import 'widgets/glass_bar.dart';
import 'widgets/max_width_body.dart';
import 'widgets/primary_button.dart';
import 'widgets/reveal.dart';
import 'widgets/secret_text.dart';
import 'widgets/strength_bar.dart';
import 'widgets/surface_card.dart';

/// The password generator: a big monospace result on a featured card with its
/// strength, a pill toggle between a password and a passphrase, and the
/// options as switch rows. On a wide window the result sits on the left and
/// the options on the right.
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
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppLayout.expanded;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

    final result = _ResultCard(
      value: _value,
      strength: strength,
      bits: bits,
      primaryIsGenerate: !widget.returnResult,
      onGenerate: () => setState(_regen),
      onCopy: () => copySecretWithToast(context, _value),
    );
    final use = widget.returnResult
        ? PrimaryButton(
            expanded: true,
            onPressed: () => Navigator.of(context).pop(_value),
            child: Text(l.useThis),
          )
        : null;
    final options = _Options(options: _o, onChanged: _set);

    final Widget content;
    if (wide) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                result,
                if (use != null) ...[const SizedBox(height: 16), use],
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(flex: 5, child: Reveal(index: 1, child: options)),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          result,
          const SizedBox(height: 16),
          Reveal(index: 1, child: options),
          if (use != null) ...[const SizedBox(height: 20), use],
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(title: Text(l.generator)),
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
}

/// The featured card: the generated value in big monospace, its strength, and
/// the Generate / Copy actions.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.value,
    required this.strength,
    required this.bits,
    required this.primaryIsGenerate,
    required this.onGenerate,
    required this.onCopy,
  });

  final String value;
  final StrengthResult strength;
  final int bits;

  /// Generate is the main action; otherwise "Use this password" is, and both
  /// buttons here are ghost buttons.
  final bool primaryIsGenerate;
  final VoidCallback onGenerate;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final generate = primaryIsGenerate
        ? PrimaryButton(
            expanded: true,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onGenerate,
            child: Text(l.generate),
          )
        : OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.generate),
            onPressed: onGenerate,
          );
    final copy = OutlinedButton.icon(
      icon: const Icon(Icons.copy_rounded),
      label: Text(l.copy),
      onPressed: onCopy,
    );
    return SurfaceCard(
      featured: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _Tag(icon: Icons.bolt_rounded, label: '≈ $bits bits'),
          ),
          const SizedBox(height: 14),
          // The value is the star of the screen: big, mono, always LTR.
          SecretText(
            value,
            style: AppText.secret.copyWith(
              fontSize: 26,
              height: 1.4,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 18),
          StrengthBar(result: strength),
          const SizedBox(height: 20),
          // Large system text: one button per line, so no label breaks.
          if (MediaQuery.textScalerOf(context).scale(15) > 19) ...[
            generate,
            const SizedBox(height: 12),
            copy,
          ] else
            Row(
              children: [
                Expanded(child: generate),
                const SizedBox(width: 12),
                Expanded(child: copy),
              ],
            ),
        ],
      ),
    );
  }
}

/// The portfolio's `.tag`: a small read-only pill of metadata.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 12, 4),
      decoration: BoxDecoration(
        color: t.tagFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: t.tagBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: t.accent),
            const SizedBox(width: 6),
          ],
          Flexible(
            // Digits and the approximation sign read left to right.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                label,
                style: AppText.secretSmall.copyWith(
                  color: t.tagText,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill toggle between a password and a passphrase, and the options of
/// the active kind.
class _Options extends StatelessWidget {
  const _Options({required this.options, required this.onChanged});

  final GeneratorOptions options;
  final ValueChanged<GeneratorOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final o = options;
    final rows = <_SwitchRowData>[
      _SwitchRowData('abc', l.lowercase, o.lower, (v) => o.copyWith(lower: v)),
      _SwitchRowData('ABC', l.uppercase, o.upper, (v) => o.copyWith(upper: v)),
      _SwitchRowData('123', l.digits, o.digits, (v) => o.copyWith(digits: v)),
      _SwitchRowData(
        '#@!',
        l.symbols,
        o.symbols,
        (v) => o.copyWith(symbols: v),
      ),
      _SwitchRowData(
        '0O',
        l.excludeAmbiguous,
        o.excludeAmbiguous,
        (v) => o.copyWith(excludeAmbiguous: v),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PillSegments<bool>(
          selected: o.passphrase,
          segments: [
            PillSegment(
              value: false,
              icon: Icons.password_rounded,
              label: l.password,
            ),
            PillSegment(
              value: true,
              icon: Icons.short_text_rounded,
              label: l.passphrase,
            ),
          ],
          onChanged: (v) => onChanged(o.copyWith(passphrase: v)),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: o.passphrase
              ? _SliderBlock(
                  label: l.words(o.words),
                  min: 3,
                  max: 12,
                  value: o.words,
                  onChanged: (v) => onChanged(o.copyWith(words: v)),
                )
              : _SliderBlock(
                  label: l.length(o.length),
                  min: 8,
                  max: 64,
                  value: o.length,
                  onChanged: (v) => onChanged(o.copyWith(length: v)),
                ),
        ),
        if (!o.passphrase) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(indent: 70),
                    _SwitchRow(
                      data: rows[i],
                      onChanged: (v) => onChanged(rows[i].apply(v)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A length / word-count slider with its value above it and the range under
/// its ends.
class _SliderBlock extends StatelessWidget {
  const _SliderBlock({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int min;
  final int max;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    final ends = AppText.secretSmall.copyWith(color: t.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(label, style: tt.titleMedium)),
        Slider(
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          value: value.toDouble(),
          semanticFormatterCallback: (_) => label,
          onChanged: (v) => onChanged(v.round()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$min', style: ends),
                Text('$max', style: ends),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SwitchRowData {
  const _SwitchRowData(this.sample, this.title, this.value, this.apply0);

  /// A few characters of what the option adds, shown on the leading tile.
  final String sample;
  final String title;
  final bool value;
  final GeneratorOptions Function(bool) apply0;

  GeneratorOptions apply(bool v) => apply0(v);
}

/// One option: a tile showing a sample of the characters, the name, and a
/// switch.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.data, required this.onChanged});

  final _SwitchRowData data;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FocusRing(
      child: SwitchListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 2, 12, 2),
        secondary: ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: t.line2),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                data.sample,
                textScaler: TextScaler.noScaling,
                style: AppText.secretSmall.copyWith(
                  color: data.value ? t.accent2 : t.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        title: Text(data.title),
        value: data.value,
        onChanged: onChanged,
      ),
    );
  }
}
