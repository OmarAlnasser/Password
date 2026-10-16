# Architecture

## Folder structure

```
lantern-nights/
├─ default.project.json      Rojo: maps src/ into the DataModel
├─ wally.toml                packages (Fusion 0.3)
├─ rokit.toml                pinned toolchain (rojo, wally, stylua, selene)
├─ stylua.toml / selene.toml / .luaurc
├─ assets/icons/             custom icon set: svg/ (source), png/ (upload these), contact-sheet.png
├─ tools/icons/build.mjs     regenerates svg + png from code
├─ docs/
└─ src/
   ├─ shared/                → ReplicatedStorage.Shared
   │  ├─ Theme/              design tokens (init), Palette, Icons
   │  ├─ Config/             data-driven content (Audio now; items/enemies/events later)
   │  └─ Util/               Loader (lifecycle), Format (numbers/time)
   ├─ server/                → ServerScriptService.Server (Script)
   │  ├─ init.server.luau    boots Services/
   │  └─ Services/           one ModuleScript per server system
   └─ client/                → StarterPlayerScripts.Client (LocalScript)
      ├─ init.client.luau    boots Controllers/
      ├─ Controllers/        one ModuleScript per client system (UIController…)
      └─ UI/
         ├─ Types            Scope / UsedAs / LayoutProps aliases
         ├─ Preferences      reactive player settings (scale, motion, volumes…)
         ├─ Responsive       device class, input mode, UI scale
         ├─ Motion           springs/tweens/shake/pop that respect Reduce motion
         ├─ UISound          interface SFX with pitch jitter + rate limit
         ├─ Layers           ScreenGui stack + scaled roots, safe-area aware
         ├─ WindowManager    one-window-at-a-time modal stack + backdrop
         ├─ Toasts           notification stack
         ├─ Tooltip          hover / long-press / gamepad-select tooltips
         ├─ Components/      Text, Icon, Button, Card, Window, ProgressBar,
         │                   CountUp, Toggle, Slider, Decor (corner/stroke/padding/list)
         └─ Dev/UIKit        Studio-only living style guide (F2)
```

Wally installs `Packages/` (git-ignored) into `ReplicatedStorage.Packages`.

## Conventions

- **`--!strict` everywhere.** Components are plain functions,
  `Component(scope: Types.Scope, props: Component.Props): Instance`, with exported `Props` types.
- **Tokens, never literals.** Colours, sizes, radii, strokes, durations and easings come from
  `Shared.Theme`. If a value you need is missing, add a token; don't hard-code it.
- **One motion path.** Animations go through `UI/Motion`, so the Reduce motion setting works
  everywhere.
- **Lifecycle.** Services and controllers export optional `Priority`, `Init()` (sync, no
  yielding) and `Start()` (spawned after every `Init` has run). Errors are isolated per module.
- **Scopes own cleanup.** Anything a component creates (connections, threads) is registered on
  its Fusion scope with `table.insert(scope, cleanupFn)`.
- **Layers, not ad-hoc ScreenGuis.** Mount into `Layers.get("HUD" | "Menus" | …)`. Each root is
  already scaled and inside the safe area.
- **Accessibility built in.** Hit targets ≥ 44 pt, touch text ≥ 18 px, colour is never the only
  cue (icons, pips, ON/OFF words), and every hover affordance has a long-press and a gamepad path.

## Why Fusion springs, not Stylesheets, for interaction states

Roblox StyleSheets and Fusion would both write the same properties (`BackgroundColor3`,
scale, transparency) on the same instances, and the two systems would fight. The UI therefore
has one source of truth: Theme tokens, read reactively by Fusion components. Hover, press and
disabled transitions are springs in `Button`, which the Reduce motion setting can turn off
in one place. Hand-built Studio UI can still read the same tokens through `Shared.Theme`.
