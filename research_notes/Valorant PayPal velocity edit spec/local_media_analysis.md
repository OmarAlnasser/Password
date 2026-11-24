# Local media analysis: reference, v3, clips (Valorant "PayPal" velocity edit)

All findings come from direct analysis of local files in the scratchpad
`S=/tmp/claude-0/-home-user-Password/8b878525-d069-55ae-a36f-4e6ae8e9ca44/scratchpad`.
The tools were ffmpeg contact sheets, 160x90 per-frame stats, librosa 0.10.1 band onsets, and tiles of the kill-emblem region at 4 to 8 fps.
Analysis scripts and images are in `S/res/` (vis.py, aud.py, cuts.py, map.py, ovl2.py, kills.py, ev.py, ban.py, plus *.jpg sheets).
Times are in seconds. Output and reference times share one clock: ref t=0 equals song file `sc00002.wav` at 7.618 s.
Clip times are source-clip seconds and are read from 4 fps tiles, so they are accurate to about ±0.15 s.
Unless stated otherwise, a clip "kill time" below is the time the kill emblem first appears. That is about 0.1 s after the shot.

## 1. Reference: hits vs music, grade, transitions, ending

### Takeaway
The reference has about 36 clip-to-clip cuts, about 27 more cuts inside runs, and about 34 kill-emblem pops. The emblem pops sit on the beat: median offset 0.074 s, mean +0.003 s. The cuts land about 0.06 to 0.13 s before the beat, so a cut comes about 4 to 6 frames early and the kill emblem pops on the beat.
From 22.15 s to 35.9 s it cuts every 2 beats (about 0.92 s), with one kill per shot.
The grade changes by section: a cool/blue intro, a pink-white smoke shot, saturated yellow/red on "YEAH", a yellow flash at 17.0 to 17.25, warm orange from 18 to 23, magenta edge-vignette at 26.5 to 28.25 and 43 to 45.25, and darker scenes around 34 to 36 and 39 to 40. There is no black-and-white section.
It ends with one ordinary kill at 44.12 to 44.25 and a fade to black from 45.4 to 45.6. There is no ACE in the reference.

### Cited Findings
- **Tempo and grid.** librosa gives 129.2 BPM, a beat period of 0.464 s, and 101 beats over 0 to 46.2 s. The grid in grid.json has 83 beats starting at 8.377. The first strong drop hit is at about 8.33 to 8.71 (snare plus hats) — [S/res/ref_aud.json](S/res/ref_aud.json), [S/song/grid.json](S/song/grid.json)
- **Strongest percussive hits** (low-band onset strength, 30 to 120 Hz, which is kick/808):
  - 36.03 (13.7, the strongest in the song), 17.80 (12.1), 10.41 (11.4), 36.93 (9.1), 42.96 (8.7), 20.67 (8.5), 45.27 (8.2), 14.79, 13.85, 28.21, 29.55, 40.67.
  - The strongest snares (1.5 to 5 kHz) are at 30.49, 22.64, 26.80, 8.71, 20.67, 45.27, 12.92, 8.33, 39.96, 27.13, 15.25, 28.65.
  - Loudness (RMS) is low from 0 to 6 s (intro), rises at 6 to 7 s, and dips from 19 to 21 s. That dip is the "PEGA NO MEU HOLY SHIT" breakdown.
  - — [S/res/ref_aud.json](S/res/ref_aud.json)
- **Reference clip-to-clip cuts (36):**
  - 2.78, 5.55, 7.32, 8.25, 9.17, 10.32, 12.00, 13.78, 15.65, 16.93, 17.77, 19.40, 22.15, 23.02, 23.70, 24.40, 25.10, 25.78, 26.72, 27.63, 28.55, 29.48, 30.40, 31.32, 32.25, 33.23, 34.10, 35.93, 36.87, 37.78, 38.70, 40.55, 41.48, 42.40, 43.32, 44.30.
  - Offset to the nearest beat has a mean of −0.100 s: cuts come early.
  - Many cuts sit on a kick or snare 0.03 to 0.09 s after the cut. Examples: 7.32 to kick 7.38, 13.78 to kick 13.85, 17.77 to kick+snare 17.80, 22.15 to kick 22.20, 33.23 to kick+snare 33.26 to 33.29, 44.30 to kick+snare 44.33.
  - — [S/res/map.py output](S/res/map.py)
