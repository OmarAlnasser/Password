# Valorant / FPS Velocity Edits: Speed Ramping and Beat Mapping

Scope note: Velocity edits are mostly taught in YouTube and TikTok videos, which give few numbers in their text and descriptions. The sources I could read and cite are written guides (CapCut, Vidova, DJordan Media, an SBK Edits blog post, a Boris FX tutorial) and one open-source automation skill built specifically for Valorant TikTok beat edits (gustavomenani/editing-gameplay-montages, written in Portuguese, released in 2025). That skill matters because it encodes a working pipeline with exact numbers. I could not read Reddit threads directly. One fetch of a secondary Reddit write-up returned a 404, and only its search snippet survives. Treat numbers marked as inferences accordingly.

Beat-grid math for ~130 BPM (computed, not sourced): 1 beat = 60/130 = 0.4615 s = 13.8 frames at 30 fps, or 27.7 frames at 60 fps. A 1/8 note = 0.231 s (6.9 frames at 30 fps, 13.8 at 60 fps). A 1/16 note = 0.115 s (3.5 frames at 30 fps, 6.9 at 60 fps). A 4/4 bar = 1.846 s. This grid is used in the inferences below.

## 1. Speed-ramp patterns (fast, slow, fast curves; slow-mo %, hold length, ease curves)

### Takeaway
The standard velocity shape is a fast build (about 1.5x–2x, or up to 10x in CapCut), an eased drop into a slow section of about 10–30%, a short hold, then a fast exit. The drop is shaped as an S-curve in the AE Speed Graph, with handles pulled about 30–40% of the keyframe gap. "Impact" ramps are short: ramp in over 6–8 frames, hold 3–5 frames at 10–15% speed, ramp out fast. Slow-mo below about 25–30% needs 60 fps footage or more plus interpolation (Pixel Motion, Optical Flow, Twixtor or RIFE).

### Cited Findings
- **Speed scale**: 100% is normal, 50% is half speed and 0% is a freeze. 20–30% gives "dramatic slow motion" and 50–60% gives a "subtle drift". A fast subject can go to about 15%; a slow subject looks better around 40%. Keep the curve's fast peak "at or near 100%" unless you want an accelerated hit — [DJordan Media AE Speed Ramp Tutorial](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)
- **Preset timings** (all from [DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)):
  - **Impact Freeze**: ramp to 10–15% over 6–8 frames, hold 3–5 frames, ramp out fast. This is the closest match to a kill hit.
  - **Cinematic Drift**: ramp to 30–35% over 12–15 frames, hold 10–20 frames, ramp out at the same pace.
  - **Transition Pull**: 40–50% speed at the cut, ramping back to 100% on the next clip.
  - **Reverse Ramp**: start at 20–30% and ramp to 100% over 20–25 frames.
- **AE workflow**:
  1. Enable Time Remapping, which adds 2 keyframes.
  2. Add slow-mo entry and exit keyframes, for 4 in total.
  3. Open the Graph Editor (Shift+F3) and switch to Edit Speed Graph.
  4. Pull the inner handles out about 30–40% of the distance between keyframes to build an S-curve, then flatten the peak slightly.
  5. Remap the base footage layer, not an adjustment layer.
  6. Start the ramp before the impact, not during it.
  The manual method takes about 5–8 minutes per ramp — [DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)
- **Frame-rate requirements**: 30–40% speed needs at least 60 fps source. 20% speed needs 120 fps or more. Ramping 24 fps footage to 20% causes frame-blending artifacts — [DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)
- **What reads as slow-mo**: Build-up speed is about 1.5x–2x. About 0.25x reads as slow motion, while 0.5x–0.7x "often reads as a stutter". Slow-down uses an ease-out curve and speed-up uses an ease-in. An ease-out cubic starts at 3x its average speed, so 0.4 s of footage fills 1.2 s on screen — [Vidova: What is a speed ramp](https://vidova.ai/blog/what-is-a-speed-ramp)
- **Worked single-ramp example** (about 3.3 s): 0.5 s at 1x, then 0.4 s of footage stretched to 1.2 s, reaching near-stop at 1.7 s. Then 0.5 s of footage plays over about 0.94 s, exiting at 1.6x — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)
- **Velocity edit template**: about 18 s on a track of about 117 BPM. It has 4 action shots of 6 beats each, each entered with a whip pan. Build-up is about 2x and the peak is near-stop landing on a beat. Scale pushes in from 1.02x to 1.14x by the peak, and the edit ends on a freeze frame of the biggest moment — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)
- **Interpolation load at a 30 fps timeline**: 30 fps footage at 0.25x leaves 7.5 real frames per second, so 22.5 must be generated. 60 fps footage at 0.25x leaves 15 real frames. 120 fps footage at 0.25x leaves 30 real frames, so nothing needs generating — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)
- **Valorant AE tutorial (SBK Edits)**:
  - Setup: 1080 px, 30 fps comp; record at 60 fps or more.
  - Time remapping: Ctrl+Alt+T, with frame blending set to Pixel Motion.
  - Keyframes go on the first shot and the headshot indicator and are snapped to beat markers.
  - Dead time is removed by dragging keyframes together and splitting (Ctrl+Shift+D).
  - A sniper clip uses 4 keyframes: start, after hit, reload start, end.
  - Easing: apply Easy Ease (F9). In the Value graph, aim for steep at start (fast), flat in the middle (slow), steep at end (fast).
  — [SBK Edits Valorant Montage Tutorial](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)
