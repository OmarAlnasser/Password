# Bundled fonts

All fonts are shipped inside the app. The app never downloads fonts and never
uses the `google_fonts` package: a password manager must not tell a font CDN
that this app is running. All three families are licensed under the SIL Open
Font License 1.1; each folder keeps its `OFL.txt`, and those texts are also
declared as Flutter assets (see `pubspec.yaml`) so an in-app licences screen can
show them.

| Family (Flutter name) | Files | Weights | Used for |
|---|---|---|---|
| `Outfit` | `outfit/Outfit-{Regular,Medium,SemiBold,Bold}.ttf` | 400 500 600 700 | English / Latin UI text |
| `IBMPlexSansArabic` | `ibm-plex-sans-arabic/IBMPlexSansArabic-{Regular,Medium,SemiBold,Bold}.ttf` | 400 500 600 700 | Arabic UI text, and the fallback for Outfit |
| `JetBrainsMono` | `jetbrains-mono/JetBrainsMono-{Regular,Medium}.ttf` | 400 500 | Passwords, emails, URLs, codes |

Outfit has no Arabic glyphs; IBM Plex Sans Arabic has Arabic and Latin.
JetBrains Mono has Latin, Cyrillic and Greek only.

## Provenance

Downloaded from `https://raw.githubusercontent.com/google/fonts/main/ofl/<family>/`
on 2026-10-06. Magic bytes checked (`00 01 00 00`, TrueType outlines).

| Family | Upstream file | Upstream SHA-256 | Change made here |
|---|---|---|---|
| IBM Plex Sans Arabic | `IBMPlexSansArabic-{Regular,Medium,SemiBold,Bold}.ttf` | identical to the shipped files (below) | none, byte-for-byte |
| Outfit | `Outfit[wght].ttf` (variable, wght 100-900, default instance is Thin) | `fc7287273e66929776e2ba54f144fe699080bec29f61bf649d70d871468aeade` | four static instances |
| JetBrains Mono | `JetBrainsMono[wght].ttf` (variable, wght 100-800, default 400) | `48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda` | two static instances, `calt` feature removed |

**Why static instances.** google/fonts only publishes Outfit and JetBrains Mono
as variable fonts. Flutter does drive the `wght` axis from `FontWeight`
(checked by rendering), but Outfit's default instance is Thin, and variable-axis
handling is the part most likely to differ between the Android, iOS and Windows
text stacks. Static files render the same everywhere. Flutter's `FontLoader`
takes the weight from the font file itself (checked: it has no weight
parameter and still picks the right file per `FontWeight`), so every instance
has its OS/2 `usWeightClass` set to its weight, and the `weight:` values in
`pubspec.yaml` mirror those numbers.

**Why `calt` is removed from JetBrains Mono.** The font ships coding ligatures:
`->` becomes an arrow, `!=` becomes a not-equal sign, `==` and `<=` fuse. Inside
a password that silently changes what the user sees. Removing the feature from
the files means no screen can forget to disable it. `SecretText` should still set
`fontFeatures: [FontFeature.disable('calt')]` as a second guard.

**Licence notes.** IBM Plex carries the Reserved Font Name "Plex", so those files
must stay unmodified (do not subset or rename them). Outfit and JetBrains Mono
declare no Reserved Font Name; the instances are Modified Versions under OFL 1.1
and keep the original copyright and licence text. The fonts are not sold on their
own.

## How the instances were made

With `fonttools` (4.66) in a throw-away virtualenv:

1. `fontTools.varLib.instancer.instantiateVariableFont(font, {"wght": N}, updateFontNames=True)`
   for N = 400, 500, 600, 700 (Outfit) and 400, 500 (JetBrains Mono).
2. Set the name table (IDs 1, 2, 3, 4, 6, 16, 17), `OS/2.usWeightClass` and the
   `fsSelection` / `macStyle` bits so Regular and Bold are flagged properly.
3. JetBrains Mono only: `fontTools.subset` over its whole cmap with the layout
   feature list minus `calt`, `liga`, `clig`, `dlig` (glyph count 1179 to 1168).

## Shipped files

| SHA-256 | File |
|---|---|
| `6f611412270a132bbac838da9259d4c68569b4175f3b3b8fa3fa36a30b56dab9` | `ibm-plex-sans-arabic/IBMPlexSansArabic-Regular.ttf` |
| `b8363ab9f733dfa4f8e96b8b2102c24b5cf4110fb96d1d3d9a9412f6fb49cf74` | `ibm-plex-sans-arabic/IBMPlexSansArabic-Medium.ttf` |
| `597bd5502e5997be4414e4c9c88834b30ff3784250c84f20bce2b20e53ebd467` | `ibm-plex-sans-arabic/IBMPlexSansArabic-SemiBold.ttf` |
| `691e0c891a38637ae6bbdb69700f8042cb0724a137bee615068ffdb92244f61f` | `ibm-plex-sans-arabic/IBMPlexSansArabic-Bold.ttf` |
| `91a1f61781a2b3f3d5ee0aa51bf93278d8dc856ab60770739c98e62610cf0c68` | `outfit/Outfit-Regular.ttf` |
| `85cd51a4b755d0889362fb144b083cfeaaa7829d3ee93f8131a04738ea6a52a2` | `outfit/Outfit-Medium.ttf` |
| `b9c95ee2211f370d5fa2724532fcebb7027dc98c565bd1ef73ea075259980b89` | `outfit/Outfit-SemiBold.ttf` |
| `695afc1760ac1ba04578782234d94528043818edc67b083620883e1d6b4a46e4` | `outfit/Outfit-Bold.ttf` |
| `79fcbda592c8f17186c776b97cbdcf1a0d5c5f7459fda06394df0c0b26626b4e` | `jetbrains-mono/JetBrainsMono-Regular.ttf` |
| `f860c58da88137bb5e65b3b083a5fc5c5a79bbecc0f6b1e7158a5fcaf8297840` | `jetbrains-mono/JetBrainsMono-Medium.ttf` |

Total: 1,381,672 bytes of fonts plus 13,244 bytes of licence text.
