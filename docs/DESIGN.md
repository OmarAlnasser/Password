# Design system

Status: design brief for the UI refresh. Written from the owner's portfolio
site (`styles.css`, `index.html`, screenshots at 1440x900 and 390x844, Arabic
and English) and then checked by rendering a specimen screen with the real
bundled fonts in dark and light, English and Arabic (RTL), phone and desktop.
Every contrast ratio below was computed (WCAG 2.x relative luminance), not
estimated.

Read `docs/SECURITY.md` first. The UI rules that follow from it are in
section 12 and they win over anything visual in this file.

## 0. Ground rules

* **The app name is not final.** Never write it in UI code. Read it from the
  single constant in `lib/brand.dart`. The brand tile shows the first letter of
  that constant (the portfolio shows "O"), computed at run time.
* **Dark is the identity.** New installs default to dark. Light is a full
  second theme with the same violet character, not an afterthought. System
  stays available.
* **No network for looks.** Fonts are bundled (section 3.1). No remote images,
  no CDN, no analytics. The only existing network image feature is the
  opt-in website-icon fetch described in `docs/SECURITY.md` item 17.
* **Texts, widget types and semantics that tests find stay.** Primary actions
  stay `FilledButton` with their current labels ('I saved it', 'Create',
  'Unlock'). Restyle through `ThemeData`, not by swapping widget types.
* **Secrets are always left-to-right monospace** (section 10).

## 1. What the portfolio is, in one paragraph

A near-black violet page (`#07060f`) with a faint violet glow bleeding in from
the top-right corner. Content sits on slightly lighter violet-black surfaces
with 1px borders and 14 to 22px corners. One accent family does everything:
lavender `#c9a8ff` for emphasis, `#a17cf5` for links and small accents,
`#8251d4` for filled buttons and the selected pill. Headings are large, tight
and heavy (Outfit 600/700, negative tracking); body text is calm and generous
(1.65 line height English, 1.8 Arabic). Cards are diagonal gradients
(`#151023` to `#09080f`) that lift 4px and light up with a violet glow on
hover. Controls are pills (filters, tags, language toggle) or 12px-radius
rectangles (buttons). Numbers are big lavender figures on small stat tiles. A
pulsing mint dot says "live". The header is translucent and blurred once the
page scrolls. Motion is soft and fast (200 to 300 ms, one easing curve), with
a 700 ms fade-up on first appearance.

## 2. Colour

### 2.1 Dark tokens (primary)

Hex is the CSS value; `Color(...)` is the Flutter literal (alpha first).

| Token | Hex | Flutter | Portfolio var | Use |
|---|---|---|---|---|
| `bg` | `#07060f` | `Color(0xFF07060F)` | `--bg` | page background, `ColorScheme.surface` |
| `bg2` | `#0c0a17` | `Color(0xFF0C0A17)` | `--bg-2` | side rail, alternate bands |
| `surface` | `#120e1f` | `Color(0xFF120E1F)` | `--surface` | stat tiles, pills, plain cards |
| `surface2` | `#191329` | `Color(0xFF191329)` | `--surface-2` | inputs, icon tiles, secret box |
| `surface3` | `#221a38` | `Color(0xFF221A38)` | new | highest container (menus, hovered rows) |
| `ink` | `#f4f1fa` | `Color(0xFFF4F1FA)` | `--ink` | primary text |
| `soft` | `#d6cbe8` | `Color(0xFFD6CBE8)` | `--soft` | secondary text, nav links |
| `muted` | `#aaa6bc` | `Color(0xFFAAA6BC)` | `--muted` | captions, hints, labels |
| `line` | `#262036` | `Color(0xFF262036)` | `--line` | hairlines, dividers |
| `line2` | `#3a2d50` | `Color(0xFF3A2D50)` | `--line-2` | decorative borders (pills, buttons) |
| `outline` | `#74629a` | `Color(0xFF74629A)` | new | borders that identify a control (inputs) |
| `accent` | `#a17cf5` | `Color(0xFFA17CF5)` | `--accent` | links, icons, digits, `ColorScheme.primary` |
| `accent2` | `#c9a8ff` | `Color(0xFFC9A8FF)` | `--accent-2` | eyebrows, stat numbers, focus ring |
| `strong` | `#8251d4` | `Color(0xFF8251D4)` | `--accent-strong` | filled button, selected pill |
| `strongHover` | `#8a59dd` | `Color(0xFF8A59DD)` | `#9766e8` in the portfolio | button hover (see 2.7) |
| `strongPressed` | `#7545cb` | `Color(0xFF7545CB)` | new | button pressed |
| `good` | `#7fe0a8` | `Color(0xFF7FE0A8)` | `--good` | success, "live" dot, strong password |
| `warn` | `#f2c46d` | `Color(0xFFF2C46D)` | browser-bar dot `#f2c46d` | warnings, ambiguous characters |
| `error` | `#f26d6d` | `Color(0xFFF26D6D)` | browser-bar dot `#f26d6d` | errors, symbols in passwords, destructive |

### 2.2 Light tokens (derived)

Same hue family, surfaces tinted lavender-white, text deep violet-black.
Cards are white on a `#faf8ff` page so they lift the same way dark cards do.

| Token | Hex | Flutter | Use |
|---|---|---|---|
| `bg` | `#faf8ff` | `Color(0xFFFAF8FF)` | page, `ColorScheme.surface` |
| `bg2` | `#f3effb` | `Color(0xFFF3EFFB)` | side rail, bands |
| `surface` | `#ffffff` | `Color(0xFFFFFFFF)` | stat tiles, pills, cards |
| `surface2` | `#f5f1fd` | `Color(0xFFF5F1FD)` | inputs, icon tiles, secret box |
| `surface3` | `#ece5f8` | `Color(0xFFECE5F8)` | menus, hovered rows |
| `ink` | `#160f29` | `Color(0xFF160F29)` | primary text |
| `soft` | `#3b3153` | `Color(0xFF3B3153)` | secondary text |
| `muted` | `#5a5370` | `Color(0xFF5A5370)` | captions, hints, labels |
| `line` | `#e5def2` | `Color(0xFFE5DEF2)` | hairlines, dividers |
| `line2` | `#cfc3e6` | `Color(0xFFCFC3E6)` | decorative borders |
| `outline` | `#857a9f` | `Color(0xFF857A9F)` | input borders (3:1) |
| `accent` | `#6a3dc4` | `Color(0xFF6A3DC4)` | links, icons, digits, `ColorScheme.primary` |
| `accent2` | `#55299f` | `Color(0xFF55299F)` | eyebrows, stat numbers |
| `strong` | `#8251d4` | `Color(0xFF8251D4)` | filled button, selected pill (same as dark) |
| `strongHover` | `#7443c8` | `Color(0xFF7443C8)` | button hover (darker, not lighter) |
| `strongPressed` | `#6a38bd` | `Color(0xFF6A38BD)` | button pressed |
| `good` | `#12703f` | `Color(0xFF12703F)` | success |
| `warn` | `#8a5a00` | `Color(0xFF8A5A00)` | warnings, ambiguous characters |
| `error` | `#c0263f` | `Color(0xFFC0263F)` | errors, destructive |

