# Audio sources

Every sound in the game is either synthesised by our own scripts or a
recording released under **CC0 1.0** (public domain dedication: free for
commercial use, no attribution required). Sources are listed anyway.

## Engine (assets/audio/engine_low.wav, engine_high.wav)

Since 2026-11-24 the game uses its original engine again: two tones
synthesised by our own `tools/audio/make_sfx.py` (first version, commit
e9314f6). No recordings. The CC0 Freesound "Dyno Sessions: 190E" mixes
used from 2026-11-10 to 2026-11-24 are no longer in the game
(`tools/audio/real_engine.py` can still rebuild them).

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
