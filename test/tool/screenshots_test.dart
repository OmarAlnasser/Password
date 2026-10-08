/// Visual gallery of the shared theme and widgets. Skipped by default (see
/// `dart_test.yaml`); run it to look at the primitives:
///
/// ```sh
/// SHOTS_DIR=/tmp/shots flutter test --run-skipped -t screenshots test/tool/screenshots_test.dart
/// ```
@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisn/services/password_generator.dart';
import 'package:hisn/ui/theme/tokens.dart';
import 'package:hisn/ui/theme/typography.dart';
import 'package:hisn/ui/widgets/brand_mark.dart';
import 'package:hisn/ui/widgets/empty_state.dart';
import 'package:hisn/ui/widgets/glass_bar.dart';
import 'package:hisn/ui/widgets/max_width_body.dart';
import 'package:hisn/ui/widgets/pill_chip.dart';
import 'package:hisn/ui/widgets/primary_button.dart';
import 'package:hisn/ui/widgets/pulse_dot.dart';
import 'package:hisn/ui/widgets/secret_text.dart';
import 'package:hisn/ui/widgets/section_header.dart';
import 'package:hisn/ui/widgets/site_avatar.dart';
import 'package:hisn/ui/widgets/stat_tile.dart';
import 'package:hisn/ui/widgets/strength_bar.dart';
import 'package:hisn/ui/widgets/surface_card.dart';

import 'screenshot_harness.dart';

void main() {
  testWidgets('gallery: phone, dark and light, English and Arabic', (
    tester,
  ) async {
    await pumpScreenshots(
      tester,
      const _Gallery(),
      'gallery',
      sizes: [ShotSize.custom('phone', 390, 2560)],
    );
  });

  testWidgets('gallery: phone at 200% text', (tester) async {
    await pumpScreenshots(
      tester,
      const _Gallery(),
      'gallery-x2',
      sizes: [ShotSize.custom('phone', 360, 3800)],
      textScale: 2,
      themes: [Brightness.dark],
    );
  });

  testWidgets('desktop: rail, list and detail built from the primitives', (
    tester,
  ) async {
    await pumpScreenshots(
      tester,
      const _DesktopSample(),
      'desktop',
      sizes: [ShotSize.desktop],
    );
  });

  testWidgets('overlays: dialog, sheet, snack bar, menu, tooltip', (
    tester,
  ) async {
    for (final (name, tap) in [
      ('dialog', 'Open dialog'),
      ('sheet', 'Open sheet'),
      ('snack', 'Show snack bar'),
      ('menu', 'Open menu'),
    ]) {
      for (final b in [Brightness.dark, Brightness.light]) {
        await pumpScreenshot(
          tester,
          const _Overlays(),
          'overlay-$name-${b.name}',
          brightness: b,
          afterPump: (t) async {
            await t.tap(find.text(tap));
            await t.pump(const Duration(milliseconds: 600));
          },
        );
      }
    }
  });
}

String _s(BuildContext context, String en, String ar) =>
    context.isArabic ? ar : en;