The light theme keeps `strong` identical so a filled button looks the same in
both themes; only the text-weight tokens (`accent`, `accent2`, `good`, `warn`,
`error`) are darkened to clear 4.5:1 on white.

### 2.3 Tinted containers

| Role | Dark bg / fg | Light bg / fg |
|---|---|---|
| primary container (selected tile, nav indicator) | `#251d3c` (accent at 13% over `surface`) / `ink` | `#f0eafa` (strong at 12% over white) / `ink` |
| good container | `#10281c` / `good` | `#dff5e8` / `good` |
| warn container (ambiguous character in a password) | `#33270d` / `warn` | `#fff1d6` / `warn` |
| error container | `#3a1620` / `#ff9aa6` | `#fde7ea` / `#9d1b31` |

### 2.4 Password-strength ramp (score 0 to 4)

Replace the stock `Colors.red ... Colors.green` in `StrengthBar`. The label text
always accompanies the bar, so colour is never the only signal.

| Score | Dark | Light |
|---|---|---|
| 0 | `#f26d6d` | `#c0263f` |
| 1 | `#f59a6b` | `#c4571c` |
| 2 | `#f2c46d` | `#a86b00` |
| 3 | `#b6e07a` | `#5c8a12` |
| 4 | `#7fe0a8` | `#12703f` |

All ten are at least 3:1 against their card surface (non-text contrast, WCAG
1.4.11): dark 6.5 to 12.6, light 4.1 to 6.15 on white and at least 3.7 on
`surface2`.

### 2.5 Surface recipes

| Surface | Dark | Light |
|---|---|---|
| Card | gradient 140deg `#151023` to `#09080f`, border `#2e2340` | gradient 140deg `#ffffff` to `#f6f2fd`, border `#e0d6f0` |
| Card hover (pointer devices) | border `#7a5ba6`, lift 4px, shadow, glow overlay `#b281f322` | border `#b79de6`, lift 4px, shadow |
| Featured card | gradient 130deg `#221437` to `#0b0814` at 70%, border `#4a3368` | gradient 130deg `#f1e8ff` to `#ffffff`, border `#cdb8ee` |
| Dialog / sheet | radial from top-right `#35204d` to `#100a1c` at 65%, border `#684686` | radial `#eadcff` to `#ffffff` at 65%, border `#cdb8ee` |
| Selected row | fill `#a17cf522`, border `#7a5ba6` | fill `#8251d41f`, border `#b79de6` |
| Scrim | `#02010b` at 77% (`#02010bc4`) + blur 8 | `#1a0f33` at 55% + blur 8 |
| Glass header | `#07060fcc` + blur 14, bottom border `line` | `#faf8ffcc` + blur 14, bottom border `line` |
| Ambient glow | `#6a3fd02e` radial, top-right | `#8251d424` radial, top-right |
| Brand tile | gradient 135deg `#8251d4` to `#c9a8ff`, glyph `#0b0814` | identical |

### 2.6 Alpha tokens: CSS to Flutter

CSS puts alpha last (`#rrggbbaa`); Flutter puts it first (`0xAARRGGBB`).

| Name | CSS | Flutter |
|---|---|---|
| nav hover | `#ffffff0d` | `Color(0x0DFFFFFF)` |
| nav selected / selected row | `#a17cf522` | `Color(0x22A17CF5)` |
| ambient glow | `#6a3fd02e` | `Color(0x2E6A3FD0)` |
| glass header | `#07060fcc` | `Color(0xCC07060F)` |
| glass header, open menu | `#07060ff5` | `Color(0xF507060F)` |
| ghost button fill | `#ffffff06` | `Color(0x06FFFFFF)` |
| primary button glow | `#7d43ce40` | `Color(0x407D43CE)` |
| live-dot ring | `#7fe0a822` | `Color(0x227FE0A8)` |
| scrim | `#02010bc4` | `Color(0xC402010B)` |
| card hover glow | `#b281f322` | `Color(0x22B281F3)` |
| tag fill | `#9d74e80f` | `Color(0x0F9D74E8)` |
| top hairline highlight | `#ffffff10` | `Color(0x10FFFFFF)` |
| hero halo | `#6838d855` | `Color(0x556838D8)` |

### 2.7 Contrast (computed)

Body text must be at least 4.5:1; large text (24px, or 18.66px bold) and UI
components and graphics at least 3:1. Where I changed a portfolio value it is
because the portfolio value failed.

**Dark, text on background**

| Text | on `bg` | on `surface` | on `surface2` |
|---|---|---|---|
| `ink` | 18.05 | 16.97 | 16.12 |
| `soft` | 13.02 | 12.24 | 11.63 |
| `muted` | 8.53 | 8.02 | 7.62 |
| `accent` | 6.45 | 6.06 | 5.76 |
| `accent2` | 10.10 | 9.50 | 9.03 |
| `good` | 12.60 | 11.85 | 11.26 |
| `error` | 6.89 | 6.48 | 6.16 |
| `warn` | 12.37 | 11.63 | 11.05 |

Also: `ink` on `surface3` 14.78, `muted` on `surface3` 6.98, `muted` on a
selected row 6.74, white on `strong` 5.15, white on `strongHover` 4.61, white
on `strongPressed` 6.05, `#0b0814` on `accent` 6.34, on `accent2` 9.94,
`onError #1b0508` on `error` 6.70, `onTertiary #1f1500` on `warn` 11.06.

**Light, text on background**

| Text | on `bg` | on `bg2` | on `surface` | on `surface2` |
|---|---|---|---|---|
| `ink` | 17.57 | 16.35 | 18.51 | 16.64 |
| `soft` | 11.39 | 10.60 | 12.00 | 10.79 |
| `muted` | 6.86 | 6.38 | 7.23 | 6.50 |
| `accent` | 6.48 | 6.03 | 6.82 | 6.14 |
| `accent2` | 9.04 | 8.42 | 9.53 | 8.57 |
| `good` | 5.84 | 5.43 | 6.15 | 5.53 |
| `warn` | 5.63 | 5.24 | 5.93 | 5.33 |
| `error` | 5.55 | 5.17 | 5.85 | 5.26 |

Also: white on `strong` 5.15 (same as dark), white on `strongHover` 6.21,
white on `accent` 6.82, `ink` on a selected row 15.74, `muted` on a selected
row 6.14, `accent` on a selected row 5.80, `surface3` pairs: `ink` 15.10,
`muted` 5.89. Containers: `good` on its container 5.38, `warn` 5.31, error
text `#9d1b31` on its container 6.75.

**Non-text**

| Pair | Ratio | Verdict |
|---|---|---|
| dark `outline #74629a` on `bg` / `surface` / `surface2` | 3.80 / 3.57 / 3.39 | passes, use for input borders |
| dark `line2` on `bg` | 1.60 | decorative only, do not use as the only boundary of an input |
| dark `line` on `bg` | 1.29 | decorative hairline |
| light `outline #857a9f` on `bg` / `surface` / `surface2` | 3.77 / 3.98 / 3.58 | passes |
| light `line2` on `bg` | 1.58 | decorative only |
| dark focus ring `accent2` on `bg` / `surface2` | 10.10 / 9.03 | passes |
| light focus ring `accent` on `bg` | 6.48 | passes |
| `strong` fill vs `bg` (dark / light) | 3.91 / 4.89 | selected pill is identifiable without its label colour |