- **Reference cuts inside runs (27):**
  - 3.05, 7.38, 13.85, 14.13, 14.35, 17.25, 24.17, 24.47, 24.87, 25.55, 26.25, 28.15, 28.78, 28.85, 29.02, 31.38, 31.78, 32.53, 33.63, 36.40, 37.32, 38.25, 39.17, 41.02, 41.93, 43.38, 43.78.
  - Many are on a kick or hat: 7.38 is kick 7.38, 13.85 is kick 13.85, 43.38 is kick+snare 43.38 to 43.40.
  - — [S/res/cuts.py](S/res/cuts.py)
- **Reference kill-emblem pops (34)**, each with its musical event (an offset in brackets is from the hit time to the musical event):

  | Pop time | Musical event (offset) |
  |---|---|
  | 5.62 | beat and snare, on "YEAH" |
  | 7.38 | kick |
  | 9.00 | snare and hat |
  | 10.62 | beat |
  | 11.88 | off-grid |
  | 13.25 | off-grid |
  | 14.12 | snare |
  | 14.75 | kick 14.79 |
  | 17.12 | beat |
  | 18.50 | beat and kick |
  | 22.25 | beat and kick |
  | 23.12 | beat and snare |
  | 23.38 | hat |
  | 24.50 | beat and kick |
  | 25.00 | beat and snare |
  | 25.88 | beat and kick |
  | 26.38 | beat and kick |
  | 27.38 | snare |
  | 28.12 | kick |
  | 29.12 | beat and kick |
  | 29.50 | kick |
  | 30.12 | beat and snare |
  | 30.88 | kick and snare |
  | 32.62 | kick |
  | 32.88 | beat |
  | 34.38 | hat |
  | 34.62 | beat |
  | 37.38 | beat and snare |
  | 38.75 | kick and snare |
  | 39.50 | off-grid |
  | 39.88 | snare |
  | 40.12 | beat and snare |
  | 41.62 | beat and kick |
  | 44.12 | kick |

  53% of pops are within 0.08 s of a beat, and most of the rest are on a kick, snare or hat — [S/res/emb_ref.jpg](S/res/emb_ref.jpg), [S/res/map.py](S/res/map.py)
- **Vocal / word mapping (on-screen lyric words follow the vocal syllables):**

  | Time | Word(s) |
  |---|---|
  | 0.5–1.75 | TETO |
  | 3.0–4.25 | PAYPAL |
  | 5.5–6.75 | YEAH / AH / YEAH |
  | 7.0 | FIZ |
  | 7.5 | UM SHOW |
  | 7.75 | SOLD |
  | 8.0 | OUT |
  | 8.25–8.75 | ENTROU NA |
  | 9.0 | MINHA CONTA |
  | 9.5 | NO |
  | 9.75 | PAYPAL |
  | 10.25 | GRANA |
  | 10.75 | AINDA |
  | 11.0 | ME TIRAR |
  | 11.5 | DESSA LAMA |
  | 12.0 | ESSA |
  | 12.25 | BITCH |
  | 12.5 | NÃO |
  | 12.75 | QUER |
  | 13.0 | AMOR |
  | 13.5 | BANANA |
  | 13.75 | EU |
  | 14.25 | DINHEIRO |
  | 14.75 | NA |
  | 15.0 | CAMA |
  | 15.25 | VAI |
  | 15.75 | FURO |
  | 16.25 | ATRAVÉS |
  | 16.5 | DA |
  | 16.75 | PAREDE |
  | 17.0 | COM |
  | 17.25 | REAL |
  | 17.5 | NÃO |
  | 18.0 | DE FRENTE |
  | 20.25 | PEGA |
  | 20.75 | NO |
  | 21.0 | HOLY |
  | 21.5 | SHIT |
  | 22.25 | UP |
  | 22.5 | THE |
  | 22.75 | SMOKE |
  | 23.0 | SÓ |
  | 23.5 | BALÃO |
  | 26.75 | CUP |
  | 29.75–34.5 | ad-libs "AHN" at 29.75, 31.75, 33.5, 34.25 |
  | 30.75 | ENTRA |
  | 32.5 | DIZ |
  | 33.0 | QUE É MINHA |
  | 35.25 | SOU |
  | 35.5 | TETINHO |
  | 38.75 | NO MEU |
  | 39.0 | PESCOÇO |
  | 39.75 | EU TAVA |
  | 40.25 | PERDIDO |
  | 40.75 | MAS DISSO |
  | 41.5 | LEMBRO |

  — [S/res/ref_s0.jpg](S/res/ref_s0.jpg), [S/res/ref_s1.jpg](S/res/ref_s1.jpg)
