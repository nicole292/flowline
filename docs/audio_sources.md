# Audio sources

Every sound in the game is either synthesised by our own scripts or a
recording released under **CC0 1.0** (public domain dedication: free for
commercial use, no attribution required). Sources are listed anyway.

## Engine

Settings > Engine chooses one of three sounds (default SPORT):

- **CLASSIC** (`engine_low.wav`, `engine_high.wav`): the game's original
  engine, two tones synthesised by our own `tools/audio/make_sfx.py`
  (first version, commit e9314f6). No recordings.
- **SPORT / MUSCLE** (`engine_real_low.wav`, `engine_real_high.wav`,
  `engine_real_low_off.wav`, `engine_real_high_off.wav`): built by
  `tools/audio/real_engine.py` (`exhaust` for the on-load pair, `offload`
  for the coasting pair) from the Freesound pack **"The Dyno Sessions: 190E"**
  by **Chippy569**, a Mercedes-Benz 190E 2.3-16V on a dynamometer. CC0 1.0.

| Freesound id | Clip | Used for |
|---|---|---|
| 162509 | 19_2500_D6 (exhaust mic) | on-load low layer (~2550 rpm) |
| 162512 | 20_6500_D6 (exhaust mic) | on-load high layer (~6200 rpm) |
| 162510 | 19_2500_4062 (engine-bay mic) | coasting low layer |
| 162508 | 19_2500_Distant | coasting low layer |
| 162513 | 20_6500_4062 (engine-bay mic) | coasting high layer |
| 162511 | 20_6500_Distant | coasting high layer |

Pages: `https://freesound.org/people/Chippy569/sounds/<id>/`

## Exhaust pops (assets/audio/pop_*.wav)

Cut by `tools/audio/real_engine.py pops`.

| Freesound id | Sound | Author | Used for |
|---|---|---|---|
| 797835 | Car Antilag (No cleanup, 32float) | modusmogulus | pop_crackle, pop_1, pop_2 |
| 385935 | S012_Engine_Backfire_Mono | Pól | pop_3 |

Both CC0 1.0.

## Everything else

Synthesised by `tools/audio/make_sfx.py` (horn, chimes, whoosh, crash,
scrape, click, music). Original, no licence needed.

To rebuild the recorded sounds, download the clips above (Freesound
"preview" MP3s are enough) into `build/engine_real/src/` and
`build/engine_real/pops/`, `pip install miniaudio`, then run the script.