**Where the portfolio fails and what the app does instead**

* Primary button hover `#9766e8` with white text is **3.90:1** (fails 4.5).
  The app lightens only to `#8a59dd` (4.61) in dark and darkens to `#7443c8` in
  light.
* Input outlines at `--line-2` are 1.6:1. Inputs use `outline` (3:1 or better).
* The big project numeral colour `#5d3f8c` on a card is 2.26:1. It is
  decorative in the portfolio. In the app such a numeral may only be a purely
  decorative, semantics-excluded watermark; never put information in it.
* `#9e80be` overlines on a card are 5.56:1 and pass, so the portfolio's
  overline colour can be reused as is.

### 2.8 Material `ColorScheme` mapping

Build `ColorScheme(...)` explicitly. Do not use `fromSeed`: it would rederive
the palette and lose the identity. Set `surfaceTint` to transparent so Material
does not tint elevated surfaces.

| `ColorScheme` | Dark | Light |
|---|---|---|
| `primary` / `onPrimary` | `accent` / `#0b0814` | `accent` / `#ffffff` |
| `primaryContainer` / `onPrimaryContainer` | `strong` / `#ffffff` | `strong` / `#ffffff` |
| `secondary` / `onSecondary` | `accent2` / `#0b0814` | `accent2` / `#ffffff` |
| `secondaryContainer` / `onSecondaryContainer` | `#251d3c` / `ink` | `#f0eafa` / `ink` |
| `tertiary` / `onTertiary` | `warn` / `#1f1500` | `warn` / `#ffffff` |
| `tertiaryContainer` / `onTertiaryContainer` | `#33270d` / `warn` | `#fff1d6` / `warn` |
| `error` / `onError` | `error` / `#1b0508` | `error` / `#ffffff` |
| `errorContainer` / `onErrorContainer` | `#3a1620` / `#ff9aa6` | `#fde7ea` / `#9d1b31` |
| `surface` / `onSurface` / `onSurfaceVariant` | `bg` / `ink` / `muted` | `bg` / `ink` / `muted` |
| `surfaceContainerLowest` | `bg` | `#ffffff` |
| `surfaceContainerLow` | `bg2` | `bg2` |
| `surfaceContainer` | `surface` | `surface` |
| `surfaceContainerHigh` | `surface2` | `surface2` |
| `surfaceContainerHighest` | `surface3` | `surface3` |
| `outline` / `outlineVariant` | `outline` / `line2` | `outline` / `line2` |
| `inverseSurface` / `onInverseSurface` / `inversePrimary` | `ink` / `bg` / `accent` | `ink` / `bg` / `accent` |
| `scrim` | `#02010b` | `#1a0f33` |

Why `tertiary` is amber and not mint: `SecretText` paints ambiguous characters
with `tertiaryContainer` / `onTertiaryContainer`. Amber reads as "look twice";
green reads as "fine". `good` lives in a `ThemeExtension` instead.

Recommended `ThemeExtension` (call it `AppTokens`): `good`, `goodContainer`,
`warn`, `outlineStrong`, `cardGradient`, `featuredGradient`, `dialogGradient`,
`cardBorder`, `cardHoverBorder`, `glow`, `glass`, `selected`, `selectedBorder`,
`shadow`, `buttonGlow`, `strengthRamp`. Components read these; nothing reads a
raw hex.

## 3. Typography

### 3.1 Fonts (bundled, OFL)

| Family name in Flutter | Weights available | Role |
|---|---|---|
| `Outfit` | 400, 500, 600, 700 | English UI; brand wordmark and numerals in every language |
| `IBMPlexSansArabic` | 400, 500, 600, 700 | Arabic UI; fallback for Outfit (it also has Latin) |
| `JetBrainsMono` | 400, 500 | secrets, emails, URLs, codes, in every language |

Details, provenance, hashes and licences: `assets/fonts/README.md`. All files
are static TrueType. Nothing is fetched at run time, and `google_fonts` must
not be added.

Rules that were verified by rendering:

* **Fallback chain.** Outfit has no Arabic. Always give the style
  `fontFamilyFallback`. English styles: `fontFamily: 'Outfit'`,
  `fontFamilyFallback: ['IBMPlexSansArabic']`. Arabic styles:
  `fontFamily: 'IBMPlexSansArabic'`, `fontFamilyFallback: ['Outfit']`. A mixed
  string such as "Vault - خزنة آمنة 123" renders correctly with the English chain.
* **Weights.** Only the weights above exist. `w300` falls to 400; `w800` and
  `w900` fall to 700. Do not rely on synthetic bold.
* **Mono has no ligatures** (removed from the files). `SecretText` should still
  pass `fontFeatures: [FontFeature.disable('calt')]`. It should stop using
  `fontFamily: 'monospace'` and use `JetBrainsMono` with `['monospace']` as the
  fallback, so a password looks the same on all three platforms. In the render,
  `0` carries an inner mark, `O` is a plain oval, `1` has a flag and a base, `l`
  has a curved tail, `I` has serifs and `|` is a bar, so `0O1lI|` is
  unambiguous.
* **Letter spacing on Arabic.** Flutter 3.47 ignores `letterSpacing` on Arabic
  runs (rendered at -0.6, 0, +0.3 and +1.4: identical), as CSS does for cursive
  scripts. Set `letterSpacing: 0` on Arabic styles anyway so the intent is
  explicit and Latin words inside Arabic strings are not tracked.
* **Digits.** Use Western digits (0-9) everywhere, as the portfolio does, also
  in Arabic. `intl`'s plain `ar` locale formats numbers and dates with
  Arabic-Indic digits, so format counts with `toString()` or an `en` number
  format. Passwords, codes and TOTP are always ASCII digits.
* **Tabular figures.** Counters and the TOTP code use
  `fontFeatures: [FontFeature.tabularFigures()]` (Outfit has `tnum`).
* **Glyph coverage.** Both text fonts contain `← → ↑ ↓ ↗ • · — … ×`. Neither
  contains `◆` or `●`: draw bullets and dots as shapes, not text. Outfit and
  IBM Plex have `✓`; JetBrains Mono does not, so do not put a check mark in a
  mono run (use an icon).

### 3.2 Scale

`height` in Flutter is a multiple of the font size, like CSS unitless
line-height. Sizes are for the app, not the landing page: the portfolio's fluid
`clamp()` heading sizes are capped to what fits a phone and a 1180px column.
Portfolio source values are given so the ratios stay traceable.

