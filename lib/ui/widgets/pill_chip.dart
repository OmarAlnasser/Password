import 'package:flutter/material.dart';

/// A filter pill (the portfolio's `.chip`, DESIGN section 8.3): a stadium with
/// a `line2` border, filled violet when [selected]. A thin wrapper over
/// [ChoiceChip], so keyboard focus, semantics ("selected") and the 48 dp tap
/// target are the framework's; the colours come from `AppTheme`.
///
/// Put the result count ("Showing 4 of 4") in a `bodySmall` line under a row
/// of pills, as the portfolio does.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;

  /// Null disables the pill.
  final ValueChanged<bool>? onSelected;

  /// Optional leading icon (18 px).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null ? null : Icon(icon, size: 18),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
    );
  }
}
