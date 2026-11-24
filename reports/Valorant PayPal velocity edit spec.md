# Rebuild the PayPal edit around the beats

The v3 edit fails mainly because its kills do not land on the music. The plan put 34 kills on beats, but only about **22 kill emblems are ever visible**, and many of them appear **0.4 to 0.7 s after the beat** or not at all. The cause is in the code. It puts "shot time minus 0.10 s" on the beat, then plays 0.15x slow motion, so the emblem shows up late. A whip jump at "kill + 0.3 s" then often cuts away before the emblem appears ([v3 emblem scan][embv3], [velocity.py][vel]). On top of that, v3 **reuses 5 clips** (nov14, sep10, sep06, oct04b, sep08c), splits the ACE into two places so it never reads as 5 kills, shows the **SteelSeries "MOMENTS" overlay in at least six places**, flashes on every kill (33 flashes against the reference's 15), and colours each clip by automatic gain instead of by song section ([local analysis][lma]). The reference TikTok works by a simple rule: the cut comes about 4 to 6 frames (0.06 to 0.13 s) before the hit, and the kill emblem pops on the hit (median offset 0.074 s). The grade also changes at fixed section points ([cut analysis][cuts], [map][map]). The fix is a full rebuild with **14 runs, 14 clips, each clip used once, about 37 kills on measured hits**, an ACE that starts on the strongest kick in the song (36.03 s) and ends on a big kick (42.96 s), and a hard rule never to show clip time before 4.4 s unless the overlay is masked. The "clean 3k" is almost certainly **sep17** (3 kills in 1.4 s, then "WON"). v3 used sep17, but only a 2.6 s slice that started inside the overlay time and showed only one emblem, so the 3k never read as a 3k.

All times in this report are in seconds. Output time and reference time use the same clock (reference 0.0 = song file at 7.618 s). Clip times are seconds inside each source clip and are accurate to about ±0.15 s ([local analysis][lma]). The song measures **129.2 BPM**, so one beat is **0.464 s** (about 28 frames at 60 fps) ([audio analysis][aud]).

## Twelve problems in v3, ranked by how much they hurt

The table lists what is wrong, from most serious to least. Every point comes from frame and audio measurement of v3 and the reference ([local analysis][lma], [v3 emblem scan][embv3], [cut analysis][cuts], [map][map]).

| Rank | Problem | Where in v3 (output time) | Why it hurts |
|---|---|---|---|
| 1 | **Kills miss the beat.** 34 kills planned, only about 22 emblems visible. | No emblem near the planned beat at 9.79, 14.38, 15.30, 18.07, 18.97, 23.62, 26.82 (emblem only at 28.25), 27.77, 29.15, 30.08, 31.00, 31.46, 32.37, 34.22, 35.14, 37.9 (emblem 0.48 s late), 40.2 (0.42 s late), 42.03 | This is the "missed beats" complaint. The edit does not hit. |
| 2 | **The biggest hits in the song are empty.** | Strongest kick 36.03: v3 cuts at 36.40 instead. Kick 10.41: nothing. Kick+snare 20.67: nothing. Top snare 30.49: v3 cuts off-grid at 30.40. Big kick 45.27: nothing. | The "potential beats" the user hears get no kill, no cut and no punch. |
| 3 | **Code bug.** `ks = [k - LEAD ...]` with LEAD 0.10, then 0.15x slow motion for 0.30 s after each kill. Whip jumps at kill + 0.3 s; 10 of 14 jumps are off the beat. | Jumps at 8.55, 12.92, 14.68, 19.27, 21.44, 27.12, 29.45, 31.21, 31.76, 32.59, 34.52, 35.44, 43.27, 44.21 | Emblem time = (0.1 + 0.15 + error) / 0.15 later than planned, or it is cut away before it shows. |
| 4 | **Kill times in the RUNS table are wrong** by 0.25 to 0.5 s. | e.g. oct04 10.25 (real 10.75), nov21 1.25/2.00 (real 1.5/2.7/3.45), sep11 3.00 (real 3.5) | Even a perfect sync rule would miss with wrong input times. |
| 5 | **Clips come back.** 5 clips are used twice. | nov14 at 0–5.55 and 33.6–36.4; sep10 at 5.55–7.32 and 42.4–end; sep06 at 10.32–12.0 and 36.4–38.8; oct04b at 13.78–15.65 and 38.8–41.0; sep08c at 26.3–28.5 and 41.0–42.4 | This is the "cuts between clips and comes back" complaint. |
| 6 | **The ACE is broken.** ACE kill 2 is used at 5.55; the end shows only ACE kills 3 to 5. | 5.55–7.32 and 42.4–46.48 | It never reads as 5 kills, so there is no "oooh ACE" moment. |
| 7 | **SteelSeries overlay is visible.** | "MOMENTS" at 7.6–8.3, 10.4–11.0, 19.2, 28.6; orange "CAPTURED WITH steelseries" at 15.65–18.4 (all of sep08 and nov21); also 18.5–19.0 (n01) and 30.5–31.0 (sep11) | The user said it must never be visible. |
| 8 | **The clean 3k is lost.** sep17 is used as src 2.77→5.38 only. | 7.32–9.17; one emblem at 8.62 | Starts inside overlay time, cuts the 3rd kill (5.9) and the WON banner. |
| 9 | **Clips are not fully used.** | oct04 src ends at 10.46, before its first emblem (10.75), so that kill never shows. n01 is stretched over 5.9 s. | Plays are cut into slices; the viewer never sees a whole multi-kill. |
| 10 | **Source plays backwards.** | n01 run (18.40–24.30) reaches source speed −101; nov14 run (33.60–36.40) reaches −13 | Reverse footage looks like a glitch. |
| 11 | **Grade follows clips, not the song.** | 0–6 heavy magenta (reference is cool blue); 7–35 mostly flat; 36–40.5 blown-out orange (saturation up to 200) from the wood rooms in sep06/oct04b | This is the "colour never changes per section" complaint: changes exist, but they are accidents, not design. |
| 12 | **Too many flashes, wrong place; off-grid cuts; stray emblems.** | 33 flashes, one per kill. 5 of 18 clip cuts off-grid (15.65, 28.5, 30.4, 33.6, 42.4). nov14 emblem lingers 0–2.6 with no hit; sep10 emblem lingers 5.62–5.75. | Flash on every kill hides the play. Lingering emblems without a hit look like mistakes. |

The pattern behind these twelve points is simple. v3 tried to fix sync by moving the **shot** onto the beat, but what the viewer sees on the beat is the **emblem**. The reference puts the emblem on the beat. Written guides say the same: keyframes go on "the first shot and the headshot indicator" and are snapped to beat markers ([SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)), and automated Valorant edits place kills on the measured attack of the drum hit, not on the theoretical grid ([skillsllm](https://skillsllm.com/skill/editing-gameplay-montages)).

## The reference hits about 34 times, almost always on a drum

The reference has **36 cuts between clips, 27 cuts inside runs, 34 kill-emblem pops and 15 white flashes** ([cut analysis][cuts]). Its emblems land on the beat: 53% are within 0.08 s of a beat and most of the rest sit on a kick, snare or hi-hat ([reference emblems][embref]). Its cuts come early, with a mean of −0.10 s to the nearest beat. Examples: cut 7.32 before kick 7.38, cut 13.78 before kick 13.85, cut 17.77 before kick+snare 17.80, cut 22.15 before kick 22.20, cut 44.30 before kick+snare 44.33 ([map][map]). From 22.15 to 35.9 it cuts every 2 beats (about 0.92 s) with one kill per shot. Its 15 flashes are almost all on clip cuts, not on kills, and nearly every cut has a zoom or motion blur dip, so the transitions are whip and zoom-blur cuts ([cut analysis][cuts]). It ends with one normal kill at 44.12 and a **fade to black at 45.4 to 45.6**. There is **no ACE** in the reference, and its footage is another player's ([local analysis][lma]).

The song's strongest hits are the "potential beats" the user hears. Measured on the kick/808 band they are, in order: **36.03** (the strongest in the song), **17.80, 10.41, 36.93, 42.96, 20.67, 45.27**, then 14.79, 13.85, 28.21, 29.55, 40.67. The strongest snares are 30.49, 22.64, 26.80, 8.71, 20.67, 45.27, 12.92, 8.33, 39.96, 27.13, 15.25 and 28.65 ([audio analysis][aud]). The intro (0 to 6) is quiet, energy rises at 6 to 7, and there is a dip from 19 to 21, which is the "PEGA NO MEU HOLY SHIT" breakdown. Brazilian funk uses syncopated 808 kicks, claps and shouted vocal chops as percussion, so some hits fall off the straight grid ([Digital Renaissance](https://www.digitalrenaissance.education/magazine/the-global-rise-of-brazilian-funk-influence-rhythmic-pattern-and-groove-analysis-for-club-producers); [Melodigging](https://www.melodigging.com/genre/tamborzao)). Those off-grid hits (10.41, 8.71, 27.13, 29.55, 39.96) are where a zoom punch or shake belongs, even when no kill is there.

The reference grade changes by section ([cut analysis][cuts], [map][map]):

| Reference time | Look | Measured |
|---|---|---|
| 0–2.78 | Cool blue | R−B −15 to −26 |
| 2.78–5.55 | Bright pink-white smoke | Y 135–149 |
| 5.55–7.32 ("YEAH") | Hot yellow/red | Sat 126–153, R−B +45 to +83 |
| 7.3–16.8 | Neutral to slightly warm | Sat 77–114 |
| 17.0–17.25 | Full-frame yellow flash frames | Sat 156–163 |
| 18–23 | Warm orange, red lyric text | R−B +38 to +72 |
| 26.5–28.25 and 43.0–45.25 | Magenta edge vignette | — |
| 34–36 and 39–40 | Darker | Y 63–73 |
| 42–44 | Saturated | Sat 127–138 |
| 45.4–45.6 | Fade to black | — |

There is no black-and-white section in the reference. The lyric words appear on the vocal syllables; the full word timing list is in the spec below ([reference sheets][refs0]).

## What the user asked for, and what each clip can give

The user's wishes map to clear rules. "Hit every potential beat" means the emblem goes on measured hits, and off-grid hits get a punch. "Don't cut away and come back" means one clip per run and no clip used twice; jumping forward inside the same clip is fine, but never backwards. "Grade per section" means the grade switches on fixed section beats through an adjustment layer, not per clip. "Oooh ACE" means sep10's five kills play as one run that builds and peaks. "Never show the GG logo" means no clip time before 4.4 s unless masked. "Use the clean 3k" means sep17 in full. "Use clips fully" means show the whole play of each run (all its kills and its banner), not a slice.

Genre guides support most of this. Editors keep a multi-kill clip continuous and remove dead time inside it with time remapping ([SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)). Effects belong on the strongest moments, because a flash or shake on every cut hides the play ([DOR](https://clip.dor.gg/en/blog/how-to-make-gaming-montage)). "Big kill" treatment is kept for the drop, the strongest kill and the ACE ([editing-gameplay-montages](https://github.com/gustavomenani/editing-gameplay-montages)). Slowing after every kill looks artificial ([ZLeague summary](https://www.zleague.gg/theportal/unlocking-the-art-of-valorant-editing-a-reddit-post-analysis/)). The "never come back to a clip" rule and "best clip on the drop, ACE last" ordering appear in no written source I could reach; they are genre habit, and the user asked for them directly.

The user's Drive folder holds exactly the same 14 clips plus one byte-identical copy of sep08 (13,102,368 bytes). No clip has "3k", "ace", "fade" or "clean" in its name. n01 is titled **"end it here"** ([Drive folder](https://drive.google.com/drive/folders/1QSVtWsr_x8ChUeyk1qzkqG7zMAQf-PSf)). Every clip has the same overlay at source 0 to about 4.3 s ([local analysis][lma]).

| Clip | Size, length | Kill emblem times (src) | Big moment | Best part | Overlay risk |
|---|---|---|---|---|---|
| **sep10** | 1080p, 36.0 | 9.25, 10.5, 21.25, 31.25, 34.0 | **The only real ACE (5K).** "ACE – Balerion" banner 34.0–35.75. Emblem grows each kill; kill 5 is a white/red-burst ACE emblem. | 8.5–36.0, squeeze the walks at 12.5–21 and 22.8–31 | None |
| **sep17** | 1080p, 7.98 | 4.5, 5.2, 5.9 | **Clean 3K in 1.4 s**, "WON" at 7.6 | 4.35–7.98 | Overlay ends 4.3; start after it |
| sep05b | 1080p, 15.8 | 7.25, 11.5, 13.0 | 3K **CLUTCH** banner 13.25–13.4 | 6.5–15.0 | None |
| sep21 | 1080p, 25.1 | 7.25, 8.25, 10.0, 12.25 | **4K in 5 s**. Later an enemy "ACE – Clove" banner at 24.75 (never use) | 6.3–13.5 | None |
| nov21 | 1440p, 14.8 | 1.5, 2.7, 3.45, 8.5 | **4K**, first 3 in 2 s | 0.8–4.6 | **Whole part is inside overlay time: mask** |
| oct04 | 1080p, 19.2 | 10.75, 12.0, 15.0, 16.75 | 4 kills; "LOST" at 17.25 (stop before 17.1) | 10.0–17.0 | None |
| oct04b | 1080p, 21.9 | 6.0, 13.25, 17.5, 20.25 | 4 spread kills | 12.4–21.0 | None |
| sep06 | 1080p, 27.65 | 4.0, 4.75, 9.25, 22.5 | 2K at 4.0/4.75 | 3.8–10.0 | **Mask until 4.4** |
| sep08c | 1080p, 21.06 | 5.75, 13.25, 15.25, 16.0 (8.75 not sure) | 3K in 2.75 s, "WON" 20.75 | 12.4–20.9 | None |
| sep11 | 1080p, 30.4 | 3.5, 7.5, 12.0, 19.5 (8.75 not sure) | 4 kills | 3.4–12.5 | **Mask until 4.4** |
| nov14 | 1440p, 47.0 | 5.75, 16.0, 38.25, 43.0 (43.5?) | Pink smoke 6.3–9.5 | 4.4–9.5 | None if start at 4.4 |
| n01 "end it here" | 1080p, 28.9 | 3.0, 19.5, 20.5 | 2K at 19.5/20.5; death/scoreboard from 25.0 | 18.6–21.6 | None |
| sep05 | 1080p, 57.7 | 5.0, 13.25, 14.5?, 35.5, 49.25 | Mostly single kills | 12.4–15.5 | None |
| sep08 | 1080p, 5.12 | 1.6 | Single kill, yellow arc 1.5–1.75 | 1.5–3.4 | **Whole clip is inside overlay time: mask** |

Sources for this table: emblem tiles and banner scan ([emblem sheet][emall0], [events][ev], [banner scan][ban], [sep10 ACE][sep10]).

The overlay sits at the **left edge, lower middle**, not in a corner at the top. From 0 to about 1.5 s it is an orange "CAPTURED WITH steelseries" bar; from about 2 to 4.25 s it is a dark "MOMENTS·GG" box. At 1920×1080 the box is x 0–300, y 760–840. At 2560×1440 (nov14, nov21) it is x 0–400, y 1013–1120 ([overlay crop][ovcrop], [left-edge sheet][left]). The gear in the top-left is the Valorant minimap, not a logo. A static "Client FPS / Packet Loss" text line runs along the top (y 4–18 at 1080p) and is worth cropping too.

## The remake spec: 14 runs, 37 kills, one clip each

This section is the ready-to-use plan. The timeline follows the reference's own section cuts and the measured drum hits ([local analysis][lma], [audio analysis][aud]). Speed numbers are averages between anchors, computed from the source and output times; ramp shapes follow written velocity guides ([DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial); [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)). Some source start times are moved slightly from the research notes so the first kill can land right after the cut; these changes are mine and are marked "adj.".

### Timeline

| Run | Output | Clip | Source | Kill emblem → output time (hit) | Average speeds | Section grade | Notes |
|---|---|---|---|---|---|---|---|
| R1 | 0.00–5.55 | nov14 | 4.4→5.75, jump forward to 6.3→9.5 (adj.) | 5.75 → **2.78** (beat, "PAYPAL" starts) | 0.5x to the kill; 1.15x through smoke | 0–2.78 cool blue; 2.78–5.55 pink-white | Calm open. The only kill lands on the grade switch. No emblem lingers without a hit. |
| R2 | 5.55–7.32 | sep08 | 1.5→3.4 (adj.), **masked** | 1.6 → **5.64** (beat+snare, "YEAH") | ~1x in, 0.3x hold for 0.3 s, ~1x out | Hot yellow/red | Yellow arc matches the yellow grade. |
| R3 | 7.32–9.17 | **sep17 (clean 3k)** | 4.35→7.98 (adj.) | 4.5 → 7.48, 5.2 → 7.94, 5.9 → **8.38** (drop, snare 8.33) | ~1.3x, 1.5x, 1.6x; after kill 3: 0.25x for 4 frames, then ~3x into WON | Neutral-warm | WON banner (src 7.6) shows around 8.9. Zoom punch on snare 8.71. |
| R4 | 9.17–12.00 | oct04 | 10.0→15.3 | 10.75 → 9.80, 12.0 → 10.68, 15.0 → 11.59 | 1.2x, 1.4x, 3.3x, then 0.7x | Neutral-warm | Zoom punch on off-grid kick 10.41. Stop before "LOST" (src 17.1). |
| R5 | 12.00–13.78 | sep05b | 6.6→13.6 (adj.) | 7.25 → 12.06, 11.5 → **12.98** (snare 12.92), 13.0 → 13.44 | 4.6x and 3.3x travel (motion blur) | Neutral-warm | Shows the whole clutch: 3 kills + CLUTCH banner held to 13.78. |
| R6 | 13.78–17.77 | sep21 | 6.3→13.5 | 7.25 → 14.40, 8.25 → **14.84** (kick 14.79), 10.0 → 15.77, 12.25 → 16.70 | 1.5x, 2.3x, 1.9x, 2.4x; after kill 4: 0.3x, then build | Neutral-warm; **yellow flash frames 17.0–17.25** | Quick 4K. Punch on snare 15.25. Stop long before src 24 (enemy ACE). |
| R7 | 17.77–19.40 | nov21 | 0.8→4.6, **masked (1440p)** | 1.5 → 18.07, 2.7 → 18.53, 3.45 → 18.97 | 2.3x, 2.6x, 1.7x, 2.7x | **Warm orange** starts 17.77 | Cut on kick+snare 17.80. |
| R8 | 19.40–22.15 | sep11 | 3.45→12.5 (adj.), mask to 4.4 | 3.5 → 19.43, 7.5 → **20.67** (kick+snare), 12.0 → 21.80 | 3.2x, 4.0x travel, 1.4x out | Warm orange | Breakdown ("PEGA NO MEU HOLY SHIT"). Fewer effects here; let it breathe. |
| R9 | 22.15–25.94 | sep06 | 3.85→10.5 (adj.), mask to 4.4 | 4.0 → 22.25 (kick 22.20), 4.75 → **22.69** (snare 22.64), 9.25 → 24.52 | 1.7x, 2.5x, then ~0.9x | Warm orange to 23, then neutral | Cut on kick 22.20 ("UP THE SMOKE"). Avoid the orange wood-room blow-out: cap saturation. |
| R10 | 25.94–29.62 | oct04b | 12.4→21.0 | 13.25 → **26.84** (snare 26.80), 17.5 → **28.24** (kick 28.21), 20.25 → 29.16 | 1.0x, 3.0x, 3.0x, 1.6x | **Magenta edge vignette 26.5–28.25** | Punch on 27.13 and 28.65. |
| R11 | 29.62–33.23 | sep08c | 12.4→20.9 | 13.25 → **30.49** (top snare), 15.25 → 31.46, 16.0 → 31.93 | 1.0x, 2.1x, 1.6x, then 3.6x into WON | Saturated pink/neutral | Punch on kick 29.55. WON (src 20.75) just before the cut. |
| R12 | 33.23–35.93 | sep05 | 12.4→15.5 | 13.25 → 33.79, 14.5 → 34.23 | 1.7x, 2.8x, then **0.5x slow build** | **Darker** (like reference 34–36) | Pre-drop tension. Cut on kick+snare 33.26. Speed rises again in the last beat before the drop. |
| R13 | 35.93–44.30 | **sep10 ACE** | 9.15→36.0 | 9.25 → **36.06** (strongest kick 36.03), 10.5 → **36.93** (kick), 21.25 → 38.85, 31.25 → **40.67** (kick), 34.0 → **42.96** (kick) | 1.4x, **5.6x**, **5.5x** (walks, heavy motion blur), then ramp down to 0.25x before kill 5 | Full saturation snap at 36.03; dark at 39–40; saturated + **magenta vignette 43–45.25** | The "oooh ACE". See ACE staging. Punch on snare 39.96. |
| R14 | 44.30–end | n01 "end it here" | 18.6→21.6 | 19.5 → 44.84, 20.5 → **45.27** (big kick+snare) | 1.7x, 2.3x, then 0.25x hold | Saturated, magenta vignette, **fade to black 45.4–45.6** | Short closing tag. Stop before death (src 25.0). |

This gives about **37 kill hits on measured drum hits** (reference: 34; v3 visible: about 22), plus about 10 punch accents on off-grid hits that have no kill. All 14 clips are used once. The sep08 duplicate is not needed.

### Kill-sync rule

The **kill emblem's first frame** goes on the measured drum attack (kick, snare or 808), within ±1 frame at 60 fps. This is what the reference does. Because the emblem appears about 0.1 s after the shot, at 0.3x speed the shot shows about 0.33 s before the hit. That is good: the viewer sees the flick, then the emblem hits the drum. The **clip cut comes 4 to 6 frames (0.06–0.10 s) before a hit**. Inside a run, a forward jump may only happen at least **0.5 s of source time after an emblem**, and only on a hi-hat, snare or beat. Never play source backwards. Before render, check every emblem onset at 60 fps, because current kill times are only ±0.15 s accurate ([local analysis][lma]). The written method behind this is "keyframes on the shot and the headshot indicator, snapped to beat markers", with beat markers taken from the waveform ([SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)), and kills placed on measured drum attacks rather than the grid ([skillsllm](https://skillsllm.com/skill/editing-gameplay-montages)).

### Speed-ramp numbers

Travel between kills runs at **1.5x to 3x**, up to **5.5x** only in the sep10 walks, with motion blur (RSMB is faster than CC Force Motion Blur) ([Creative Dojo](https://creativedojo.net/reelsmart-motion-blur-vs-cc-force-motion-blur/)). A normal kill gets a short "impact" dip: ramp to **25–35%** over 6–8 frames, hold 3–5 frames, ramp out fast. The big moments (drop 8.38, drop 36.03, ACE kill 5, final 45.27) get **10–15%** for half to one beat ([DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)). Do not slow down on every kill; about one kill in three gets a real slow-motion dip. Avoid long stretches at 0.5–0.7x, which "often reads as a stutter" rather than slow motion ([Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)). Use S-curve speed graphs with handles at about 30–40% of the keyframe gap, and start the ramp before the impact, not on it ([DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial)). Below about 30% speed you need 60 fps source plus frame interpolation (Pixel Motion, Twixtor or RIFE); 20% needs 120 fps or interpolation, or it judders ([DJordan Media](https://djordanmedia.com/blogs/news/after-effects-speed-ramp-tutorial); [Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)).

### ACE staging (R13, 35.93–44.30)

The reference has no ACE, so this staging is my design, built from documented impact patterns. Boris FX describes the impact as "slow motion before the action, followed by a beat drop", plus an optional still frame right after the shake, and gives shake values: amplitude 6 on the impact frame, falling to 0 over about 20 frames, frequency 15 ([Boris FX](https://borisfx.com/blog/shake-effect-after-effects-tutorial/)). Applied here, kill 1 lands on **36.03**, the strongest kick in the song, with a double white flash, a full-saturation grade snap and a big shake. Kill 2 hits kick 36.93 with a small punch only. The two walks race at about 5.5x with motion blur, and kills 3 and 4 hit 38.85 and kick 40.67 with small punches, so the count keeps rising. The emblem grows with each kill in this clip, which helps the count read ([sep10 emblems][emsep10]). From about 42.0, the speed ramps down to 20–25% and the zoom creeps from 100% to 110%. Kill 5 lands on kick **42.96**. On that frame: 1–2 inverted or white impact frames, a freeze of 3–4 frames, the heavy shake, then a punch-zoom to 120–125% toward the top-centre "ACE" banner (about x 710–1210, y 136–325 at 1080p) ([banner scan][ban]). Hold the banner at 0.3–0.5x until the cut at 44.30, under the magenta edge vignette. Keep lyric text off the banner during this hold.

### Section grade

Switch grade only on section beats, using adjustment layers placed on the beat marker, never per clip and never by auto-gain. The values copy the reference table above: cool blue (0–2.78), pink-white (2.78–5.55), hot yellow/red (5.55–7.32), neutral-warm with saturation +10 (7.32–16.9), yellow flash frames (17.0–17.25), warm orange (17.77–23.0), neutral with more contrast (23.0–26.5), magenta edge vignette (26.5–28.25), saturated pink-neutral (28.25–33.23), darker by about 20% (33.23–35.93), full saturation snap (36.03), a short darker dip (39–40), saturated plus magenta vignette (42.5–45.25), fade to black (45.4–45.6). Cap saturation in the sep06 and oct04b wood rooms so orange never blows out as in v3. A pink/magenta lean fits the song: Kasane Teto's signature colours are pink-red ([Know Your Meme](https://knowyourmeme.com/memes/kasane-teto)). In Lumetri, use Hue vs Hue and Hue vs Sat curves to push reds toward pink, and keep any LUT at 50–70% strength ([Adobe](https://helpx.adobe.com/premiere/desktop/correct-color/add-color-effects/correct-color-using-hue-and-saturation-curves.html); [Freevisuals](https://www.freevisuals.net/post/master-lumetri-color-for-premiere-pro-cinematic-looks)).

### Transitions and flashes

Every clip cut is a hard cut with **5 frames of whip or zoom blur** ([editing-gameplay-montages](https://github.com/gustavomenani/editing-gameplay-montages)), matching the reference's blur dip at nearly every cut. Use Motion Tile with mirror edges so zooms and shakes never show black borders ([SBK Edits](https://sbkeditsofficial.blogspot.com/2022/04/valorant-montage-tutorial-time.html)). Use **about 15 white flashes**, on cuts and big moments only, never on every kill: 5.55 (tinted yellow), 7.32, 9.17, 12.00, 13.78, 17.0–17.25 (yellow), 17.77, 19.40, 22.15, 25.94, 29.62, 33.23, 36.03 (double), 42.96 (inverted, double), 44.30. A flash is 1–2 frames, fading out over 2–4 frames. Fade to black is used only at the end.

### SteelSeries overlay rule

The rule is simple: **no frame from source time 0–4.4 s may reach the final video unless it is masked.** Runs R2 (sep08), R7 (nov21), R8 (sep11, until 4.4), and R9 (sep06, until 4.4) need the mask. Mask area: **x 0–330, y 750–850 at 1080p**, or **x 0–440, y 1000–1135 at 1440p** ([overlay crop][ovcrop]). Fill it with Content-Aware Fill in After Effects ([Adobe](https://helpx.adobe.com/after-effects/using/content-aware-fill.html)), or with a feathered blurred patch from a nearby frame. If the output is a centred 9:16 vertical crop (608 px wide at 1080p, x 656–1264), the overlay is already outside the frame, but still check every masked run frame by frame. For future clips, turn the tag off in SteelSeries GG: Settings > Moments > Overlays and Notifications > uncheck "Moment Overlay" ([SteelSeries support](https://support.steelseries.com/hc/en-us/articles/43442485371917-How-to-enable-disable-Moments-tag-on-my-clips)).

### Lyric text style

One or two words at a time, each popping on its syllable. Pop: scale 0→115→100% over 4–6 frames with overshoot, opacity 0→100% over 2 frames. Font: a condensed bold sans (Anton, Bebas Neue or Montserrat ExtraBold). Colour: white with a pink glow (Glow radius 20–40) and a 2–4 px dark stroke; red text from 18 to 23 like the reference. Place the text in the centre, away from the lower-left overlay zone, the top-right kill feed and the top-centre ACE banner. Optionally put the text behind the gun model with a cutout layer ([CapCut](https://www.capcut.com/resource/how-to-put-text-behind-a-person-in-capcut)). Text style and font have no documented genre standard; these are choices. Word timings come from the reference ([reference sheets][refs0], [part 2][refs1]).

### Copy-paste prompt

```text
Remake my Valorant velocity edit to Teto "PayPal". Song: 129.2 BPM, beat = 0.464 s.
Output clock: 0.0 = song file at 7.618 s. Length about 46 s. 60 fps.

HARD RULES
1. One clip per run. Each of the 14 clips is used exactly once. Never cut back to a clip.
   Never play source backwards. Forward jumps inside a run are allowed.
2. Kill sync: the FIRST FRAME OF THE KILL EMBLEM lands on the measured drum hit (±1 frame).
   Clip cuts come 4-6 frames (0.06-0.10 s) BEFORE a hit.
   No in-run jump less than 0.5 s of source after an emblem. Jumps only on hats/snares/beats.
   Check every emblem onset at 60 fps before render (listed times are ±0.15 s).
3. SteelSeries overlay: no source time 0-4.4 s on screen unless masked.
   Mask x0-330 y750-850 (1080p) / x0-440 y1000-1135 (1440p). Content-aware fill.
4. Show the whole play of each run: every kill listed + its banner.
5. Flashes only on cuts and big moments (about 15 total), never on every kill.

TIMELINE (run | out | clip | source | emblem -> out time)
R1  0.00-5.55   nov14  4.4->5.75, jump to 6.3->9.5   5.75->2.78
R2  5.55-7.32   sep08  1.5->3.4 MASK                 1.6->5.64
R3  7.32-9.17   sep17 (clean 3k) 4.35->7.98          4.5->7.48, 5.2->7.94, 5.9->8.38 ; WON ~8.9
R4  9.17-12.00  oct04  10.0->15.3                    10.75->9.80, 12.0->10.68, 15.0->11.59
R5  12.00-13.78 sep05b 6.6->13.6                     7.25->12.06, 11.5->12.98, 13.0->13.44 ; CLUTCH held
R6  13.78-17.77 sep21  6.3->13.5                     7.25->14.40, 8.25->14.84, 10.0->15.77, 12.25->16.70
R7  17.77-19.40 nov21  0.8->4.6 MASK(1440p)          1.5->18.07, 2.7->18.53, 3.45->18.97
R8  19.40-22.15 sep11  3.45->12.5 MASK to 4.4        3.5->19.43, 7.5->20.67, 12.0->21.80
R9  22.15-25.94 sep06  3.85->10.5 MASK to 4.4        4.0->22.25, 4.75->22.69, 9.25->24.52
R10 25.94-29.62 oct04b 12.4->21.0                    13.25->26.84, 17.5->28.24, 20.25->29.16
R11 29.62-33.23 sep08c 12.4->20.9                    13.25->30.49, 15.25->31.46, 16.0->31.93 ; WON before cut
R12 33.23-35.93 sep05  12.4->15.5                    13.25->33.79, 14.5->34.23 ; slow build to drop
R13 35.93-44.30 sep10 ACE 9.15->36.0                 9.25->36.06, 10.5->36.93, 21.25->38.85, 31.25->40.67, 34.0->42.96
R14 44.30-end   n01    18.6->21.6                    19.5->44.84, 20.5->45.27 ; fade to black 45.4-45.6
Punch/shake accents (no kill): 8.71, 10.41, 13.85, 15.25, 27.13, 28.65, 29.55, 33.26, 39.96.

SPEED
Travel 1.5-3x (5.5x only in sep10 walks, with motion blur). Normal kill: ramp to 25-35% over
6-8 frames, hold 3-5 frames, fast out. Only ~1 in 3 kills gets slow motion. Big moments
(8.38, 36.03, 42.96, 45.27): 10-15% for 0.5-1 beat. S-curve speed graph. Interpolate slow parts.

ACE (R13)
36.03 kill 1 = double flash + full-saturation snap + big shake. Kills 2-4 small punches.
Walks at ~5.5x. From ~42.0 ramp to 20-25% + zoom 100->110%. Kill 5 on 42.96: 1-2 inverted
frames, 3-4 frame freeze, shake amp 6 decaying over 20 frames, punch-zoom 120-125% to the ACE
banner (top centre), hold banner at 0.3-0.5x to 44.30, magenta edge vignette.

GRADE (adjustment layers on beat markers, not per clip)
0-2.78 cool blue | 2.78-5.55 pink-white | 5.55-7.32 hot yellow/red | 7.32-16.9 neutral-warm
17.0-17.25 yellow flash frames | 17.77-23.0 warm orange | 23.0-26.5 neutral, more contrast
26.5-28.25 magenta edge vignette | 28.25-33.23 saturated pink-neutral | 33.23-35.93 darker
36.03 full saturation snap | 39-40 darker dip | 42.5-45.25 saturated + magenta vignette
45.4-45.6 fade to black. Cap saturation in wood rooms (sep06, oct04b).

TRANSITIONS / FLASHES
Hard cut + 5-frame whip/zoom blur at every clip cut. Motion Tile mirror edges.
Flashes (1-2 frames, fade 2-4): 5.55(yellow) 7.32 9.17 12.00 13.78 17.0-17.25(yellow) 17.77
19.40 22.15 25.94 29.62 33.23 36.03(double) 42.96(inverted) 44.30.

LYRICS (pop on syllable: scale 0->115->100% in 4-6 frames; bold condensed sans; white + pink
glow, red 18-23; centre; never over the ACE banner)
TETO 0.5 | PAYPAL 3.0 | YEAH/AH/YEAH 5.5-6.75 | FIZ 7.0 | UM SHOW 7.5 | SOLD 7.75 | OUT 8.0
ENTROU NA 8.25 | MINHA CONTA 9.0 | NO 9.5 | PAYPAL 9.75 | GRANA 10.25 | AINDA 10.75
ME TIRAR 11.0 | DESSA LAMA 11.5 | ESSA 12.0 | BITCH 12.25 | NÃO 12.5 | QUER 12.75 | AMOR 13.0
BANANA 13.5 | EU 13.75 | DINHEIRO 14.25 | NA 14.75 | CAMA 15.0 | VAI 15.25 | FURO 15.75
ATRAVÉS 16.25 | DA 16.5 | PAREDE 16.75 | COM 17.0 | REAL 17.25 | NÃO 17.5 | DE FRENTE 18.0
PEGA 20.25 | NO 20.75 | HOLY 21.0 | SHIT 21.5 | UP 22.25 | THE 22.5 | SMOKE 22.75 | SÓ 23.0
BALÃO 23.5 | CUP 26.75 | ENTRA 30.75 | DIZ 32.5 | QUE É MINHA 33.0 | SOU 35.25 | TETINHO 35.5
NO MEU 38.75 | PESCOÇO 39.0 | EU TAVA 39.75 | PERDIDO 40.25 | MAS DISSO 40.75 | LEMBRO 41.5
Ad-libs "AHN" at 29.75, 31.75, 33.5, 34.25.
```

## Questions to answer before rendering

Some points cannot be settled from the files. **Which clip is the "clean 3k fade"?** The best guess is sep17: three kills in 1.4 s, nothing messy, then "WON". The second guess is sep05b (3K clutch). "Fade" could mean the agent Fade, a fade transition, or a fade-out ending; the agent in each clip could not be identified from the frames ([local analysis][lma]). **Should the edit end on the ACE or on n01?** The plan ends with n01 because its Drive title is "end it here", but a 2-kill tag after an ACE can feel smaller. Option B: let sep10 run to the end (kill 5 on kick+snare 44.33, banner held to the fade at 45.4), move n01 into the R12 slot, and drop sep05, the weakest clip (mostly single kills). That breaks "use every clip" but gives the strongest ending.

**What frame rate are the clips?** The slow-motion numbers assume 60 fps; at 30 fps every dip below 30% needs interpolation and may show artifacts ([Vidova](https://vidova.ai/blog/what-is-a-speed-ramp)). **What output shape?** If the final video is a centred 9:16 crop, the overlay is cut away on its own; in 16:9 it must be masked. **Can the user re-export the clips without the overlay?** That is cleaner than any mask. **How fully should clips be used?** The plan shows every kill of each chosen play, but some far-away kills are left out because the time is not there: nov21 8.5, sep11 19.5, sep06 22.5, oct04b 6.0, sep08c 5.75, oct04 16.75, nov14 16.0/38.25/43.0, and sep05 35.5/49.25. Some kill times are not confirmed (sep05 14.5, sep08c 8.75, sep11 8.75, nov14 43.5), and the kill counts for oct04, oct04b, sep11 and nov14 come from emblem flares only. Finally, **how pink should it be?** The reference is not pink overall; it uses pink in the smoke shot and magenta vignettes only.

## Conclusion

The main lesson is that v3 was not missing effort but anchoring the wrong thing. It put the shot on the beat and then slowed down, so the part the viewer actually reads, the emblem, drifted late or was cut away. Moving the anchor to the emblem, and banning jumps for 0.5 s after it, fixes most of the "missed beats" complaint without adding any effects. The second lesson is that the reference gets its rhythm from about 36 different shots, which 14 clips with no reuse cannot copy. The remake makes up for that with multi-kill runs where every kill hits a drum, plus punch accents on the syncopated funk hits that carry no kill.

Because the reference has no ACE, the ACE is the one place where this edit can be better than its model. Starting the ACE on the strongest kick in the song (36.03) and landing kill 5 on a big kick (42.96) turns the user's best play into the song's peak. Two answers from the user (which clip is the "clean 3k fade", and whether to end on the ACE) and one 60 fps check of the emblem times are all that stand between this spec and a final render.

[lma]: </home/user/Password/research_notes/Valorant PayPal velocity edit spec/local_media_analysis.md>
[vel]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/pp/velocity.py>
[embv3]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/emb_v3.jpg>
[embref]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/emb_ref.jpg>
[cuts]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/cuts.py>
[map]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/map.py>
[aud]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ref_aud.json>
[refs0]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ref_s0.jpg>
[refs1]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ref_s1.jpg>
[emall0]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/emall0.jpg>
[ev]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ev.jpg>
[ban]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ban.jpg>
[sep10]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/sep10_ace.jpg>
[emsep10]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/em_sep10.jpg>
[ovcrop]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/ov_crop.png>
[left]: </tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad/res/left.jpg>