- **Hit counts.**
  - Reference: about 63 cuts (36 between clips and 27 inside runs), 34 kill pops, and 15 white flashes.
  - The flashes are at 7.32, 9.17, 12.0, 14.35, 19.45, 22.15, 24.87, 24.92, 25.55, 28.55, 28.8, 36.87, 36.92, 43.38 and 44.3. They are almost all on clip cuts, not on every kill.
  - A sharpness dip (zoom or motion blur) occurs at nearly every cut, 59 in total. Transitions are whip / zoom-blur cuts.
  - — [S/res/cuts.py](S/res/cuts.py)
- **Reference grade per section.** Per-second means of luma Y, saturation S, R−B and green minus magenta; per-second minimum saturation never drops below 51 except in the fades:

  | Section | Look | Measured values |
  |---|---|---|
  | 0–2.78 | Cool/blue dome shot | R−B −15 to −26, S about 93 to 100 |
  | 2.78–5.55 | Bright pink-white smoke | Y 135 to 149, S 78 to 88 |
  | 5.55–7.32 | Saturated yellow/red swirl on "YEAH" | S 126 to 153, R−B +45 to +83 |
  | 7.3–16.8 | Mostly neutral to slightly warm | S 77 to 114 |
  | 16.9–17.8 | Full-frame yellow flash frames at 17.0 to 17.25 | S 156 to 163, R−B +86 to +90 |
  | 18–23 | Warm orange (red lyric text) | R−B +38 to +72 |
  | 26.5–28.25 and 43.0–45.25 | Magenta edge vignette, also faintly at 14.25 | — |
  | 34–36 and 39–40 | Darker shots | Y 63 to 73 |
  | 42–44 | Saturated | S 127 to 138 |
  | 45.4–45.6 | Fade to black | — |

  — [S/res/cuts.py](S/res/cuts.py), [S/res/map.py](S/res/map.py)
- **Reference ending.** The last cut is at 44.30 (on kick+snare 44.33). There is one kill pop at 44.12 to 44.25, the emblem holds to about 45.4, then the picture fades to black at 45.5. No ACE banner appears — [S/res/emb_ref.jpg](S/res/emb_ref.jpg), [S/res/ref_s1.jpg](S/res/ref_s1.jpg)

### Inferences
- The reference's rule is "cut slightly before the beat; the kill emblem lands on the beat". It uses one kill per shot from 22 s on, so its rhythm comes from many short shots. With 14 clips and no reuse we cannot copy that density. Runs with several kills each, every kill on a beat, are the substitute.
- The breakdown (19.4 to 22.15) is one longer shot in the reference, and the biggest drop hit is 36.03. These are the two places where a slow-motion hold and a hard re-entry pay off.

### Gaps
- Separating 808 from kick: a 30 to 120 Hz onset detector cannot tell them apart. Vocal-chop onsets came only from the on-screen words, not from source separation.
- The reference's own source footage was not identified. Its gun skins and emblems (skull, heart, lion) differ from the user's clips, so it is a different player's footage.

## 2. v3: missed hits, reuse, grade, overlay

### Takeaway
v3 has 19 runs and plans 34 kill beats, and its planned kills sit on beats (88% within 0.08 s). But only about 22 kill emblems ever show on screen, and many appear 0.4 to 0.7 s after the beat or not at all.
The cause has two parts:
- velocity.py maps (kill − LEAD) to the beat and then plays 0.15x slow motion. The emblem therefore appears (0.1 + 0.15 s + error) / 0.15 later.
- The whip jump at about kill + 0.3 s often cuts away before the emblem appears.

Several RUNS kill times are also 0.25 to 0.5 s too early compared with the real emblem times.
v3 reuses 5 clips and splits the sep10 ACE across two places. Its grade has a heavy magenta intro and over-saturated orange at 36 to 41. It flashes on every kill: 33 flashes against the reference's 15.
The MOMENTS / "CAPTURED WITH steelseries" overlay is visible in v3 at about 7.6–8.3, 10.3–11.0, 15.65–18.4 (whole sep08 and nov21 runs), 18.4–19.3 and 30.4–31.0.

