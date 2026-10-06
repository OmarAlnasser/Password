import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'site_avatar.dart';

/// An entry's website icon (see `FaviconService`) in the 44 px rounded tile of
/// a list row or detail header (DESIGN section 8.6), or, while there is none,
/// the first letter of its title on a soft violet gradient tile. Never empty.
///
/// The website icon sits in a [SiteAvatar]; the letter fallback is a sibling
/// tile of the same size, radius and border with a faint brand gradient, so a
/// list that mixes both still reads as one set. The tile is decoration: the
/// row's title already names the entry, so it is excluded from semantics.
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
          // SiteAvatar insets its child by 18% of the size on every side.
          final inner = size * (1 - 2 * 0.18);
          return SiteAvatar(
            title: title,
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
              errorBuilder: (_, _, _) => _Letter(title: title, size: size),
            ),
          );
        },
      ),
    );
  }
}

String _initial(String title) =>
    title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

/// The letter on its own, in the style of `SiteAvatar`'s fallback.
class _Letter extends StatelessWidget {
  const _Letter({required this.title, required this.size});

  final String title;
  final double size;

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
        color: context.tokens.accent2,
        height: 1,
      ),
    );
  }
}

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
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: selected ? t.selectedBorder : t.line2),
      ),
      child: _Letter(title: title, size: size),
    );
  }
}