| Role (Material) | English: Outfit | Arabic: IBM Plex Sans Arabic | Portfolio source |
|---|---|---|---|
| `displayLarge` (lock screen title) | 40 / 700 / ls -1.0 / h 1.10 | 36 / 700 / ls 0 / h 1.35 | hero h1 46-92, 700, -2.5px, 1.02 |
| `headlineLarge` (screen title) | 32 / 600 / ls -0.6 / h 1.20 | 30 / 600 / ls 0 / h 1.40 | h2 32-48, 600, -1px EN / -0.6px AR, 1.15 EN / 1.3 AR |
| `headlineMedium` (section title) | 26 / 600 / ls -0.3 / h 1.25 | 24 / 600 / ls 0 / h 1.45 | h3 21-26, lh 1.45 |
| `titleLarge` (app bar, dialog title) | 22 / 600 / ls -0.2 / h 1.30 | 21 / 600 / ls 0 / h 1.50 | h3 |
| `titleMedium` (list title) | 16 / 600 / ls 0 / h 1.40 | 16 / 600 / ls 0 / h 1.55 | project/cert h3 |
| `titleSmall` (group label) | 14 / 600 / ls 0.1 / h 1.40 | 14 / 600 / ls 0 / h 1.55 | |
| `bodyLarge` (notes, long text) | 16 / 400 / ls 0 / h 1.65 | 16 / 400 / ls 0 / h 1.80 | body 16, 1.65 EN / 1.8 AR |
| `bodyMedium` (default) | 14 / 400 / ls 0 / h 1.55 | 15 / 400 / ls 0 / h 1.75 | |
| `bodySmall` (captions, stat labels) | 13 / 400 / ls 0.1 / h 1.50 | 13 / 400 / ls 0 / h 1.70 | stat label 13, 1.5 |
| `labelLarge` (buttons) | 15 / 600 / ls 0.1 / h 1.20 | 15 / 600 / ls 0 / h 1.30 | button 15, 600 |
| `labelMedium` (pills, chips) | 14 / 500 / ls 0.2 / h 1.20 | 14 / 500 / ls 0 / h 1.35 | chip 14 |
| `labelSmall` (overline, tags) | 11 / 500 / ls +1.4, UPPERCASE / h 1.60 | 12 / 500 / ls 0, not uppercased / h 1.60 | overline 11, +1.4px |
| eyebrow (section kicker) | 14 / 500 / ls +0.3 / accent2 | 14 / 500 / ls 0 / accent2 | `.eyebrow` |
| numeral (stat tile) | Outfit 34 / 600 / h 1.10, tabular | same (always Outfit) | `.stats dd` |
| `secret` (mono, password display) | JetBrainsMono 18 / 400 / ls 0.8 / h 1.50 | same, forced LTR | |
| `secretSmall` (mono, email/URL subtitle) | JetBrainsMono 12.5 / 400 / ls 0 / h 1.50 | same, forced LTR | |

Notes:

* Arabic body is one point larger than English at 14 (15) and 12 minimum
  elsewhere, because the Arabic glyphs read smaller at the same size. Never go
  below 12 in either language.
* Arabic needs more line height, but not 1.8 inside controls: keep 1.3 to 1.55
  there so buttons and list rows do not grow.
* Only the brand wordmark (Outfit 600, 15, +1 tracking, uppercase), the stat
  numerals and the `EN` toggle use Outfit in Arabic mode; the `ع` toggle uses
  IBM Plex Sans Arabic.
* Emphasis inside a heading: the portfolio colours a word with `accent`
  (`em` / `.accent`) or a lavender gradient. In Flutter use a `TextSpan` with
  `color: accent`, or `ShaderMask` with the gradient `accent2` to `strong` for
  hero text only.
* Honour the system text scale up to 2.0 (section 11). Do not give text
  containers a fixed height.

### 3.3 Wiring (one builder per language)

```dart
TextStyle _base(bool ar) => TextStyle(
      fontFamily: ar ? 'IBMPlexSansArabic' : 'Outfit',
      fontFamilyFallback: ar ? const ['Outfit'] : const ['IBMPlexSansArabic'],
    );

const secretStyle = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontFamilyFallback: ['monospace'],
  fontFeatures: [FontFeature.disable('calt')],
);
```

Build the `TextTheme` and `ThemeData` from the active locale (`Locale('ar')` or
not), so a language switch swaps the whole scale.

## 4. Spacing, radii, sizing

**Spacing scale (dp):** 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.

| Use | Value |
|---|---|
| page gutter | 16 on phones (< 640), 20 elsewhere (portfolio `100% - 40px`) |
| gap between list tiles | 10 |
| gap between stat tiles / grid cells | 12 |
| gap between a section title and its content | 10 to 16 |
| gap between sections | 24 to 32 (portfolio uses 64+ between landing sections; do not copy that) |
| card padding | 16 to 20 (portfolio 28x30 desktop, 22x20 phone) |
| dialog padding | 24 |
| button padding | 22 horizontal, 13 vertical, minimum height 48 |
| input content padding | 16 horizontal, 14 vertical |
| filter pill padding | 12 to 20 horizontal, 9 vertical |

**Radii (dp):**

| Element | Radius | Portfolio |
|---|---|---|
| tag, small chip | 6 | 6 |
| skill tag | 8 | 8 |
| brand tile | 0.3 x size (10 at 34) | 10 |
| button, input, secret box, menu | 12 | 12 |
| stat tile | 14 | 14 |
| site icon tile (44) | 12 | |
| card, list tile | 16 | 16 (`--radius`) |
| dialog, bottom sheet (top corners), featured card | 22 | 22 |
| pill (filter, language toggle, kicker, snackbar action chip) | `StadiumBorder` | 30 |
| status dot, avatar, FAB | circle | 50% |

**Sizes:** minimum interactive target 48x48 (see 11); brand tile 34 in the bar,
38 in the rail, 72 on the lock screen; site icon tile 44 in lists, 64 in the
detail header; status dot 8 with a 4 ring; header height 56 on phones, 72 on
desktop (portfolio `--header-h`).

## 5. Elevation and glow

The look is borders plus gradients plus a few large soft shadows, not Material
elevation. Set `elevation: 0` on cards, app bars, dialogs and menus and draw
these instead.

Flutter's `BoxShadow.blurRadius` is blurrier than the same CSS value (CSS
standard deviation is r/2; Flutter's is about 0.577r + 0.5). Multiply the CSS
blur by 0.87 to match the portfolio.

| Recipe | CSS | Flutter (blur already x0.87) |
|---|---|---|
| Primary button glow | `0 8px 30px #7d43ce40` | `BoxShadow(color: 0x407D43CE, offset: (0, 8), blurRadius: 26)` |
| Card hover | `0 20px 50px #0007` | `(0, 20), blurRadius: 43, color: 0x77000000` |
| Dialog / sheet | `0 25px 100px #000a` | `(0, 25), blurRadius: 87, color: 0xAA000000` |
| Floating chip, toast | `0 10px 30px #0007` | `(0, 10), blurRadius: 26, color: 0x77000000` |
| Back-to-top / FAB | `0 6px 25px #0007` | `(0, 6), blurRadius: 22, color: 0x77000000` |
| Accent hover glow | `0 0 40px #8f4fc640` | `(0, 0), blurRadius: 35, color: 0x408F4FC6` |
| Live-dot ring | `0 0 0 4px #7fe0a822` | `spreadRadius: 4, blurRadius: 0, color: 0x227FE0A8` |
| Top hairline highlight | `inset 0 1px 0 #ffffff10` | no inset shadows in Flutter: 1px top border in `0x10FFFFFF` on an inner `DecoratedBox`, or a 1px gradient strip |

