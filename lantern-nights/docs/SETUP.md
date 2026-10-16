# Studio + Rojo setup

## 1. Toolchain (once per machine)

1. Install **Rokit**: https://github.com/rojo-rbx/rokit
2. In `lantern-nights/`, run:
   ```sh
   rokit install            # rojo, wally, wally-package-types, stylua, selene (pinned in rokit.toml)
   wally install            # downloads Fusion into Packages/
   rojo sourcemap -o sourcemap.json
   wally-package-types --sourcemap sourcemap.json Packages/   # re-exports Fusion's types for strict mode
   ```
3. **VS Code extensions:** *Luau Language Server* (JohnnyMorganz), *StyLua*, *Selene*, *Rojo*.
   `.vscode/settings.json` already points luau-lsp at `default.project.json`.
4. Selene's Roblox standard library: `selene generate-roblox-std` (once).

## 2. Connect Studio

1. Install the Rojo Studio plugin: `rojo plugin install` (or from the Creator Store).
2. Start the sync server: `rojo serve`
3. In Studio, open a new **Baseplate**, then **Plugins → Rojo → Connect**.
   Everything under `src/` appears in the Explorer and updates live as you save.
4. **Game Settings → Security:** turn on *Enable Studio Access to API Services* (needed from
   Module 3, DataStores).

To build a place file without Studio: `rojo build -o LanternNights.rbxlx`.

## 3. Icons

The icons ship as PNGs in `assets/icons/png/` (white fill + dark outline, 256×256).

1. Studio → **Window → Asset Manager → Bulk Import** → select every PNG in `assets/icons/png/`.
2. Right-click each imported image → **Copy Asset ID**, then paste it into
   `src/shared/Theme/Icons.luau` → `AssetIds` (e.g. `Health = "rbxassetid://1234567890"`).
3. Until an ID is filled in, the UI draws a text glyph instead, so nothing breaks.

To change or add an icon, edit `tools/icons/build.mjs` and run `node tools/icons/build.mjs`
(needs Node and `npm i -g playwright`). It rewrites `svg/`, `png/` and `contact-sheet.png`.

## 4. Sounds

`src/shared/Config/Audio.luau` defaults to sounds built into the Roblox client, so the UI is
audible from the first play-test. Swap in your own uploads (`rbxassetid://…`) for the final
mix.

## 5. First play-test

Press **F5** (Play). In Studio you'll see a purple **UI Kit** button on the right edge (or
press **F2**). It opens a gallery of every component wired to the real settings. See
`docs/qa/MODULE-01-ui-framework.md` for what to check.

To hide the UI Kit in Studio, set a `DevUIKit` attribute on ReplicatedStorage to `false`.
It never mounts in live servers.

## 6. Formatting and lint

```sh
stylua src            # format
stylua --check src    # CI-style check
selene src            # lint
```
