# Visual Polish in Pro Valorant/FPS Music Edits (velocity edits, montage shorts)

Scope note: Searched 2024–2026 tutorial and support material. Tutorials from creators tend to be YouTube or TikTok videos, which the search and fetch tools can't read. The citable text sources are mostly vendor documentation (Adobe, CapCut, SteelSeries, Medal), general After Effects (AE) tutorials, and one Valorant-specific AE blog from 2022. Many genre conventions (CC per section, ACE staging, never reusing a clip) appear in no written source I could reach. Those are labelled Inferences and come from general practice. They are not cited facts. Two fetches failed: the SteelSeries support article returned HTTP 403, and develop2.insights.gg could not be resolved in this network sandbox.

## 1. Color grading per section (intro / verse / drop / ACE ending), looks, and beat-switched CC

### Takeaway
I found no written source that documents per-section CC for Valorant edits. The building blocks are documented: a teal/orange grade from color wheels, an S-curve, Hue-vs-Sat/Hue-vs-Hue curves, and HSL Secondary isolation. Flashes are a white solid at 20–40% opacity, keyframed on and off. CapCut has "Style > Velocity" presets (Flash, Blur Shake, Rainbow) that switch the look per clip.

### Cited Findings
- Teal/orange recipe in Lumetri: push the shadows wheel toward teal and the midtones/highlights wheels toward orange. Add an RGB S-curve for "instant filmic contrast". — [Freevisuals: Master Lumetri Color](https://www.freevisuals.net/post/master-lumetri-color-for-premiere-pro-cinematic-looks); [Storyblocks: color grading Premiere Pro](https://www.storyblocks.com/resources/tutorials/color-grading-premiere-pro)
- To strengthen the look, raise teal saturation with Hue vs Sat and turn yellows toward orange with Hue vs Hue. — [Storyblocks](https://www.storyblocks.com/resources/tutorials/color-grading-premiere-pro); [Adobe: Hue and Saturation curves](https://helpx.adobe.com/premiere/desktop/correct-color/add-color-effects/correct-color-using-hue-and-saturation-curves.html)
- HSL Secondary: pick a color with the eyedropper to isolate it, then denoise/blur the key so it blends. One tutorial uses it to make every color pop except skin, and to desaturate greens slightly. — [Adobe: HSL secondary controls](https://helpx.adobe.com/cz/premiere-pro/using/hsl-secondary-controls.html); [Freevisuals](https://www.freevisuals.net/post/master-lumetri-color-for-premiere-pro-cinematic-looks)
- Lumetri processes top-down. Sections after Curves (Color Wheels, HSL Secondary, Vignette) aren't included when Curves samples color. — [Adobe: Hue and Saturation curves](https://helpx.adobe.com/premiere/desktop/correct-color/add-color-effects/correct-color-using-hue-and-saturation-curves.html)
- If a LUT/look is applied, lower its intensity to about 50–70% for natural results. — [Freevisuals](https://www.freevisuals.net/post/master-lumetri-color-for-premiere-pro-cinematic-looks)
- AE has built-in CC effects (CC Color Offset, CC Toner, CC Color Neutralizer, CC Kernel, Auto Color/Contrast) that are usable per layer. — [Adobe: Color Correction effects](https://helpx.adobe.com/after-effects/using/color-correction-effects.html)
- Lightweight color/white flash: a solid at about 20–40% opacity, keyframed to appear and disappear quickly. — [AEJuice / search summary of flash method](https://aejuice.com/blog/how-to-add-a-vibration-shake-in-after-effects)
- CapCut path for per-clip looks: Edit > Style > Velocity presets, including "Flash", "Blur Shake", "Fade Blur", "Retro Zoom" and "Rainbow" (some paid). — [CapCut: how to do velocity](https://www.capcut.com/resource/how-to-do-velocity-on-capcut); [Shotkit: velocity CapCut](https://shotkit.com/velocity-capcut/)
- Kasane Teto's signature colors are dark pink/red hair and eyes. That's the likely reason Teto-song edits lean pink/magenta. I found no source that documents a "PayPal" Teto edit trend or grade. — [Know Your Meme: Kasane Teto](https://knowyourmeme.com/memes/kasane-teto)

### Inferences
- A workable section spec built from these blocks, as a recommendation rather than documented pro practice:
  - Intro: low saturation or near-B&W, crushed blacks, a slight vignette.
  - Verse: a moderate grade (teal/orange or the song's palette), saturation +10–20.
  - Drop: a full-saturation grade change exactly on the drop frame, a 1–3 frame white/color flash (solid at 20–40%, or 100% for a hard flash), and optional glow (AE Glow or Deep Glow, threshold about 60–70%).
  - ACE ending: the strongest grade, then a short B&W or desaturated freeze on the final kill.
- For a pink Teto look: in Lumetri Creative or Color Wheels, push highlights/midtones to magenta (around 300–330°). Use Hue vs Hue to swing Valorant's reds/oranges (Reyna/Phoenix VFX, the red enemy outline) toward pink. Boost Vibrance and add glow. Enemy outline color is a player setting, so editors should know which outline color they recorded with.
- Beat-switched CC: cut the clip, or put an adjustment layer on the beat marker, and change the grade only on that adjustment layer. This keeps every switch on a beat frame. Mark the beats with AE's double-L waveform and markers (cited in section 3).

### Gaps
- No Valorant-specific written source gives Lumetri numbers, LUT names or preset packs used by top velocity editors. That material is in YouTube/TikTok videos the tools couldn't read.
- The "Teto PayPal" trend and its typical palette are unverified.

## 2. ACE / clutch highlighting ("oooh" moment staging)

### Takeaway
Written sources describe a sequence: brief slow motion before the action, then shake, then flash, then a beat drop, with an optional freeze frame right after the shake. The Boris FX article gives concrete shake values. Valorant-specific ACE banner and kill-feed zoom staging appears in no reachable written source.

### Cited Findings
- Boris FX describes the impact pattern: "a screen flash or maybe some slow motion before the action, followed by a beat drop or a peak within a song". It also suggests "a static frame right after the camera shake occurs… on the action moment within a gaming clip", and warns this can look disruptive. — [Boris FX: shake effect AE](https://borisfx.com/blog/shake-effect-after-effects-tutorial/)
- Shake values (Sapphire S_Shake):
  - Amplitude 6 on the impact frame, falling to 0 about 20 frames later.
  - Frequency 15, with motion blur on.
  - X Rand Amp 100, Y Rand Amp 150, Tilt Rand Amp 5.
  - Easy Ease, then shape the curve in the Graph Editor.
  - Source: [Boris FX](https://borisfx.com/blog/shake-effect-after-effects-tutorial/)
- Native Transform-keyframe shake: offset Position (example value about 550) and Rotation about −3. Space the opposing keyframes 2–3 frames apart; closer spacing gives a harsher shake. — [Boris FX](https://borisfx.com/blog/shake-effect-after-effects-tutorial/)
- A keyframed vibration shake with motion blur suits "impacts, glitches, explosions, or dramatic moments". — [AEJuice: vibration shake](https://aejuice.com/blog/how-to-add-a-vibration-shake-in-after-effects)
- Valorant AE workflow: time-remap (Ctrl+Alt+T) with Pixel Motion frame blending, and keyframes on action points (first shot, reload, end) aligned to beat markers. The speed graph rises at the start, flattens in the middle and rises at the end. A straight/zero line freezes the clip. Record at 60 fps or more for smooth slow motion. — [SBK Edits: Valorant montage tutorial](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)

### Inferences
- Recommended ACE staging spec:
  1. Build-up: during the song's riser, ramp speed down toward 20–40%, with zoom-in creeping from 100→110%.
  2. On each kill, make a hard speed-up and cut on beat, adding a 2–4 frame micro-shake.
  3. Final (5th) kill: 1–3 impact frames (white or inverted/high-contrast flash), then a heavy shake (amp 6 decaying over about 20 frames, per Boris FX), then a 0.5–1 s freeze or near-0% speed hold. Optionally drop the freeze to B&W.
  4. Hit the "ACE" banner moment with a punch-zoom (scale 100→120–130% over 3–5 frames) or a crop-zoom onto the kill feed.
  5. Sync the vocal "ooh"/drop to the freeze. Audio should land on the final kill frame.
- Kill-feed zoom: keyframe scale/position on a duplicated layer masked to the top-right kill-feed region. Valorant's kill feed sits top-right by default.

### Gaps
- No written source documents Valorant ACE banner timing or "ooh" sync conventions. These are inferred.

## 3. Transitions (whip pan, zoom, flash, fade, frame-blend, shake, "fade clip")

### Takeaway
CapCut exposes velocity curves (Montage, Hero, Bullet, Jump Cut, Flash In, Flash Out) and Style presets (Flash, Blur Shake, Fade Blur, Retro Zoom). The AE route is time-remap plus Pixel Motion, Motion Tile with mirrored edges (needed for zoom/whip transitions so edges don't go black), and shake/flash keyframes. No source gives a written rule for when to use each transition.

### Cited Findings
- CapCut Speed > Curve presets: Montage, Hero, Bullet, Jump Cut, Flash In, Flash Out. Custom > Edit opens a point graph: raise a point to speed up, lower it to slow down. — [CapCut: velocity](https://www.capcut.com/resource/how-to-do-velocity-on-capcut); [Shotkit](https://shotkit.com/velocity-capcut/)
- One guide's manual velocity workflow: apply a flash-in curve to each clip, then add motion blur and shake per beat. "Most velocity edits also feature blurring and flash effects." — [Shotkit](https://shotkit.com/velocity-capcut/); [FlexClip: velocity on CapCut](https://flexclip.com/learn/how-to-make-a-velocity-edit-on-capcut.html)
- Motion Tile with Mirror Edges on and output size about 250 lets scale/position transitions run without exposing black borders. — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)
- Beat marking in AE: press LL to show the waveform and add markers (numpad *). — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html); [SpotlightFX lyric video](https://spotlightfx.com/blog/how-to-make-a-lyric-video-in-after-effects-5-steps)
- Leave handles: keep enough footage at each clip's start and end for transitions. — [Fiverr editor listing (low authority)](https://fiverr.com/valofx/edit-clean-valorant-montage-with-beat-sync)
- Commercial shake/RGB-flash transition packs are widely sold, which indicates heavy use of shake and flash transitions in this genre. — [Videohive shake transitions](https://videohive.net/item/shake-transitions-pack-dynamic-impact-camera-shake-effects-for-after-effects/60753861); [Uppbeat camera shake transitions](https://uppbeat.io/motion-graphics/asset/camera-shake-transitions-14291)

### Inferences (usage rules, recommended)
- Hard cut plus flash: the default on strong beats/drops.
- Zoom-in/out (with directional blur and Motion Tile): energy rises between same-energy clips. Use zoom-in going into a drop.
- Whip pan: lateral motion between clips where the crosshair is already moving horizontally. Match the direction of the flick.
- Shake transition: kills and snare hits.
- Fade-to-black: intro open and final outro only.
- Frame-blend/Pixel Motion: on slow-mo ramps, not as a cut.
- "Fade clip" (clean opacity/blur fade-in of a clip): calm intro or verse sections, giving contrast before the drop.
- Keep one transition family per section, and save the most aggressive ones for the drop and the ACE.

### Gaps
- I found no authoritative written guide that defines the "fade clip" style or prescribes transitions per section.

## 4. Clip ordering (no back-cutting, intensity ordering)

### Takeaway
Written sources only cover mechanics (drag to reorder, trim dead time). I found no reachable source for the "never cut back to an earlier clip" rule or for best-clip-at-drop ordering. Treat both as genre convention.

### Cited Findings
- Trim clips to the key moments, because viewers lose interest when little is happening. Split a clip to move part of it elsewhere. — [SteelSeries: How to make gaming montages using Moments](https://steelseries.com/blog/how-make-gaming-montages-using-moments-453)
- Medal montage editor: drag clips to reorder them. Trim first when only a short moment is needed. — [Medal: How to create a montage](https://support.medal.tv/support/solutions/articles/48001185258-how-to-create-a-montage); [Medal: gaming clips for edits](https://medal.tv/learn/gaming-clips-for-edits)
- Remove pauses inside a clip by collapsing time-remap keyframes. — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)

### Inferences
- Forward-only rule: once a clip has played, don't return to it. Cutting back reads as repetition and breaks the escalation story. Splitting one clip across a transition is fine only if time moves forward.
- Order by intensity. Open with a clean, readable 1–2 kill clip as the hook (first 1–2 s on TikTok). Verses get multi-kills. The drop gets the flashiest mechanical clip (flick or Operator/Sheriff one-taps). The ACE/clutch goes last as the climax. If the short is under 15 s, it can be all ACE.

### Gaps
- No primary source (pro editor interview, Reddit thread) was reachable to confirm these conventions.

## 5. Watermarks / recorder overlays (SteelSeries Moments, Outplayed, Medal)

### Takeaway
The cleanest fix happens before editing. SteelSeries GG can turn the Moments overlay/tag off in settings. Medal never watermarks local clips, only uploads, and watermark-free downloads need Premium. In post, the standard options are crop-and-scale (simplest for corner badges), Content-Aware Fill in AE, or a tracked blur/mask.

### Cited Findings
- SteelSeries GG: Settings > Moments > Overlays and Notifications > uncheck "Moment Overlay" to remove the Moments tag from clips. Taken from the support article title "How to enable/disable Moments tag on my clips". The page returned HTTP 403, so the steps come from the search snippet. — [SteelSeries support article](https://support.steelseries.com/hc/en-us/articles/43442485371917-How-to-enable-disable-Moments-tag-on-my-clips)
- Medal: the watermark corner is selectable from a drop-down. Path: Settings > Recorder > Watermarks, or Settings > Advanced > Watermark (the docs are inconsistent). Only Premium subscribers can download clips without watermarks. "We will never apply a watermark to your local clips, only uploaded clips." — [Medal: how to enable watermarks](https://support.medal.tv/support/solutions/articles/48001170040-how-to-enable-watermarks); [Medal Author Watermarks FAQ](https://support.medal.tv/support/solutions/articles/48000959998-author-watermarks-faq); [Medal Premium](https://medal.tv/premium)
- AE Content-Aware Fill: mask the region, track the mask if it moves, set the mask to Subtract, then Window > Content-Aware Fill > Generate Fill Layer. — [Adobe: Content-Aware Fill](https://helpx.adobe.com/after-effects/using/content-aware-fill.html); [Adobe Learn: remove unwanted element](https://www.adobe.com/learn/after-effects/web/remove-unwanted-element?learnIn=1)
- Premiere has no native content-aware fill. For branded corner clips, people "tend to crop and zoom" or increase scale if the resolution loss is acceptable. — [Adobe Community: hide/mask visible date top-left](https://community.adobe.com/t5/premiere-pro-discussions/hide-mask-a-visible-date-top-left-on-a-video/m-p/14971171); [Adobe Community: remove logo text](https://community.adobe.com/t5/premiere-pro-discussions/remove-background-logo-text-in-premiere-pro-cc/td-p/12809556)

### Inferences
- Crop-and-scale math for a 1920×1080 source: a corner badge about 8% of the frame from the edge needs scale of about 110–115%. A 9:16 vertical crop (608×1080 centered on the crosshair) already discards the outer horizontal 68%, so corner badges are usually cut out automatically. Check the top and bottom corners only.
- For a static badge in Valorant's flat UI areas, a feathered mask with Gaussian blur or a patch from a nearby frame works. Content-Aware Fill is best when the badge sits over moving 3D scenery.
- Re-export or re-record from the source without the overlay at 60 fps whenever possible. It's lossless compared with any post fix.
- Only remove branding from your own clips. Stripping another creator's watermark may breach platform ToS. Medal's watermark is explicitly for creator attribution.

### Gaps
- Exact on-screen positions and sizes of the SteelSeries "MOMENTS"/"Captured with SteelSeries" badge, and of Outplayed's watermark, are undocumented in any source I could reach (SteelSeries support returned 403; no Outplayed results). Check by inspecting a sample clip.

## 6. Lyric text styling (fonts, 3D/metallic, text behind subject, per-word pop, glow)

### Takeaway
Text behind a subject uses a three-layer stack: original video at the bottom, text in the middle, and a background-removed copy of the video on top. CapCut does the cutout with Smart tools > Remove background > Auto removal; AE uses Roto Brush. Per-word pop uses AE text Animators (opacity/scale per word) keyed to waveform markers. CapCut offers 3D text with rotation, position and scale controls, plus stroke, glow and shadow.

### Cited Findings
- CapCut steps:
  - Web: video at the bottom, text above it, then a duplicate video above the text with Smart tools > Remove background > Auto removal (or Chroma key for green screen).
  - Desktop: compound clip (video plus text), then a cut-out copy on top. Mute the duplicate to avoid echo.
  - Mobile: Duplicate, then Overlay.
  - Keyframe the mask as the subject moves.
  - Source: [CapCut: text behind a person](https://www.capcut.com/resource/how-to-put-text-behind-a-person-in-capcut)
- Styling tips: use stroke/glow/shadow for legibility, semi-transparent text with a light glow for "poetic" looks, and export at the highest quality and 60 fps. — [CapCut: text behind a person](https://www.capcut.com/resource/how-to-put-text-behind-a-person-in-capcut)
- Check cutout edges, because rough edges are the giveaway. — [MiniTool: text behind person CapCut](https://moviemaker.minitool.com/news/how-to-put-text-behind-a-person-in-capcut.html)
- CapCut 3D text: AI-generated 3D text styles in the Text panel, with adjustable rotation, position and scale. — [CapCut: 3D text effect](https://www.capcut.com/ru-by/resource/3d-text-effect)
- Per-word animation in AE: use text Animators (Opacity, or a color animator for karaoke fills) set to animate per word or letter. Sync with the LL waveform and markers. — [SpotlightFX: lyric video in AE](https://spotlightfx.com/blog/how-to-make-a-lyric-video-in-after-effects-5-steps); [PremiumBeat: karaoke graphics](https://www.premiumbeat.com/blog/create-karaoke-graphics-after-effects); [Tutkit: words to the beat](https://www.tutkit.com/en/text-tutorials/28480-animating-words-to-the-beat-in-after-effects-step-by-step-guide); [Adobe: how to make a lyric video](https://www.adobe.com/creativecloud/video/discover/how-to-make-a-lyric-video)
- Time cost warning: a beginner can spend 8–10 hours on a single animated sentence. — [Adobe Community thread](https://community.adobe.com/t5/after-effects-discussions/how-to-do-lyrics-animation-in-a-after-effect/m-p/10448876)

### Inferences
- Pop-in spec for each word on its syllable:
  - Scale 0→115→100% over about 4–6 frames, using overshoot/Easy Ease.
  - Opacity 0→100% over 2 frames.
  - Optional 1–2 px Y bounce.
- Glow: AE Glow at radius 20–40 and intensity 1–1.5, or Deep Glow, tinted to the grade (pink for Teto). Add a 2–4 px stroke or drop shadow for legibility over bright Valorant maps.
- Fonts: condensed bold sans (e.g. Anton, Bebas, Montserrat ExtraBold) or a Japanese-style display font to match a vocaloid track. This is a choice; no source documents one standard font.
- Metallic/3D text: CapCut 3D text, or in AE a bevel (Bevel Alpha), a gradient ramp from silver to pink, and a light sweep.
- Text behind the subject works only when there's a clear subject (agent model, weapon viewmodel). In first-person Valorant, put the lyric behind the gun/arms viewmodel with a cutout of the viewmodel.

### Gaps
- No source documents the specific fonts or text presets used by top Valorant/TikTok velocity editors.