### Cited Findings
- **v3 plan and source ranges** (from `velocity.py plan`; output range, clip, source range, kill beats):

  | Output | Clip | Source | Kill beats | Note |
  |---|---|---|---|---|
  | 0–5.55 | nov14 | 6.30→9.07 at 0.5x | none | Kill-5.75 emblem lingers at 0 to 2.6 with no hit |
  | 5.55–7.32 | sep10 | 10.95→12.70 | none | ACE kill-2 emblem lingers at 5.62 to 5.75 |
  | 7.32–9.17 | sep17 | 2.77→5.38 | 8.38, 8.76 | Jump at 8.55 |
  | 9.17–10.32 | oct04 | 9.34→10.46 | 9.79 | Source ends before the real emblem at 10.75, so the kill never shows |
  | 10.32–12.00 | sep06 | 3.37→5.07 | 10.73, 11.31 | — |
  | 12.00–13.78 | sep05b | 6.34→11.33 | 12.62, 13.46 | — |
  | 13.78–15.65 | oct04b | 4.87→13.10 | 14.38, 15.30 | — |
  | 15.65–16.85 | sep08 | 0.63→1.76 | 16.24 | — |
  | 16.85–18.40 | nov21 | 0.75→2.09 | 17.16, 18.07 | — |
  | 18.40–24.30 | n01 | 1.91→20.81 | 18.97, 21.14, 23.62 | Source speed goes to −101 (backwards) |
  | 24.30–26.30 | sep21 | 6.26→8.12 | 24.98, 25.92 | — |
  | 26.30–28.50 | sep08c | 4.97→13.36 | 26.82, 27.77 | — |
  | 28.50–30.40 | sep05 | 4.05→13.33 | 29.15, 30.08 | — |
  | 30.40–33.60 | sep11 | 2.12→19.88 | 4 kills | — |
  | 33.60–36.40 | nov14 | 37.09→43.35 | 3 kills | Source speed −13 |
  | 36.40–38.80 | sep06 | 20.20→22.78 | 37.9 | — |
  | 38.80–41.00 | oct04b | 15.33→17.68 | 40.2 | — |
  | 41.00–42.40 | sep08c | 14.56→16.11 | 42.03 | — |
  | 42.40–46.48 | sep10 | 20.41→34.59 | 42.97, 43.91, 44.86 | — |

  — [S/pp/velocity.py](S/pp/velocity.py)
- **Clip reuse in v3:**
  - nov14 at 0–5.55 and 33.6–36.4
  - sep10 at 5.55–7.32 (the ACE kill-2 moment, src 10.95) and 42.4–end (only ACE kills 3 to 5 are shown, so the ACE never reads as 5 kills)
  - sep06 at 10.32–12.0 and 36.4–38.8
  - oct04b at 13.78–15.65 and 38.8–41.0
  - sep08c at 26.3–28.5 and 41.0–42.4

  — [S/pp/velocity.py](S/pp/velocity.py)
- **Kill emblems actually visible in v3 (22):** 8.62, 11.0, 12.62, 13.62, 15.5, 16.62, 17.62, 21.12, 23.0, 23.12, 25.0, 25.38, 28.25, 32.88, 33.25, 35.88, 38.38, 40.62, 40.75, 43.0, 43.88, 44.75. That is against 34 planned kill beats.
- **Planned kill beats with no emblem near the beat:**
  - 9.79 (oct04), 14.38, 15.30, 18.07, 18.97, 23.62
  - 26.82 (the emblem shows at 28.25, much later), 27.77, 29.15, 30.08 (sep05 kills cut away by the jump at 29.45)
  - 31.00, 31.46, 32.37 (sep11 shows its emblem only at 32.88 to 33.5)
  - 34.22, 35.14 (nov14 emblem only at 35.88)
  - 37.9 (emblem at 38.38, +0.48 late), 40.2 (emblem at 40.62, +0.42), 42.03

  — [S/res/emb_v3.jpg](S/res/emb_v3.jpg), [S/res/map.py](S/res/map.py)
