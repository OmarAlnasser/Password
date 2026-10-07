import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// An entry's website icon (see `FaviconService`) in the rounded square tile
/// of a list row or detail header (DESIGN section 8.6), or, while there is
/// none, the first letter of its title on a soft violet gradient tile. Never
/// empty.
///
/// Both states are the same size, radius and border, so a list that mixes
/// them still reads as one set. A website icon sits on a light plate: favicons
/// are drawn for a white browser tab and many of them (a black cat, a black
/// apple) vanish on a dark violet tile. The plate is the tile itself, so there
/// is no second box inside the first.
///
/// The tile is decoration: the row's title already names the entry, so it is
/// excluded from semantics. It does not grow with the system text size.
class SiteIcon extends StatelessWidget {
  const SiteIcon({
    super.key,
    required this.url,
    required this.title,
    this.size = 44,
    this.selected = false,
  });

  /// The entry's URL, not its host: `androidapp://com.example` must not be
  /// mistaken for the website `com.example`.
  final String url;
  final String title;
  final double size;

  /// Lighter border, for the open row of the two-pane layout.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final letter = _LetterTile(title: title, size: size, selected: selected);
    final icons = context.services.favicons;
    if (icons == null) return ExcludeSemantics(child: letter);
    return ExcludeSemantics(
      child: ListenableBuilder(
        listenable: icons,
        builder: (context, _) {
          final bytes = icons.cached(url);
          if (bytes == null) return letter;
          // The plate is inset by 20% of the size on every side.
          final inner = size * 0.6;
          return _PlateTile(
            size: size,
            selected: selected,
            child: Image.memory(
              bytes,
              width: inner,
              height: inner,
              fit: BoxFit.contain,
              // The bytes come from the site: decode them at display size
              // only, and fall back to the letter if they are not a usable
              // image.
              cacheWidth: (inner * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _Letter(
                title: title,
                size: size,
                color: _letterOnPlate(context.tokens),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _initial(String title) =>
    title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

/// The plate behind a website icon: the page's lightest ink in dark mode (the
/// icon is drawn for white), white in light mode.
Color _plate(AppTokens t) => t.isDark ? const Color(0xFFF4F1FA) : Colors.white;

/// A letter that has to read on [_plate].
Color _letterOnPlate(AppTokens t) =>
    t.isDark ? const Color(0xFF3A2570) : t.accent;

BorderRadius _radius(double size) => BorderRadius.circular(size * 0.27);

/// The letter on its own.
class _Letter extends StatelessWidget {
  const _Letter({required this.title, required this.size, this.color});

  final String title;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      _initial(title),
      // The tile is a fixed shape: it does not grow with the system text size.
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: AppFonts.en,
        fontFamilyFallback: const [AppFonts.ar],
        fontSize: size * 0.4,
        fontWeight: FontWeight.w600,
        color: color ?? context.tokens.accent2,
        height: 1,
      ),
    );
  }
}

/// The tile of a website icon: a light plate with the icon centred on it.
class _PlateTile extends StatelessWidget {
  const _PlateTile({
    required this.size,
    required this.selected,
    required this.child,
  });

  final double size;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _plate(t),
        borderRadius: _radius(size),
        border: Border.all(
          color: selected ? t.selectedBorder : t.line2,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: child,
      ),
    );
  }
}

/// The tile of an entry without a website icon: the first letter of its title
/// on a faint brand gradient.
class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.title,
    required this.size,
    required this.selected,
  });

  final String title;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(t.strong.withValues(alpha: 0.30), t.surface2),
            Color.alphaBlend(t.brandEnd.withValues(alpha: 0.14), t.surface2),
          ],
        ),
        borderRadius: _radius(size),
        border: Border.all(
          color: selected ? t.selectedBorder : t.line2,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: _Letter(title: title, size: size),
    );
  }
}