// -----------------------------------------------------------------------------

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    Widget gap([double h = 24]) => SizedBox(height: h);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassBar(
        title: const BrandLockup(),
        actions: [
          Container(
            margin: const EdgeInsetsDirectional.only(end: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: ShapeDecoration(
              color: t.surface,
              shape: StadiumBorder(side: BorderSide(color: t.line2)),
            ),
            child: Text(
              context.isArabic ? 'EN' : 'ع',
              style: TextStyle(
                fontFamily: context.isArabic ? AppFonts.en : AppFonts.ar,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: t.ink,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: MaxWidthBody.insets(
          context,
          base: EdgeInsets.fromLTRB(
            0,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 20,
            0,
            40,
          ),
        ),
        children: [
          SectionHeader(
            eyebrow: _s(context, 'Your vault', 'خزنتك'),
            title: _s(context, 'Passwords, protected', 'كلماتك محمية'),
            size: SectionHeaderSize.display,
            accentDot: true,
          ),
          gap(18),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusPill(
              label: _s(
                context,
                'Encrypted on this device',
                'مشفّرة على جهازك',
              ),
            ),
          ),
          gap(22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PillChip(
                label: _s(context, 'All', 'الكل'),
                selected: true,
                onSelected: (_) {},
              ),
              PillChip(
                label: _s(context, 'Favorites', 'المفضلة'),
                onSelected: (_) {},
              ),
              PillChip(label: _s(context, 'Weak', 'ضعيفة'), onSelected: (_) {}),
              PillChip(
                label: _s(context, 'Old', 'قديمة'),
                icon: Icons.history_rounded,
                onSelected: (_) {},
              ),
              PillChip(label: _s(context, 'Disabled', 'معطّلة')),
            ],
          ),
          gap(22),
          StatGrid(
            tiles: [
              StatTile(
                value: '128',
                label: _s(context, 'All logins', 'كل الحسابات'),
              ),
              StatTile(
                value: '6',
                label: _s(context, 'Weak', 'ضعيفة'),
                valueColor: t.error,
              ),
              StatTile(
                value: '3',
                label: _s(context, 'Reused', 'مكررة'),
                footnote: '+1',
              ),
              StatTile(
                value: '11',
                label: _s(context, 'Old', 'قديمة'),
                onTap: () {},
              ),
            ],
          ),
          gap(28),
          SectionHeader(
            title: _s(context, 'Logins', 'الحسابات'),
            size: SectionHeaderSize.group,
            trailing: TextButton(
              onPressed: () {},
              child: Text(_s(context, 'See all', 'عرض الكل')),
            ),
          ),
          gap(8),
          const _Row(
            'github.com',
            'omar.dev@mail.com',
            'G',
            selected: true,
            fav: true,
          ),
          const _Row('accounts.google.com', 'omar@gmail.com', 'G'),
          const _Row('netflix.com', 'family-plan@mail.com', 'N'),
          gap(14),
          SurfaceCard(
            featured: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s(context, 'Featured card', 'بطاقة مميزة'),
                  style: tt.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  _s(
                    context,
                    'The brighter gradient is for one thing per screen.',
                    'التدرّج الأفتح لعنصر واحد في كل شاشة.',
                  ),
                  style: tt.bodyMedium!.copyWith(color: t.soft),
                ),
              ],
            ),
          ),
          gap(28),
          TextField(
            obscureText: true,
            controller: TextEditingController(text: 'hunter2hunter2'),
            decoration: InputDecoration(
              labelText: _s(context, 'Master password', 'كلمة المرور الرئيسية'),
              suffixIcon: const Icon(Icons.visibility_outlined),
            ),
          ),
          gap(14),
          TextField(
            decoration: InputDecoration(
              hintText: _s(context, 'Search the vault', 'ابحث في الخزنة'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          gap(14),
          TextField(
            decoration: InputDecoration(
              labelText: _s(context, 'Email', 'البريد'),
              errorText: _s(
                context,
                'Enter an email address.',
                'أدخل عنوان بريد إلكتروني.',
              ),
            ),
          ),
          gap(14),
          TextField(
            enabled: false,
            decoration: InputDecoration(
              labelText: _s(context, 'Disabled', 'معطّل'),
            ),
          ),
          gap(24),
          SecretBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SecretText(r'Tr0ub4dor&3-Il1O|xQ', style: AppText.secret),
                const SizedBox(height: 12),
                StrengthBar(result: const StrengthResult(4, 'centuries', null)),
              ],
            ),
          ),
          gap(12),
          for (final s in [0, 1, 2, 3])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StrengthBar(result: StrengthResult(s, '3 days', null)),
            ),
          gap(12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  icon: const Icon(Icons.lock_open_rounded),
                  onPressed: () {},
                  child: Text(_s(context, 'Unlock', 'فتح')),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {},
                child: Text(_s(context, 'Cancel', 'إلغاء')),
              ),
            ],
          ),
          gap(14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              PrimaryButton(
                onPressed: () {},
                destructive: true,
                child: Text(_s(context, 'Erase vault', 'مسح الخزنة')),
              ),
              const PrimaryButton(onPressed: null, child: Text('Disabled')),
              TextButton(
                onPressed: () {},
                child: Text(
                  _s(context, 'Forgot password?', 'نسيت كلمة المرور؟'),
                ),
              ),
              FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
              IconButton(
                tooltip: 'Copy',
                onPressed: () {},
                icon: const Icon(Icons.copy_rounded),
              ),
              FloatingActionButton.small(
                onPressed: () {},
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          gap(24),
          RadioGroup<int>(
            groupValue: 1,
            onChanged: (_) {},
            child: Row(
              children: [
                Switch(value: true, onChanged: (_) {}),
                Switch(value: false, onChanged: (_) {}),
                Checkbox(value: true, onChanged: (_) {}),
                Checkbox(value: false, onChanged: (_) {}),
                const Radio<int>(value: 1),
                const Radio<int>(value: 2),
              ],
            ),
          ),
          gap(8),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(_s(context, 'System', 'النظام')),
              ),
              ButtonSegment(
                value: 1,
                label: Text(_s(context, 'Light', 'فاتح')),
              ),
              ButtonSegment(value: 2, label: Text(_s(context, 'Dark', 'داكن'))),
            ],
            selected: const {2},
            onSelectionChanged: (_) {},
          ),
          gap(8),
          Slider(value: 0.6, onChanged: (_) {}),
          gap(16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BrandMark(size: 34),
              BrandMark(size: 34, glyph: BrandGlyph.letter),
              BrandMark(size: 72, glow: true),
              PulseDot(),
              PulseDot(active: false),
            ],
          ),
          gap(8),
          SizedBox(
            height: 330,
            child: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: _s(context, 'Your vault is empty', 'خزنتك فارغة'),
              message: _s(
                context,
                'Add your first login. It is encrypted on this device.',
                'أضف أول حساب. يُشفَّر على هذا الجهاز.',
              ),
              action: PrimaryButton(
                onPressed: () {},
                icon: const Icon(Icons.add_rounded),
                child: Text(_s(context, 'Add login', 'إضافة حساب')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
    this.name,
    this.user,
    this.letter, {
    this.selected = false,
    this.fav = false,
  });

  final String name;
  final String user;
  final String letter;
  final bool selected;
  final bool fav;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.tileGap),
      child: SurfaceCard(
        selected: selected,
        hoverLift: 0,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
        onTap: () {},
        child: Row(
          children: [
            SiteAvatar(title: letter, selected: selected),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LtrText(name, style: tt.titleMedium),
                  LtrText(user),
                ],
              ),
            ),
            if (fav) Icon(Icons.star_rounded, color: t.accent2, size: 22),
            IconButton(
              tooltip: 'Copy',
              onPressed: () {},
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _DesktopSample extends StatelessWidget {
  const _DesktopSample();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: 0,
            labelType: NavigationRailLabelType.none,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: BrandMark(size: 38),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.lock_outline_rounded),
                label: Text('Vault'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.star_border_rounded),
                label: Text('Favorites'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.shield_outlined),
                label: Text('Security'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                label: Text('Settings'),
              ),
            ],
          ),
          VerticalDivider(width: 1, color: t.line),
          SizedBox(
            width: 400,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: _s(context, 'Logins', 'الحسابات'),
                    size: SectionHeaderSize.section,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: InputDecoration(
                      hintText: _s(
                        context,
                        'Search the vault',
                        'ابحث في الخزنة',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PillChip(
                        label: _s(context, 'All', 'الكل'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      PillChip(
                        label: _s(context, 'Favorites', 'المفضلة'),
                        onSelected: (_) {},
                      ),
                      PillChip(
                        label: _s(context, 'Weak', 'ضعيفة'),
                        onSelected: (_) {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Row(
                    'github.com',
                    'omar.dev@mail.com',
                    'G',
                    selected: true,
                    fav: true,
                  ),
                  const _Row('accounts.google.com', 'omar@gmail.com', 'G'),
                  const _Row('netflix.com', 'family-plan@mail.com', 'N'),
                  const _Row('x.com', 'omar_dev', 'X'),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: t.line),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppLayout.form),
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SiteAvatar(title: 'G', size: 64),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'github.com',
                                style: tt.headlineLarge,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const SecretBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SecretText(
                              r'Tr0ub4dor&3-Il1O|xQ',
                              style: AppText.secret,
                            ),
                            SizedBox(height: 12),
                            StrengthBar(
                              result: StrengthResult(4, 'centuries', null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      StatGrid(
                        columns: 3,
                        tiles: [
                          StatTile(
                            value: '128',
                            label: _s(context, 'All logins', 'كل الحسابات'),
                          ),
                          StatTile(
                            value: '6',
                            label: _s(context, 'Weak', 'ضعيفة'),
                          ),
                          StatTile(
                            value: '3',
                            label: _s(context, 'Reused', 'مكررة'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          PrimaryButton(
                            onPressed: () {},
                            icon: const Icon(Icons.copy_rounded),
                            child: Text(
                              _s(context, 'Copy password', 'نسخ كلمة المرور'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () {},
                            child: Text(_s(context, 'Edit', 'تعديل')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _Overlays extends StatelessWidget {
  const _Overlays();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Overlays')),
      body: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SurfaceCard(child: Text('Some content behind the scrim')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Save this password?'),
                        content: const Text(
                          'It is encrypted on this device before it is stored '
                          'and never leaves it in readable form.',
                        ),
                        actions: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Create'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Open dialog'),
                  ),
                  OutlinedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (c) => Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save this login?',
                              style: Theme.of(c).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            const ListTile(
                              leading: Icon(Icons.copy_rounded),
                              title: Text('Copy password'),
                            ),
                            const ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit'),
                              selected: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('Open sheet'),
                  ),
                  OutlinedButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Password copied. The clipboard clears in 30 s.',
                        ),
                        action: SnackBarAction(label: 'Undo', onPressed: () {}),
                      ),
                    ),
                    child: const Text('Show snack bar'),
                  ),
                  PopupMenuButton<int>(
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 1, child: Text('Edit')),
                      PopupMenuItem(value: 2, child: Text('Copy username')),
                      PopupMenuItem(value: 3, child: Text('Delete')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Open menu'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