- **Root cause in code:** `ks = [k - LEAD for k in run[3]]` with LEAD=0.10, followed by `SLOW_V=0.15` slow motion for 0.30 s after each kill. The whip jumps are at kill + 0.3 s (8.55, 12.92, 14.68, 19.27, 21.44, 27.12, 29.45, 31.21, 31.76, 32.59, 34.52, 35.44, 43.27, 44.21). 10 of those 14 jumps are off the beat grid — [S/pp/velocity.py](S/pp/velocity.py), [S/res/map.py](S/res/map.py)
- **v3 RUNS kill times vs measured emblem onsets (RUNS → measured):**

  | Clip | RUNS | Measured |
  |---|---|---|
  | oct04 | 10.25 | 10.75 |
  | sep17 | 4.25, 5.25 | 4.5, 5.2, 5.9 |
  | nov21 | 1.25, 2.00 | 1.5, 2.7, 3.45 |
  | sep08c | 13.00 | 13.25 |
  | oct04b | 5.75 / 13.00 / 17.25 | 6.0 / 13.25 / 17.5 |
  | n01 | 2.75, 19.75, 20.50 | 3.0, 19.5, 20.5 |
  | sep11 | 3.00, 7.25, 11.75 | 3.5, 7.5, 12.0 |
  | sep06 | 22.25 | 22.5 |
  | nov14 | 38.00, 42.75, 43.25 | 38.25, 43.0, possibly 43.5 |
  | sep10 | 34.25 | 34.0 |

  — [S/res/ev.jpg](S/res/ev.jpg), [S/res/emall0-3.jpg](S/res/emall0.jpg)
- **v3 cuts and flashes.**
  - 64 histogram cuts, which include the in-run jumps.
  - 33 white flashes, one per kill: 8.38, 8.55, 9.8, 10.32, 10.73, 11.23, 13.78, 14.4, 15.32, 16.25, 17.17, 18.07, 18.98, 21.15, 23.63, 25.0, 25.93, 26.83, 27.77, 29.17, 30.08, 31.0, 31.47, 32.38, 32.6, 32.9, 34.23, 34.53, 35.15, 40.2, 42.98, 43.92, 44.87.
  - The reference has 15 flashes, placed on cuts.
  - Of v3's 18 clip-to-clip cuts, 5 are off-grid (15.65, 28.5, 30.4, 33.6, 42.4).
  - — [S/res/cuts.py](S/res/cuts.py), [S/res/map.py](S/res/map.py)
- **v3 grade is not constant, and differs from the reference:**

  | v3 section | v3 values | Reference at the same time |
  |---|---|---|
  | 0–6 (intro) | S 104 to 138, green minus magenta −34 to −54 (heavy magenta/pink) | Cool blue, R−B −15 to −26 |
  | 7–35 | Mostly neutral, S 68 to 113 | Warm orange at 18 to 23, yellow flash at 17 |
  | 36–40.5 | S 153 to 200, R−B +60 to +112 (blown-out orange; sep06 and oct04b wood rooms through the per-clip gain) | — |

  The magenta edge vignette appears only at 10.5, against 26.5 to 28.25 and 43 to 45.25 in the reference — [S/res/cuts.py](S/res/cuts.py), [S/res/map.py](S/res/map.py)
- **Overlay in v3.**
  - Template matching finds "MOMENTS" at 7.6–8.3, 10.4–11.0, 19.2 and 28.6.
  - The orange "CAPTURED WITH steelseries" bar is at 15.7–18.1.
  - The contact sheet also shows the overlay at 18.5–19.0 (n01) and 30.5–31.0 (sep11).
  - It occurs wherever a run uses source time below 4.3 s: sep17, sep06, sep08, nov21, n01, sep11 and sep05.
  - — [S/res/v3_s0.jpg](S/res/v3_s0.jpg), [S/res/v3_s1.jpg](S/res/v3_s1.jpg), ovl2/v3 template scan
- **Overlay geometry.** The overlay is the same in all 14 clips and appears only in source time 0 to about 4.3 s:
  - 0 to about 1.5 s: an orange "CAPTURED WITH steelseries" bar.
  - About 2 to 4.25 s: a dark "⬡ MOMENTS ·GG" box.
  - Both sit at the left edge, lower-middle of the frame, not at the top.
  - Measured at 1920x1080: the dark box is x 0–300, y 760–840. The text "MOMENTS·GG" is about x 32–272, y 785–830. The template's best-match top-left is (18, 780).
  - At 2560x1440 (nov14, nov21) scale by 4/3: box x 0–400, y 1013–1120.
  - Recommended mask/crop: x 0–330, y 750–850 at 1080p, or x 0–440, y 1000–1135 at 1440p. Alternatively, never use source time before 4.4 s.
  - The top-left "gear" is the Valorant minimap, not a watermark. A static "Client FPS / Packet Loss" text strip runs along y 4–18, x 16–1525 at 1080p.
  - — [S/res/ov_crop.png](S/res/ov_crop.png), [S/res/tl.jpg](S/res/tl.jpg), [S/res/left.jpg](S/res/left.jpg), ovl2.py output

