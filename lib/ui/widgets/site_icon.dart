import 'package:flutter/material.dart';

import '../app_scope.dart';

/// An entry's website icon (see `FaviconService`), or the first letter of
/// its title while there is none.
class SiteIcon extends StatelessWidget {
  const SiteIcon({
    super.key,
    required this.url,
    required this.title,
    this.size = 40,
  });

  /// The entry's URL, not its host: `androidapp://com.example` must not be
  /// mistaken for the website `com.example`.
  final String url;
  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = CircleAvatar(
      radius: size / 2,
      child: Text(title.isEmpty ? '?' : title.characters.first.toUpperCase()),
    );
    final icons = context.services.favicons;
    if (icons == null) return letter;
    return ListenableBuilder(
      listenable: icons,
      builder: (context, _) {
        final bytes = icons.cached(url);
        if (bytes == null) return letter;
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 5),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.contain,
            // The bytes come from the site: decode them at display size only,
            // and fall back to the letter if they are not a usable image.
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => letter,
          ),
        );
      },
    );
  }
}