Light theme shadows are violet-tinted and lighter: base colour `#3a1f7a`, about
18% (`0x2E3A1F7A`), same offsets. The primary button glow becomes `0x388251D4`.
Do not put a drop shadow on a selected row in light: border plus tint is
crisper (the render showed a smudge).

Do not use `Material.elevation` shadows or `Card(elevation:)` for the glow;
they produce the grey two-layer Material shadow, not a violet halo.

## 6. Gradients

| Name | CSS | Flutter |
|---|---|---|
| Brand tile | `linear-gradient(135deg,#8251d4,#c9a8ff)` | `LinearGradient(begin: topLeft, end: bottomRight, [strong, accent2])` (square, so exact) |
| Card | `linear-gradient(140deg,#151023,#09080f)` | `cssLinear(140, [cardA, cardB])` |
| Featured card | `linear-gradient(130deg,#221437,#0b0814 70%)` | `cssLinear(130, [..], [0, .7])` |
| Dialog | `radial-gradient(ellipse at 100% 0%,#35204d,#100a1c 65%)` | `RadialGradient(center: Alignment(1, -1), radius: 1.3, colors: [a, b], stops: [0, .65])` |
| Page progress bar | `linear-gradient(90deg,#7645d0,#dda9ff)` | 3px `LinearGradient([0xFF7645D0, 0xFFDDA9FF])`; use for sync/unlock progress |
| Gradient word | `linear-gradient(90deg,#c9a8ff,#8251d4)` + text clip | `ShaderMask` with that gradient, hero text only |
| Stat gradient number | `linear-gradient(90deg,#d9c2ff,#9b6cf0)` | optional, `ShaderMask` |
| Ambient glow | `radial-gradient(closest-side,#6a3fd02e,transparent)` in a 70vw x 70vh box at top `-20vh`, right `-20vw` | `Positioned` box with `RadialGradient(colors: [glow, glow.withAlpha(0)], radius: .5)`; size it square-ish (about 520 on phones, 900x700 on desktop) so the circle matches the portfolio's ellipse |

CSS angle helper (validated in the specimen, `deg` is the CSS angle):

```dart
LinearGradient cssLinear(double deg, List<Color> colors, [List<double>? stops]) {
  final r = deg * math.pi / 180;
  final end = Alignment(math.sin(r), -math.cos(r));
  return LinearGradient(begin: -end, end: end, colors: colors, stops: stops);
}
```

Put the ambient glow once, behind the `Scaffold` body (a `Stack` above the
background colour), not per screen. In RTL it stays in the physical top-right
corner, as in the portfolio.

## 7. Motion

One curve: `--ease: cubic-bezier(.2,.8,.2,1)` is `Cubic(0.2, 0.8, 0.2, 1.0)`.
Where the portfolio leaves the timing function at its default (colour and
border transitions) use `Curves.ease`.

| What | Duration | Curve | Detail |
|---|---|---|---|
| hover and focus colour, border | 200 ms | ease | pills, buttons, links |
| card hover | 250 ms | ease | lift 4px, border, glow; **pointer devices only** |
| button hover | 200 ms | ease | lift 2px (desktop only) |
| header background on scroll | 300 ms | ease | transparent to glass |
| menu / popover | 200 ms | ease | fade + 8px slide |
| dialog / sheet enter | 300 ms | `--ease` | from opacity 0, y +16, scale .98 |
| page transition | 300 ms | `--ease` | fade + 16px slide up; use one `PageTransitionsTheme` for all platforms |
| first appearance of a list or grid | 700 ms | `--ease` | fade + 20px up; stagger 60 to 80 ms, at most 8 items, only on first build of a screen |
| strength / progress fill | 500 ms | `--ease` | portfolio's 1.2 s bar grow is too slow for feedback |
| live dot pulse | 2.4 s loop | ease | ring 4px to 8px and fading; only while sync is actually live |
| decorative float (chips) | 6 s loop | ease-in-out | landing-page only, skip in the app |

Reduced motion: when `MediaQuery.disableAnimationsOf(context)` is true,
durations become `Duration.zero`, the pulse stops on its resting frame, no
stagger, no slide. Colour changes stay (they are state, not motion).

Never animate anything that shows or hides a secret in a way that leaves the
plaintext on screen during the transition longer than the state change itself.

## 8. Components

Each pattern says what to style, in `ThemeData` terms first.

### 8.1 App background and header

* `scaffoldBackgroundColor: bg`, the ambient glow behind it (section 6).
* **Header** (`AppBar` or custom): transparent at rest, glass once content
  scrolls under it: `ClipRect` + `BackdropFilter(ImageFilter.blur(sigmaX: 14,
  sigmaY: 14))` + `glass` colour + 1px `line` bottom border. CSS `blur(14px)`
  is a standard deviation of 14, so the same number works in Flutter. Height 56
  on phones, 72 on desktop. `elevation: 0`, `scrolledUnderElevation: 0`,
  `surfaceTintColor: transparent`, `centerTitle: false`.
* Left (start) side: brand tile 34 + wordmark. End side: language toggle pill
  and actions. The toggle shows the *other* language: `ع` when in English,
  `EN` when in Arabic, in a `StadiumBorder` with `line2` border and `surface`
  fill.

### 8.2 Buttons

| Kind | Spec |
|---|---|
| Primary (`FilledButton`) | fill `strong`, white text, hover `strongHover`, pressed `strongPressed`, radius 12, padding 22x13, min height 48, label `labelLarge`; wrap in a `DecoratedBox` with the primary glow shadow (section 5). Not elevated. |
| Ghost (`OutlinedButton`) | fill `0x06FFFFFF` (dark) or transparent (light), 1px `line2` border (`accent` on hover), text `ink`, same radius and padding |
| Text (`TextButton`) | no fill, text `accent2` dark / `accent` light, radius 12, hover fill `0x0DFFFFFF` / `0x0F8251D4` |
| Destructive | same as primary but fill `error`, text `onError`; confirm in a dialog |
| Icon (`IconButton`) | 48x48 target, 22 icon, `soft`, hover fill as text button, radius 12 |
| FAB / back-to-top | circle 46 to 56, fill `strong` (portfolio `#6e39a9`), white icon, FAB shadow |
| Disabled | 38% opacity content, no glow |

Hover lift (translateY -2) only on `PointerDeviceKind.mouse`.

### 8.3 Pills (filters, language toggle, status)

`ChoiceChip` / `FilterChip` with `StadiumBorder`, fill `surface`, 1px `line2`
border, text `soft` 14/500, padding 12x9, hover border `accent`. **Selected:**
fill `strong`, border `#a879ee`, text white, no check mark. Keep a result
count line under filters in `bodySmall` (`muted`), as the portfolio does
("Showing 4 of 4").

### 8.4 Cards

Gradient surface (section 2.5), 1px border, radius 16, padding 16 to 20. On
hover (mouse only): border to `cardHoverBorder`, lift 4px, shadow, and a radial
glow `0x22B281F3` of radius about 320 that follows the pointer (position it
with `MouseRegion.onHover`; fixed top-centre is acceptable). A featured card
uses the featured gradient and spans the full row.

