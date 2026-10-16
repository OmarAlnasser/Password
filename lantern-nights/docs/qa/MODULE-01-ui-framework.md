# QA — Module 1: Theme + UI framework

Open the place in Studio with Rojo connected and press **Play**. Open the UI Kit with
**F2** or the purple **UI Kit** button on the right edge.

## Boot
- [ ] Output shows no errors or warnings from `Client`, `Server`, `[Client]` or `[Server]`.
- [ ] The default Roblox health bar and backpack hotbar are hidden.
- [ ] `PlayerGui` contains `LN_HUD`, `LN_ModalBackdrop`, `LN_Menus`, `LN_Toasts`, `LN_Overlay`, `LN_Loading`.
- [ ] `ReplicatedStorage.Remotes` exists (created by BootService).

## Window
- [ ] The UI Kit pops open (slight overshoot) in ~0.28 s, and the backdrop fades in.
- [ ] Close it with the red ✕, by tapping the dimmed backdrop, and with **B** on a gamepad.
      Each one animates out quickly (~0.2 s) and plays a close swoosh.
- [ ] With the window open, clicking the backdrop doesn't reach the world behind it.
- [ ] Nothing overlaps Roblox's top bar (check the window header and the toasts).

## Buttons
- [ ] Hover (mouse): the button grows to ~1.05 with a soft tick. Press: it shrinks to ~0.95
      and the face sinks onto the darker lip. Release: click sound, slightly different pitch each time.
- [ ] Touch (Device Emulator): no stuck hover state after tapping.
- [ ] **Locked (tap me):** shakes, plays the error sound and shows an "Not enough Embers" error toast.
      **Toggle lock** enables it, and it then behaves normally.
- [ ] The Backpack icon button shows a red "3" badge. Its tooltip appears after hovering ~0.35 s,
      after a ~0.45 s long-press on touch (and that long-press does **not** click it), and on
      gamepad selection.
- [ ] Gamepad: the D-pad moves a gold selection ring between buttons, and **A** presses visibly.

## Vitals & numbers
- [ ] **Hit −18:** the bars spring down, and a pale ghost segment lingers ~0.45 s, then drains.
- [ ] Health ≤ 25%: the fill turns deep red and the outline pulses. Warmth ≤ 25%: it turns frost blue.
- [ ] **Heal:** the bars spring back up and the ghost follows immediately.
- [ ] **+25 / +25,000:** the number rolls up and pops, and the compact label reads e.g. `26.3K`.

## Toasts
- [ ] Each kind slides in from the right, with its own colour **and** icon.
- [ ] Spam 6 quickly: no more than 3 are visible at once, and the oldest leave first.
- [ ] Tapping a toast dismisses it, and toasts auto-dismiss after ~3 s.

## Accessibility
- [ ] **UI scale** slider: the whole UI rescales live. Drag the track, and use − / + to step.
- [ ] **Reduce motion ON:** no bounces, shakes, slides or pulses. Windows and toasts appear
      instantly, and everything still works.
- [ ] **SFX volume 0%:** UI sounds go silent.
- [ ] The Rarity cards are tellable apart in greyscale by their pip count.

## Devices (Test → Device Emulator)
Check the UI Kit header line (`Device · Input · ×scale`) on each device:
- [ ] iPhone SE (small phone, landscape): text is still ≥ 18 px, nothing is clipped, the window fits.
- [ ] iPhone 14 Pro: the window and toasts avoid the notch / Dynamic Island.
- [ ] iPad: the scale is ~1.15 and the window is capped, not stretched.
- [ ] 1080p desktop: the scale is ~1.3 and the window is capped at 920×640 pt.
- [ ] Switch between mouse and gamepad mid-session: the input mode label updates and hover
      behaviour follows.

## Performance
- [ ] With the UI Kit open, **View → Script Performance**: the Client script is near 0% when idle
      (the only per-frame work is the low-health pulse, and only while a bar is low).