### Inferences
- Fixes:
  - Put the measured emblem time, not the shot time minus LEAD, on the beat. Or start slow motion only after the emblem pops.
  - Never jump within about 0.5 s of source time after an emblem pop.
  - Place in-run jumps on hats, snares or beats.
  - Flash on cuts, not on every kill.
  - Remove all clip reuse.
  - Show all 5 ACE kills in one run.
  - Mask or avoid source time below 4.4 s.
  - Replace the per-clip auto-gain with a section-based grade.

### Gaps
- Some emblems in v3 may be partly hidden by zoom-blur, so the visible count of 22 is from 8 fps tiles and could be off by ±2.

## 3. Clips: durations, kills, multi-kills, banners, overlay, best segments

### Takeaway
There is one real ACE: sep10. It has 5 kills plus an "ACE" banner (player "Balerion") at 34.0 to 35.75.
- sep17 is the cleanest 3K: 4.5, 5.2 and 5.9, then a "WON / ENEMY TEAM ELIMINATED" banner at 7.6. It is the best candidate for the "clean 3k".
- sep05b is a 3K clutch: 7.25, 11.5, 13.0, then a "CLUTCH" banner at 13.25 to 13.4.
- sep21 and nov21 are quick 4Ks.
- sep21 also has an "ACE" banner at 24.75, but it belongs to the enemy player "Clove" after the user died ("KILLED BY CLOVE", spectating). Do not use it.

The Drive folder holds exactly the same 14 clips plus a byte-identical duplicate of sep08 (13,102,368 bytes). It contains no unused clips. n01 is titled "end it here" in Drive.