Do not nest cards in cards. A section is a title plus a column of tiles, not a
card containing cards.

### 8.5 Stat tile (KPI)

`surface` fill, 1px `line` border, radius 14, padding 16. Number: Outfit 34 /
600 / h 1.1, `accent2`, tabular figures. Label below: `bodySmall` `muted`,
height 1.5. **Size to content, never to a fixed aspect ratio**: the first
specimen at 2:1 overflowed (34px numeral plus label needs about 60px plus 32px
padding). Use `IntrinsicHeight` + `Row` + `Expanded`, or a `Wrap`, not
`GridView(childAspectRatio:)`. Two per row on phones, three or four on desktop.

Use for: total logins, weak, reused, old, breached, 2FA coverage (dashboard).
Delta line (`+12.4%` style) in `good` 11/400 is optional.

### 8.6 List tile with site icon

The vault list row and the quick-search result.

* Container: card gradient, radius 16, border `cardBorder`, padding
  `EdgeInsetsDirectional(14, 12, 6, 12)`, 10 between rows.
* Leading: 44x44 icon tile, radius 12, fill `surface2`, 1px `line2` border. The
  site icon (`SiteIcon`) fills it with 8 padding and radius 8. Fallback: the
  first letter of the title in Outfit 18/600 `accent2`. Never leave it empty.
* Title: `titleMedium` (Latin names stay LTR, aligned to the start edge).
* Subtitle: the username/email in `secretSmall` (mono, `muted`, forced LTR,
  one line, ellipsis).
* Trailing: favourite star (`accent2`, 22) if set, then a copy `IconButton`.
  Long-press or secondary click opens the actions menu.
* **Selected** (two-pane desktop, and the row being edited): fill `selected`,
  border `selectedBorder`, no shadow in light.
* Hover (desktop): border `cardHoverBorder` and a trailing action cluster fades
  in; the actions must also be reachable by keyboard and long-press, never
  hover-only.

### 8.7 Inputs

`InputDecorationTheme`: `filled: true`, `fillColor: surface2`, radius 12,
border `outline` 1px, focused border `accent2` (dark) / `accent` (light) 2px,
error border `error` 1px with an error text line and icon (not colour alone),
content padding 16x14, label `bodyMedium` `muted` floating to `bodySmall`
`accent2`, hint `muted`. Disabled: 38% content.

* Search field: leading search icon, hint "Search the vault" (localised), clear
  button when non-empty, desktop `Ctrl+F` focuses it.
* Latin-only fields (email, URL, password, TOTP secret, recovery key):
  `textDirection: TextDirection.ltr`, aligned to the UI's start edge
  (`TextAlign.right` in an Arabic layout, `left` in English), mono family for
  password and recovery key.
* Password field: reveal toggle (icon button, 48x48) with a tooltip and
  `Semantics` hint; revealing switches to the mono style.

### 8.8 Secret display

Used for the password on the detail screen, the generator output and the
recovery key. Box: `surface2`, 1px `line2`, radius 12, padding 16. Text:
`secret` style, forced `TextDirection.ltr`, selectable. Character classes:
digits `accent`, symbols `error`, ambiguous characters `warn` on the warn
container with weight 500, letters `ink`. Below it the strength bar (5
segments, 6px tall, radius 3, 4px gaps, `strengthRamp`) and a text label in the
ramp colour. In an Arabic layout the box stays full width and the LTR text
aligns to the start (right) edge, matching the portfolio's RTL metrics.

### 8.9 Status dot and kicker pill

A pill with `surface` fill, `line2` border and an 8px `good` dot with a 4px
ring (`0x227FE0A8`) pulsing, followed by `bodyMedium` `soft` text such as
"Encrypted on this device" or "Synced 2 min ago". Offline or error states swap
the dot colour (`muted`, `error`) and stop the pulse. The dot is decorative:
the text carries the meaning.

### 8.10 Dialog

`AlertDialog` / `Dialog`: radial gradient surface (section 2.5), 1px border,
radius 22, padding 24, max width 560 (680 for rich content), dialog shadow,
scrim with blur 8. Title `titleLarge`, body `bodyMedium` `soft`, actions at
the end: ghost cancel then primary confirm (start-to-end order mirrors in
RTL). A destructive confirm uses the destructive button and names what is
lost. Enter animation per section 7. Escape and the back gesture close it.

### 8.11 Bottom sheet

Phones and any width below 600: modal bottom sheet, radius 22 on the top
corners, dialog surface, 4x36 drag handle in `line2`, max width 640 centred on
tablets, safe-area bottom padding, scrim as above. At 600 and wider, present
the same content as a centred dialog (section 9). Keyboard-aware: content
scrolls above the keyboard.

### 8.12 Toast / snackbar

Floating `SnackBar`: `surface3` fill, `line2` border, radius 12, text `ink`,
action `accent2` / `accent`, margin 16, `behavior: floating`, 4 s, also
announced to screen readers. Confirmations for copy actions never contain the
copied secret ("Password copied", not the password), and say when the clipboard
will be cleared.

### 8.13 Empty state

Centred column, max width 360: a 72px rounded tile with the brand gradient at
16% opacity and a lavender outline icon (or the brand tile), 24 gap,
`headlineMedium`-sized title (22 to 26), `bodyMedium` `muted` explanation, 20
gap, one primary button and optionally a ghost. A soft `glow` radial behind the
tile. One empty state each for: empty vault, no search results (offer to clear
the filter), no breach findings (a calm positive state with `good`).

### 8.14 Other controls

* **Switch / checkbox / radio:** on = `strong` track with a white thumb (`good`
  is not used for toggles), off = `surface3` track with an `outline` border.
  Focus ring 2px `accent2`.
* **Tabs / segmented control:** pill indicator in `selected` fill, text `ink`;
  unselected `soft`.
* **Navigation bar** (compact): `bg2` fill with a top `line` border, pill
  indicator `selected`, icon `accent2` when selected and `muted` otherwise,
  labels always shown.
* **Navigation rail** (expanded): 76 wide, `bg2`, 1px `line` end border, brand
  tile at the top, 48x48 items with 14 radius and `selected` fill when active.
* **Progress:** `LinearProgressIndicator` 3px with the progress-bar gradient for
  unlock and sync; `CircularProgressIndicator` stroke 3 in `accent2`.
* **Tooltips:** `surface3` fill, `ink` text, radius 8, 12px text. Not the only
  carrier of a label.
* **Dividers:** 1px `line`.
* **Tag** (read-only metadata): radius 6, 1px `#4a355e` (dark) border, fill
  `0x0F9D74E8`, text `#cbb5ea` 13/400, padding 12x3.

### 8.15 Lock and unlock screen

The first impression, so it carries the brand: centred column on the ambient
glow, a 72px brand tile, the wordmark, `displayLarge`-sized one-line title, a
mono-free master-password field (max width 420), the primary `Unlock` button
with glow, ghost buttons for biometrics and "Forgot password?". The hint text
and errors are plain, generic sentences (section 12).