- **CapCut**: Edit > Speed > Curve > Custom. The default custom curve has 5 beat points that can be added or deleted, and you drag them up to speed up and down to slow down — [Shotkit / FlexClip / Nerdschalk via search](https://shotkit.com/velocity-capcut/). On desktop the curve ranges from 0.1x to 10x, and a "Smooth slow mo" checkbox interpolates. The velocity points (white dots) should sit on beats — [CapCut: How to do velocity](https://www.capcut.com/resource/how-to-do-velocity-on-capcut)
- **CapCut presets**: Montage, Hero, Bullet, Jump Cut, Flash In and Flash Out. Applying a Style preset undoes previous velocity changes — [CapCut resource via search](https://www.capcut.com/resource/how-to-do-velocity-on-capcut). Mobile auto-velocity presets include flash, retro zoom, fade blur, blur shake and rainbow, and they auto-detect the music — [CapCut](https://www.capcut.com/resource/how-to-do-velocity-on-capcut)
- **Automated Valorant pipeline** ([gustavomenani/editing-gameplay-montages](https://github.com/gustavomenani/editing-gameplay-montages)):
  - Speed ramps are "smooth curves between anchors".
  - Frames are interpolated with RIFE to 240 fps everywhere and 960 fps where slowed, for a 60 fps output. That allows about 4x slow-down normally and 16x in slow sections.
  - After the shot, slow motion lasts until the body falls.
- **Reddit consensus** (secondary summary): don't slow down after every kill, because repeated slow-mo headshots look artificial. Vary pacing, for example by slowing right *before* the kill — [ZLeague summary of a Reddit thread (search snippet; the page later returned 404)](https://www.zleague.gg/theportal/unlocking-the-art-of-valorant-editing-a-reddit-post-analysis/)

### Inferences
- **Practical spec for a ~130 BPM funk track**:
  - Fast travel between kills runs at 150–300%.
  - Speed drops into 15–25% across about 1/8 note (6–7 frames at 30 fps, matching DJordan's 6–8 frame Impact Freeze).
  - Hold for 1/16–1/8 note (3–7 frames at 30 fps).
  - Exit back to 100%+ over about 1/8–1/4 note.
  - The full ramp cycle fits one beat (14 frames at 30 fps) or two beats (28 frames).
- **Curve shapes**:
  - AE: a Speed Graph S-curve, or in the Value graph steep, then flat, then steep (a "stair-step" velocity).
  - CapCut: Custom curve with the low point on the beat.
  - Premiere: time-remap rubber band with split keyframes and Bezier smoothing (no Premiere-specific source found).
- Bigger moments (the ace, the drop) get deeper or longer slow-mo of 10–15% for 0.5–1 beat. Routine kills get shallow or no slow-mo, so the effect stays special.

### Gaps
- I found no source giving AE influence % values specific to velocity edits. DJordan's "30–40% handle length" is the closest; YouTube creators commonly quote 80–100% influence, but I could not verify that in text.
- No Premiere Pro time-remapping specifics were found for gaming edits.
- No documented "standard" CapCut curve-point values for gaming velocity edits were found. Templates exist, but their curves are not published.

## 2. Kill sync: kill vs. shot on the beat; slow-mo on the kill; freeze/stutter

### Takeaway
Pros anchor the **frame of the shot that causes the kill**, not the kill-feed entry or death animation, onto the **attack of the beat** (the measured transient, not the theoretical grid). Slow motion starts at or just before the shot and lasts through the body falling. A transition or cut is placed shortly before each kill.

### Cited Findings
- **Anchor frame**: Each kill is anchored to the frame of the *shot that caused it*, not the kill-feed line. The tool looks back for the last shot where the ammo counter dropped before the kill-feed line appeared, then verifies against the ammo counter step or muzzle flash. One wrong frame equals 16.7 ms of desync at 60 fps — [skillsllm summary of the editing-gameplay-montages skill](https://skillsllm.com/skill/editing-gameplay-montages)
- **Beat placement**: Kills are placed on the *measured attack* of the beat, not the grid time. Beat attacks are measured from the drums with about 2 ms error. Accuracy on real Valorant edits was 62 of 66 kills on the exact shot frame, with the rest within 3 frames — [skillsllm](https://skillsllm.com/skill/editing-gameplay-montages)
- **Default cut**: a hard cut with a 5-frame blur (whip, zoom or spin) placed **14 frames before each kill**, about 233 ms at 60 fps. There is one cut before each kill in "kill-rhythm" mode, or fewer cuts aligned to bass hits in "bass" mode — [GitHub: editing-gameplay-montages](https://github.com/gustavomenani/editing-gameplay-montages)
- **Kill density**: the target is roughly one kill per second on measured drum hits. A validated 32 s edit had 16 kills — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- **Audio layer under kills**: the shot sits on the beat attack with a sub-bass hit under it. Big kills get booms, and risers lead into the drop — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- **SBK tutorial**: keyframes go on the first shot and the **headshot indicator** and are snapped to beat markers. Beat markers are placed with the numpad `*` key while viewing the waveform (LL) — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)
- **Reddit advice**: sync kills to downbeats for extra punch; one-taps read as high skill; slowing *right before* the kill is more dynamic than slowing after every kill — [ZLeague Reddit analysis (snippet)](https://www.zleague.gg/theportal/unlocking-the-art-of-valorant-editing-a-reddit-post-analysis/)
- **Freeze frame in AE**: Time > Freeze Frame at the playhead, and Split Layer (Ctrl+Shift+D) to resume or stutter. Being off by one frame makes the motion-to-still transition visibly "jump" — [Tuts+ / editvideofaster via search](https://www.editvideofaster.com/freeze-frame-after-effects/)
- **Vidova template**: the peak is "near stop, landing on a beat", and the edit ends on a freeze frame of the biggest moment — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)

### Inferences
- **Rule of thumb**: shot frame on the kick/snare transient, then slow-mo hold, with the headshot indicator or death landing during the slow section. The transition or whip comes about 1/2 beat before the kill (14 frames at 60 fps ≈ 0.23 s ≈ 1/8 note at 130 BPM).
- **Freeze or stutter**: hold 2–4 frames on the kill frame, or repeat a 2–3 frame slice of the kill 2–4 times on 1/16 notes. This is best reserved for the ace or the drop.

### Gaps
- I found no text source with exact freeze-hold lengths for gaming edits.
- "Stutter" repeat counts come from common practice and are not cited.

## 3. Beat mapping: every beat or accents only; which sounds; hi-hat rolls; tamborzão

### Takeaway
Cuts and kills land on strong, measured drum attacks (kick, snare, 808). Effects are reserved for the strongest moments, not every beat. Lighter "pulses" (flash or glow) can fill drum hits between kills. Brazilian funk sits around 120–150 BPM, built from syncopated, asymmetric 808 kicks, claps and tambor/surdo hits plus chopped vocal shouts used as percussion. Vocal chops and ad-libs are therefore valid hit points.

### Cited Findings
- Beat attacks are measured from kick, snare and hi-hat. A BPM estimate that doesn't match the actual attacks is rejected — [skillsllm](https://skillsllm.com/skill/editing-gameplay-montages)
- There are two placement modes: kill rhythm (one cut before each kill, on a beat) or bass (fewer cuts, checked to fall on kicks). Light pulses go on drum hits *between* kills, and "big kill" treatment is reserved for the drop, the strongest kill and the ace — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- Effects belong on the strongest moments only. A flash or shake on every cut hides the play. Zoom punches go on strong beats, camera shake is reserved for hits, and a single white flash frame goes on a cut — [DOR / search summary of gaming montage guides](https://clip.dor.gg/en/blog/how-to-make-gaming-montage)
- Add timed shake only on drops and "let the rest breathe" — [phonk-edit guidance via search](https://editingbyvikas.com/phonk-capcut-template/)
- CapCut's auto beat marker places markers automatically. Velocity points should sit on beats or rhythm points — [CapCut](https://www.capcut.com/resource/how-to-do-velocity-on-capcut); [Nerdschalk](https://nerdschalk.com/how-to-do-the-velocity-trend-using-capcut/)
- **Brazilian funk structure**:
  - Typical tempo is 120–150 BPM, with a faster "150 BPM" substyle and rasteirinha around 96–100 BPM.
  - The kick doesn't simply anchor the downbeat; snares fall in "unexpected positions" rather than the hip-hop backbeat.
  - Metallic hits and percussion bursts act as "rhythmic punctuation".
  - Chopped vocal phrases and processed shouts act as percussive accents and may contradict the drums.
  — [Digital Renaissance: Brazilian funk groove analysis](https://www.digitalrenaissance.education/magazine/the-global-rise-of-brazilian-funk-influence-rhythmic-pattern-and-groove-analysis-for-club-producers)
- Tamborzão means roughly "big drum", from its heavy surdo-like kick. It uses syncopated 808 kicks, claps and tambor/surdo samples at about 130–140 BPM, and its feel is asymmetric — [Melodigging: Tamborzão](https://www.melodigging.com/genre/tamborzao)

### Inferences
- **Hierarchy for a ~130 BPM funk track like "PayPal"**:
  1. Drop and first downbeat of a section: biggest kill, deepest slow-mo, flash and shake.
  2. Main kick/808 and clap hits: kills and cuts.
  3. Syncopated tamborzão hits and vocal shouts or ad-libs: zoom punches, small shakes and speed bumps (fast-forward pops).
  4. Hi-hats: no cuts, at most micro-shakes or glow pulses.
  Not every beat gets a hit. Roughly one kill per 1–2 beats in dense sections is the ceiling (one kill per second ≈ one kill per 2 beats at 130 BPM).
- **Tamborzão syncopation**: the off-grid kicks are well suited to quick speed "bumps" and zoom punches *between* kills. The kill itself goes on the strongest, most predictable hits.
- **Hi-hat rolls** (1/16 or 1/32 at 130 BPM = 115 ms or 58 ms, i.e. 3.5 or 1.7 frames at 30 fps): editors use stutter repeats, rapid micro-shakes, or a building speed-up (fast-forward ramp) into the next hit. No cited source confirms this for gaming edits.

### Gaps
- I found no bar-level transcription of the tamborzão kick/snare grid, and no BPM or structure analysis of Teto's "PayPal" specifically. The ~130 BPM figure comes from the assignment and is unverified.
- No source documents hi-hat-roll treatment in gaming edits.

## 4. Effects on beats: shakes, flashes, zoom punches, RGB split, glow, motion blur, frame blending/Twixtor

### Takeaway
The current toolkit:
- Shakes: S_Shake, Twitch, or the `wiggle()` expression, on hits and drops.
- Zoom punches and push-ins: about 1.02x→1.14x over a ramp.
- Single-frame white flashes, RGB split on big kills, inverted frames on the biggest kills, light pulses between kills.
- Motion blur: RSMB (optical-flow based, faster) over CC Force Motion Blur (frame-stacking).
- Interpolation for slow-mo: Pixel Motion, Optical Flow, Twixtor or RIFE.

### Cited Findings
- **S_Shake (Sapphire)**: example values are X Rand Amp 100, Y Rand Amp 150 and Tilt Rand Amp 5, on an adjustment layer — [Boris FX: Shake effect tutorial](https://borisfx.com/blog/shake-effect-after-effects-tutorial/)
- **Plugin-free shake**: `wiggle(3,8)` on position, where the first number is frequency — [Adobe Make It Center: wiggle](https://makeitcenter.adobe.com/blog/after-effects-wiggle.html)
- **Kill accents in the Valorant pipeline**: radial explosion, RGB split, light rays, and an inverted frame on big kills (drop, strongest kill, ace). Short zooms go on kills and light pulses on drum hits between kills — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- **Transitions**: 5 frames of blur (whip, zoom or spin) at each cut — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages). Glitch or Zoom Blur suits back-to-back kills; Fade or Light Leak suits mood changes — [DOR effects guide](https://clip.dor.gg/en/blog/game-montage-effects-guide)
- **Impact effect names**: Shake Zoom, Punch Zoom, Snap Zoom, Quick Zoom, Earthquake, Glare Impact and Flashback. Premiere options include Strobe Light, Light Leaks, RGB Split and Glint — [DOR effects guide](https://clip.dor.gg/en/blog/game-montage-effects-guide)
- **Push-in**: scale goes from 1.02x to 1.14x into the ramp peak — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)
- **SBK tutorial**: Motion Tile with Mirror Edges (output width ≈ 250) so shakes and zooms don't reveal edges, plus lens blur and glitch — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)
- **RSMB vs CC Force Motion Blur**: RSMB rendered in about half the time. RSMB uses optical flow to blur along motion, while CC Force Motion Blur stacks "onion skin" copies of frames — [Creative Dojo](https://creativedojo.net/reelsmart-motion-blur-vs-cc-force-motion-blur/)
- **Twixtor** synthesizes new frames by warping and interpolating, and is better than plain frame blending. It can artifact on messy motion or busy backgrounds — [Jonah Lee Walker on Twixtor](https://jonahleewalker.com/2021/04/08/the-best-way-to-slow-down-your-video-twixtor-from-revision-effects/)
- **Frame blending**: AE Pixel Motion or Frame Mix avoids choppy slow-mo — [DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial). The 2025 automation skill uses RIFE AI interpolation instead and recommends 60 fps or higher source, since at 30 fps half the frames must be invented — [skillsllm](https://skillsllm.com/skill/editing-gameplay-montages)
- **Tutorial ecosystem**: YouTube tutorials exist for Valorant shakes, flash effects in Premiere, saber glow with Twixtor slow-mo in AE, and RSMB in Resolve — [YouTube: shakes for Valorant edits](https://www.youtube.com/watch?v=O4jUVMkIKUQ); [YouTube: flash effect](https://www.youtube.com/watch?v=3kO7PWgfKcU); [YouTube: saber glow slow-mo](https://www.youtube.com/watch?v=AuAOHYWjyyU); [YouTube: beat shakes AE](https://www.youtube.com/watch?v=2PgWoBDOkBE)

### Inferences
- Flashes run 1–2 frames, with opacity 100%→0% over 2–4 frames.
- Shakes last 4–8 frames and decay; an S_Shake-style amplitude of 100–150 suits big hits, with smaller values on minor hits.
- Zoom punches go 100%→105–115% within 2–3 frames and ease back over about 1/8 note.
- RGB split runs 2–6 frames on kills.
- These are common-practice ranges and were not verified in text sources.
- Motion blur (RSMB) should go on the fast-ramp sections to sell speed. Slow sections need interpolation (Twixtor, RIFE or Optical Flow), or 30 fps captures will judder.

### Gaps
- I found no cited numbers for flash duration, RGB-split offset, chromatic aberration amount, glow settings, or RSMB blur amount specific to gaming edits.
- The Twitch plugin (Video Copilot) has no cited settings.

## 5. Clip length on screen; kills per clip; one continuous clip per sequence?

### Takeaway
Short-form Valorant velocity edits run about 15–45 s. At the dense end, roughly one kill per 1–2 s on measured drum hits. Each kill sequence is usually one continuous clip that is time-remapped, with dead time between kills removed by squeezing keyframes or splitting. A cut or whip transition comes just before each kill.

### Cited Findings
- **Project durations**: SBK sets up a 15 s comp at 30 fps — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html). Vidova's velocity template is about 18 s with 4 shots of 6 beats each — [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp). The automated Valorant TikTok edits were tested at 37–46 s, with a validated 32 s edit containing 16 kills — [skillsllm](https://skillsllm.com/skill/editing-gameplay-montages); [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- **Kill density**: target about one kill per second in dense sections. A 32 s edit with 16 kills averages one every 2 s — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)
- **Continuous clips**: SBK keeps a multi-kill clip continuous with time remapping and removes dead time by dragging keyframes together and splitting. A sniper clip uses 4 keyframes in one clip — [SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)
- **Vertical framing**: output is 1080×1920 at 60 fps, and in vertical the game window fills about one third of the frame height — [GitHub](https://github.com/gustavomenani/editing-gameplay-montages)

### Inferences
- At 130 BPM, a 6-beat shot (Vidova's template) is about 2.8 s and a 4-beat or 1-bar shot is about 1.85 s.
- A typical velocity section would show:
  - A single-kill clip for 1–2 bars (1.8–3.7 s).
  - A multi-kill clip (a 3k–5k round) as one continuous remapped clip of 2–4 bars, with each kill on a strong hit and fast-forward between kills.

### Gaps
- No survey or statistic exists on average shot length in Valorant TikTok edits.
- No source on Teto "PayPal" edits specifically was found.