### Cited Findings
- **Drive folder "AI" (1QSVtWsr…) has 15 videos:**
  - Moments-clip-from-Nov-14 = nov14
  - Nov-21 = nov21
  - "end it here " = n01, id 1y7v8D3h…
  - Sep-05 (1) = sep05b
  - Sep-05 = sep05
  - Sep-08 (1), id 1QtkspWE…, 13,102,368 bytes = the same size as sep08, so a duplicate
  - Sep-08 (1), id 1a0JL1hl… = sep08c
  - Sep-06, Sep-08, Sep-10, Sep-11, Sep-17, Sep-21, Oct-04 (1) = oct04b, Oct-04

  Drive search found no other clips with "3k", "ace", "fade" or "clean" in the title — [Google Drive folder listing](https://drive.google.com/drive/folders/1QSVtWsr_x8ChUeyk1qzkqG7zMAQf-PSf), [S/ids.txt](S/ids.txt)
- **Per-clip inventory.** Kill times are emblem onsets ±0.15. "Overlay" is the MOMENTS / CAPTURED toast at source 0 to 4.3 s in every clip.

| Clip | Res, dur | Kill emblem times | Multi / banner | Best usable segment |
|---|---|---|---|---|
| sep10 | 1080p, 36.0 | 9.25, 10.5, 21.25, 31.25, 34.0 | **5K ACE**; "ACE – Balerion" banner 34.0–35.75; Cypher spray 34.6 | 8.5–36.0, compressing the 12.5–21 and 22.8–31 walking gaps |
| sep17 | 1080p, 7.98 | 4.5, 5.2, 5.9 | **3K in 1.4 s**, "WON" 7.6 | 3.6–7.98 (overlay ends 4.3) |
| sep05b | 1080p, 15.8 | 7.25, 11.5, 13.0 | 3K **CLUTCH** banner 13.25–13.4 | 10.4–15.0 (or 6.5–15) |
| sep21 | 1080p, 25.1 | 7.25, 8.25, 10.0, 12.25 | **4K** in 5 s; dies later; enemy "ACE – Clove" at 24.75 (avoid) | 6.3–13.5 |
| nov21 | 1440p, 14.8 | 1.5, 2.7, 3.45, 8.5 | **4K**, first 3 in 2 s | 0.6–4.6 (mask overlay) or 0.6–9.0 |
| oct04 | 1080p, 19.2 | 10.75, 12.0, 15.0, 16.75 (fire finisher) | 4K-ish; "LOST / TEAM ELIMINATED" 17.25 (avoid after 17.1) | 10.0–17.0 |
| oct04b | 1080p, 21.9 | 6.0, 13.25, 17.5, 20.25 | 4 kills spread | 12.4–21.0 |
| sep06 | 1080p, 27.65 | 4.0, 4.75, 9.25, 22.5 | 2K at 4.0/4.75 | 3.2–10.0 (mask) or 21.6–23.5 |
| sep08c | 1080p, 21.06 | 5.75, 13.25, 15.25, 16.0 (8.75 unverified) | 3K in 2.75 s; "WON" 20.75 | 12.4–17.5 (+20.75 WON) |
| sep11 | 1080p, 30.4 | 3.5, 7.5, 12.0, 19.5 (8.75 unverified) | 4 kills; scoreboards 22–23, 28–29.5 | 2.6–20.5 |
| nov14 | 1440p, 47.0 | 5.75, 16.0, 38.25, 43.0 (43.5?) | Singles plus a late pair; pink smoke 6.3–9.5 | 4.4–9.5 (smoke intro), 37.4–44.5 |
| n01 ("end it here") | 1080p, 28.9 | 3.0, 19.5, 20.5 | 2K at 19.5/20.5; scoreboard/death from 25.0 | 18.6–24.5 |
| sep05 | 1080p, 57.7 | 5.0, 13.25, 14.5?, 35.5, 49.25 | Mostly singles; scoreboard 53–57 | 12.4–15.0, 34.6–37, 48.4–51 |
| sep08 | 1080p, 5.12 | 1.6 | Single; yellow arc 1.5–1.75 (entire clip is inside overlay time) | 0.6–3.4 (must mask) |

— [S/res/emall0.jpg](S/res/emall0.jpg)–[emall3.jpg](S/res/emall3.jpg), [S/res/ev.jpg](S/res/ev.jpg), [S/res/em_sep10.jpg](S/res/em_sep10.jpg), [S/res/ban.jpg](S/res/ban.jpg), [S/res/full9.jpg](S/res/full9.jpg), [S/res/sep10_ace.jpg](S/res/sep10_ace.jpg)
- **ACE banner** at 1080p is about x 710–1210, y 136–325, top centre. The only clip-level matches are sep10 at 34.0–35.75 (score 1.0) and sep21 at 24.25–24.75 (enemy ACE). The other banners found:
  - "CLUTCH": sep05b 13.25
  - "WON": sep17 7.6, sep08c 20.75
  - "LOST": oct04 17.25

  — [S/res/ban.py](S/res/ban.py), [S/res/ban.jpg](S/res/ban.jpg)
- **Emblem escalation.** In sep10 the emblem visibly grows at each kill (1 to 5), and the kill-5 emblem is a white / red-burst ACE emblem. Other clips show a red / green / blue ring flare at each new kill — [S/res/em_sep10.jpg](S/res/em_sep10.jpg), [S/res/ev.jpg](S/res/ev.jpg)

### Inferences
- The "clean 3k" is most likely sep17: three kills in 1.4 s, then WON, a short clip with no clutter. sep05b (3K plus CLUTCH) is the second candidate.
- "fade" could mean the agent Fade or a fade-out ending. The agent could not be confirmed from the frames.
- The Drive title "end it here" on n01 suggests the user wants n01 as the closing shot. It fits after the sep10 ACE as a 2-kill tag.

### Gaps
- Kill counts for oct04, oct04b, sep11 and nov14 come from emblem flares. The emblem tick counts were not legible at the resolution used.
- The sep05 window 40 to 45 s was not fully inspected.
- An "ACE" in nov14 or another clip that shows no banner cannot be ruled out, but none showed a 5th escalating emblem.
- The agent per clip was not identified.

## 4. Recommended timeline (one clip per run, no reuse, every kill emblem on a beat)

### Takeaway
14 runs use all 14 clips once:

| Run | Out time | Clip | Source | Kill emblem → beat (out time) | Note |
|---|---|---|---|---|---|
| R1 | 0.00–5.55 | nov14 | 4.4→ about 9.5, 0.5 to 0.9x | none | Pink-smoke intro; keep the kill-5.75 emblem off screen, or land it on the 5.55 cut. Grade cool/neutral to match the reference |
| R2 | 5.55–7.32 | sep08 | 0.6→3.0 | 1.6 → 5.64 (beat+snare, "YEAH") | Yellow arc; mask overlay; yellow/red grade |
| R3 | 7.32–9.17 | sep17 | 3.7→7.98 | 4.5 → 7.48, 5.2 → 7.94, 5.9 → 8.38 (drop) | Hold slow motion; WON banner 7.6 → about 8.9 |
| R4 | 9.17–12.00 | oct04 | 10.0→15.3 | 10.75 → 9.80, 12.0 → 10.68, 15.0 → 11.59 | Speeds 1.4x, then 3.3x |
| R5 | 12.00–13.78 | sep05b | 10.6→13.6 | 11.5 → 12.52, 13.0 → 13.44 | CLUTCH banner held into 13.78 |
| R6 | 13.78–17.77 | sep21 | 6.3→13.5 | 7.25 → 14.40, 8.25 → 14.84 (kick 14.79), 10.0 → 15.77, 12.25 → 16.70 | Slow hold to the 17.80 kick; yellow flash at 17.0–17.25 as in the reference |
| R7 | 17.77–19.40 | nov21 | 0.8→4.6 | 1.5 → 18.07, 2.7 → 18.53, 3.45 → 18.97 | Mask overlay at 1440p |
| R8 | 19.40–22.15 | sep11 | 2.6→12.5 | 3.5 → 19.43, 7.5 → 20.67 (kick+snare), 12.0 → 21.80 | Breakdown; warm/orange grade; mask before 4.3 |
| R9 | 22.15–25.94 | sep06 | 3.3→10.0 | 4.0 → 22.25, 4.75 → 22.69 (snare 22.64), 9.25 → 24.52 | Mask overlay |
| R10 | 25.94–29.62 | oct04b | 12.4→21.0 | 13.25 → 26.84 (snare 26.80), 17.5 → 28.24, 20.25 → 29.16 | Magenta edge vignette 26.5–28.25 |
| R11 | 29.62–33.30 | sep08c | 12.4→20.9 | 13.25 → 30.49 (top snare), 15.25 → 31.46, 16.0 → 31.93 | WON banner around 33.0 |
| R12 | 33.30–36.03 | sep05 | 12.4→15.5 or 34.6→37 | 13.25 → 33.79, 14.5 → 34.23, or 35.5 → 34.69 | — |
| R13 | 36.03–44.30 | sep10 ACE | 8.5→36.0 | 9.25 → 36.06 (strongest kick 36.03), 10.5 → 36.93 (kick), 21.25 → 38.85, 31.25 → 40.67 (kick), 34.0 → 42.96 (kick) | Ramps of about 5.5x through the walking gaps; ACE banner held 42.96–44.30 |
| R14 | 44.30–46.48 | n01 ("end it here") | 18.6→21.5 | 19.5 → 44.84, 20.5 → 45.27 (big kick+snare) | Slow motion, then fade to black from 45.4. Magenta vignette 43–45.25 |

That gives about 37 on-beat kill hits, against about 34 in the reference and about 22 actually visible in v3.

### Cited Findings
- The beat, kick and snare times used above come from the librosa analysis of ref.wav — [S/res/ref_aud.json](S/res/ref_aud.json)
- The clip kill times come from the emblem tiles — [S/res/ev.jpg](S/res/ev.jpg), [S/res/emall0.jpg](S/res/emall0.jpg)
- The section boundaries are the reference's own cut points: 2.78, 5.55, 7.32, 9.17, 12.00, 13.78, 17.77, 19.40, 22.15, 35.93/36.03 and 44.30 — [S/res/cuts.py](S/res/cuts.py)

### Inferences
- Use the emblem time, not shot − LEAD, as the beat anchor.
- Start each run with its cut 0.06 to 0.1 s before the beat, like the reference.
- Keep at least 0.5 s of source after each emblem before any jump.
- Flash only on cuts.
- Per-run source speeds in this plan stay within about 0.5 to 5.5x. The only fast stretches are the sep10 walking gaps (about 5.5x) and the oct04b first ramp (about 3x).

### Gaps
- Exact kill frames are only ±0.15 s from 4 fps tiles. A 60 fps pass on each chosen emblem onset is needed before rendering.
- R12 (sep05) relies on a 14.5 kill that is not fully confirmed.
- Whether the user prefers the sep10 ACE as the very last shot over n01 ("end it here") is unknown. The plan above uses both.