## 9. Layout and desktop

| Width | Class | Layout |
|---|---|---|
| < 600 | compact | single column, bottom navigation bar, bottom sheets, 16 gutter |
| 600 to 899 | medium | single column centred (max 640), navigation rail optional, sheets become dialogs, 20 gutter |
| >= 900 | expanded | **two panes: list (fixed 360 to 420) and detail (flexible)**, 76px navigation rail, 20 gutter |
| >= 1200 | large | same, navigation rail may extend to 240 with labels |

* Maximum content width **1180**, centred (the portfolio's `--wrap`), for
  full-page content such as the dashboard, settings and the generator.
* Detail pane content max width 640, started at the pane's start edge, not
  centred (specimen). Forms 480. Dialogs 560 (680 rich).
* The selected list row stays highlighted while the detail shows it; with no
  selection show the empty state in the detail pane.
* Keyboard (desktop): `Ctrl+F` search, up/down moves the selection, `Enter`
  opens/copies, `Esc` clears search or closes the sheet, `Ctrl+N` new entry, `Tab`
  order follows reading order (mirrors in RTL). The existing `Ctrl+V` paste
  handler must keep working.
* Pointer: every clickable thing has a hover state and a pointer cursor;
  scrollbars visible on desktop and styled (thumb `line2`, hover `outline`).
* Minimum window size on Windows about 420x640; content must not overflow at
  that size or at 200% text scale.
* Do not use a landing-page hero, large decorative tilted mock-ups or marquee
  strips in the app. Those belong to the portfolio.

## 10. Right-to-left and bidirectional text

The app supports Arabic and English with real RTL. The whole layout mirrors;
the following rules keep it correct.

1. Use only directional-agnostic layout: `EdgeInsetsDirectional`,
   `AlignmentDirectional`, `BorderDirectional`, `PositionedDirectional`,
   leading/trailing, `start`/`end`. No `left`/`right` except for the ambient
   glow and for aligning forced-LTR text (below).
2. **Secrets and technical strings are always LTR monospace**: passwords,
   emails, URLs, usernames, TOTP codes, recovery keys, IP addresses. Wrap in
   `Directionality(textDirection: TextDirection.ltr)` (as `SecretText` does).
   Keep the wrapper's *alignment* in the outer (RTL) layout, so the value sits at
   the start edge (right in Arabic), like the portfolio's
   `[dir=rtl] .metrics dd{direction:ltr;text-align:right}`. Render-verified.
3. Latin words inside an Arabic sentence (site names, product names): isolate
   them with `U+2066 ... U+2069` (LRI ... PDI), or build a `Text.rich` with
   separate spans, so punctuation does not jump to the wrong side.
4. Mirror icons that imply direction: back, forward, chevrons, "send", progress
   that fills along the reading direction, list indents, swipe actions. Do not
   mirror: check marks, clocks, the brand tile, media controls, signal strength,
   copy/paste, keys/locks, plus/minus.
5. The strength bar and the page progress bar fill from the start edge (right
   in Arabic). Sliders (password length) also mirror.
6. Number formatting: Western digits (section 3.1). Dates: spell the month name
   in the active language; use the same ISO-like order in both.
7. Text alignment: `TextAlign.start` (never `left`). Centre stays centre.
8. Truncation: Arabic ellipsis goes at the end of the line (the left in RTL);
   do not truncate secrets, show them wrapped or scrollable.
9. Fonts: Arabic styles use IBM Plex Sans Arabic; give every Arabic text at
   least `h 1.3` so diacritics and tall letters are not clipped, and never use
   all-caps or tracking to create hierarchy (Arabic has no case); use weight
   and colour instead.
10. Test every new screen in both languages and both themes (section 14).

## 11. Accessibility checklist

Per screen, before it is done:

- [ ] Text contrast is at least 4.5:1 (3:1 for large text); only use the
      token pairs in 2.7. No `muted` text smaller than 13 on `surface3`.
- [ ] Borders that identify a control (inputs, switches off-state) use
      `outline` (3:1); focus rings are 2px `accent2` (dark) or `accent` (light)
      with a 2px offset and are visible on every control, not only buttons.
- [ ] Information is not conveyed by colour alone: strength bar has a text
      label, errors have an icon and text, ambiguous characters are also
      bolder with a background, the live dot has a text neighbour.
- [ ] Every interactive element is at least 48x48 dp (44 pt on iOS, 40 px on
      desktop as an absolute floor) with at least 8dp between targets.
- [ ] Every icon-only button has a `tooltip` and a semantics label in the
      active language. **No tooltip or semantics label may contain a secret.**
- [ ] The screen is fully usable with the keyboard: logical focus order that
      follows reading order and mirrors in RTL, `Esc` closes overlays, no focus
      traps, visible focus.
- [ ] Text scales to 200% without clipping or horizontal scroll: no fixed
      heights around text, `Flexible`/`Expanded` in rows, `Wrap` for chips and
      stat tiles, and the layout tested at textScaler 2.0 on a 360 dp width.
- [ ] Reduced motion: `disableAnimations` honoured (section 7); nothing
      essential depends on animation or hover.
- [ ] Screen readers: headings are marked (`Semantics(header: true)`), list
      rows read as "title, username" (not the password), password fields are
      `obscured`, a reveal toggle announces its state, copy/clear actions
      announce through a live region (`SemanticsService.sendAnnouncement`).
- [ ] The dark/light/system choice is respected, and high-contrast mode
      (`MediaQuery.highContrastOf(context)`) uses `outline` instead of `line` and `line2`.
- [ ] Dialogs trap focus, name themselves (`title` is the semantics label) and
      return focus to the control that opened them.
- [ ] Error messages are generic and actionable and never echo input
      (section 12). Form errors link to the field.
- [ ] Both languages and both themes have been rendered and looked at.

## 12. Security rules that constrain the UI

From `docs/SECURITY.md`; a visual change must not weaken any of them.

* **Screen capture protection stays** (Android `FLAG_SECURE`, Windows
  `WDA_EXCLUDEFROMCAPTURE`, iOS blur and hide while captured). Do not add any
  "share screenshot", "export image" or "save as image" feature. Do not
  replace native window or activity code while restyling.
* **No secret outside the secret widgets**: not in a `Hero` tag, route name,
  `Key`, `Semantics.label`, `tooltip`, `debugLabel`, `print`, exception message
  or toast text. Titles may appear; passwords, recovery keys, TOTP codes and
  notes may not.
* **Secrets are masked by default** and revealed on demand, with an automatic
  re-mask; the masked placeholder keeps a fixed length so it does not leak the
  real one (existing `SecretText` clamps to 8 to 16 dots).
* **No network for presentation.** No remote fonts, images, Lottie files,
  gradients-as-images or analytics. Site icons keep to the opt-in, same-domain,
  HTTPS-only rules of item 17.
* **No plaintext in temp files** and no screenshots committed: renders for this
  work are written to the scratchpad only.
* **Unlock failure and reset copy is generic.** "Wrong password or recovery
  key" style messages; no hint about which part was wrong, no email
  enumeration wording.
* **Clipboard UX** must say what happens and when it is cleared; never show the
  copied value in the confirmation.

## 13. Portfolio CSS to Flutter

| Portfolio CSS | Flutter |
|---|---|
| `:root` colour variables | `AppTokens` `ThemeExtension` + explicit `ColorScheme` (2.8) |
| `body{background:var(--bg)}` | `ThemeData.scaffoldBackgroundColor`, `ColorScheme.surface` |
| `body::before` radial glow | `Positioned` `RadialGradient` behind the scaffold (6) |
| `--font-ar`, `--font-en`, `html[lang=en]` | locale-driven `TextTheme` + `fontFamilyFallback` (3.3) |
| `body{line-height:1.8}` / `1.65` | `TextStyle.height` per language (3.2) |
| `h1,h2` `letter-spacing:-2.5px / -1px` | `TextStyle.letterSpacing` (English only; Arabic 0) |
| `.eyebrow` | `labelMedium` + `accent2` |
| `em` / `.accent` colour | `TextSpan(style: TextStyle(color: accent))` |
| `.hero-role em` gradient text | `ShaderMask` + `LinearGradient` |
| `--radius:16px` | `BorderRadius.circular(16)` on `CardThemeData` / tiles |
| pill `border-radius:30px` | `StadiumBorder` |
| `.button` radius 12, padding 13x22 | `FilledButton.styleFrom(shape: RoundedRectangleBorder(12), padding: ...)` |
| `.button.primary` + `box-shadow` | `FilledButtonThemeData` + `DecoratedBox(boxShadow)` |
| `.button.primary:hover{background; translateY(-2px)}` | `WidgetStateProperty` on `hovered`; `AnimatedSlide` with `MouseRegion`, mouse only |
| `.button.ghost` | `OutlinedButtonThemeData` (`side`, `backgroundColor`) |
| `.chip` / `[aria-pressed=true]` | `ChoiceChip` + `ChipThemeData` (`selectedColor`, `side`, `shape`) |
| `.tag` | small `Container` radius 6, border, fill |
| `.project` card gradient + border | `BoxDecoration(gradient, border, borderRadius)` |
| `.project:hover` lift, border, shadow | `MouseRegion` + `AnimatedContainer` (translate via `Matrix4`/`Transform`) |
| `.project::after` radial hover glow | `Stack` child `RadialGradient` that fades in on hover |
| `.stats div` (KPI) | stat tile (8.5), `IntrinsicHeight` |
| `.dot` + `@keyframes pulse` | `AnimatedBuilder` on a 2.4 s `AnimationController`, `BoxShadow.spreadRadius` 4 to 8 |
| `.site-header.scrolled` + `backdrop-filter` | `ClipRect` + `BackdropFilter` + translucent colour |
| `.brand-mark` | brand tile (8.1), first letter of the brand constant |
| `.lang-toggle` | pill button, `StadiumBorder` |
| `.progress` bar | 3px gradient `LinearProgressIndicator` / custom paint |
| `.project-dialog` | `Dialog` with radial gradient, radius 22 |
| `.project-dialog::backdrop` | `barrierColor` + `BackdropFilter(blur 8)` in the route |
| `@keyframes pop` | `ScaleTransition` + `FadeTransition` + slide, 300 ms `Cubic(.2,.8,.2,1)` |
| `.js .reveal` | staggered `FadeTransition` + `SlideTransition`, 700 ms |
| `:focus-visible{outline:2px solid accent-2}` | `WidgetState.focused` in `ButtonStyle.side` / `overlayColor`, `InputDecorationTheme.focusedBorder` (2px), and a 2px `accent2` ring on custom tiles via `Focus` |
| `.skip` link | not needed; use semantics and focus order |
| `.back-top` | FAB / `FloatingActionButton.small` with the FAB shadow |
| `@media(max-width:980px)` | `LayoutBuilder` breakpoints 600 / 900 (9) |
| `@media(max-width:640px)` | compact: 16 gutter, single column |
| `@media(prefers-reduced-motion)` | `MediaQuery.disableAnimationsOf` |
| `[dir=rtl]` rules | `Directionality` + directional widgets (10) |
| `.wrap{width:min(1180px,100% - 40px)}` | `ConstrainedBox(maxWidth: 1180)` + 20 padding |
| `.toolstrip`, `.marquee`, `.dash` mock-up | not used in the app |

## 14. Render and look (how to check visual work)

Visual work is checked by rendering to PNG and looking at it. Write PNGs to
the scratchpad only, never into the repo, and never commit them. Things that
cost time the first time:

* Fonts declared in `pubspec.yaml` are **not** registered in `flutter_test`.
  Register each family explicitly, all weights, before pumping:
  `final l = FontLoader('Outfit')..addFont(rootBundle.load('assets/fonts/outfit/Outfit-Regular.ttf')); ... await l.load();`
  (inside `tester.runAsync`). Do this for `Outfit`, `IBMPlexSansArabic` and
  `JetBrainsMono`. Without it everything renders as solid boxes.
* Icons render as boxes unless you also load the Material icon font:
  `FontLoader('MaterialIcons')` from
  `<flutter>/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`.
* `flutter_test` turns blurred shadows into hard blocks. Set
  `debugDisableShadows = false;` (from `package:flutter/painting.dart`) before
  pumping and set it back to `true` at the end of the test, or the test fails
  Flutter's invariant check.
* Use `tester.view.physicalSize` with `devicePixelRatio = 1`, wrap the screen in
  a `RepaintBoundary`, call `boundary.toImage(pixelRatio: 2)` inside
  `tester.runAsync`, write the PNG bytes, then open it with the image reader.
* A `RenderFlex overflowed` exception fails the test: that is useful, it catches
  text-scale and Arabic overflow. Render at `textScaler: TextScaler.linear(2)`
  too.
* Render four combinations: dark/light x English/Arabic (`Locale('ar')` with
  `Directionality(textDirection: rtl)`), at 390x844 and 1280x800.

Specimen results behind this brief (not committed): the dark/light and
English/Arabic phone screens and the two desktop two-pane views all rendered
without overflow with the tokens, scale and recipes above.

## 15. Where this departs from the portfolio

| Change | Reason |
|---|---|
| Button hover colour | portfolio value fails AA with white text (3.90:1) |
| New `outline` token for inputs | portfolio's border colour is 1.6:1; inputs need 3:1 |
| Error and warning colours | the portfolio has none; derived from its two other browser-bar dots |
| Tertiary is amber, success is an extension | `SecretText` highlights ambiguous characters with the tertiary container |
| Light theme | portfolio is dark only; derived and contrast-checked |
| Mono font and ligature removal | the portfolio shows no secrets; ligatures would alter passwords |
| Hover lift, tilt, glow follow only on mouse | there is no hover on phones; nothing may depend on it |
| No landing-page structures in the app | marquee, tilted dashboard and section spacing do not suit a utility |
| Arabic: tighter line heights inside controls, +1 size at body size | 1.8 line height inflates buttons and rows |

Open points for the owner: the app name (and therefore the brand tile letter
and wordmark), whether to ship the light theme on day one or behind the
existing theme setting only, and whether to add Windows-only extras
(Mica-style translucency) later.
