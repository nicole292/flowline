# FLOWLINE (working title)

Premium endless highway traffic racer for iOS and Android.

**Signature mechanic: Flow.** Passing close to traffic fills your Flow meter.
When it is full, Flow Drive doubles your points until you bump into something.

## Technology

| Choice | Why |
|---|---|
| **Godot 4.7** (GDScript, Mobile renderer) | Free, MIT licence, no royalties or account. Exports to Android and iOS. Small runtime. Can be built, tested and screenshotted from the command line. |
| **Blender 4.3** (Python scripts in `tools/blender`) | All vehicles are generated procedurally: original fictional designs, no licence risk, and each car can be rebuilt after a tweak. |
| Android build | Android SDK (already installed) + the JDK bundled with Android Studio. |
| iOS build | Needs a Mac or a cloud Mac (Codemagic, as with Bubblop) plus an Apple Developer account. |

Rejected options: Unity (needs an interactive account login and licence, and a much heavier toolchain), Flutter/Flame (no real 3D), web/Three.js wrapped in an app (weaker GPU performance on phones).

## Roadmap / checklist

**Stage 1 – Foundation** ✅
- [x] Inspect machine/projects (no existing racing project; `Desktop\Game` is an unrelated React web arcade, left untouched)
- [x] Engine + art pipeline (Godot 4.7.2, Blender-generated cars)
- [x] 5 player cars + 6 traffic types (`assets/vehicles/*.glb`)
- [x] Endless road (world-space shader markings, follows player, rebases every 1200 m)
- [x] Arcade vehicle model: speed-sensitive steering with weight/grip, brakes, body roll/pitch, wheel spin/steer
- [x] Chase camera: lag, speed FOV, accel pull-back, light shake, impact kicks
- [x] Traffic: pooling, lane speeds, car following, signalled lane changes, brake lights, fairness rules
- [x] Crash (slow-mo, spin, flash) → results → restart; pause; auto-pause when app is backgrounded
- [x] 30 headless tests (vehicle, scoring, traffic incl. 2-minute no-clipping soak, save/load)
- [x] Android debug APK builds and runs on the emulator (Vulkan, mobile renderer, landscape)

**Stage 2 – Fun** (in progress)
- [x] Near miss tiers + streaks, overtakes, speed-scaled points
- [x] Flow meter / Flow Drive (x2), screen edge glow
- [x] Synthesised audio: engine with 6-speed gearbox, wind, scrape, whoosh, chimes, crash
- [x] Speed streak FX, haptics on phones
- [ ] Playtest on a real phone and tune steering, density ramp, Flow balance
- [ ] Difficulty ramp beyond density (traffic speed spread, more trucks later)
- [ ] Listen to and tune the generated sounds (untested by ear)

**Stage 3 – Visuals** (first realism pass done, 0.2.0)
- [x] Photographed HDRI sky (lighting + reflections), sun aligned to the photo
- [x] Photo-scanned asphalt/grass/gravel/concrete (normal + roughness maps), worn markings, repair patches, tyre tracks
- [x] Realistic trees: Poly Haven models baked into impostor billboards (`tools/blender/bake_impostors.py`)
- [x] Opposite carriageway with oncoming traffic, median lighting columns, guardrail reflectors
- [x] Sign gantries with readable direction signs, concrete overpass bridges
- [x] Cars: creases, panel gaps, black sills/pillars, layered lights, number plates, door handles, baked AO, bigger wheels
- [x] UI: Barlow font, amber accent, new start screen
- [ ] Cars still look procedural up close (fronts especially) — the biggest remaining realism gap
- [ ] Night / dusk variant, tunnels, rain
**Stage 4 – Systems** (0.3.0)
- [x] Garage: 7 cars (Vanta GT → Vortex), buy, 4 upgrades x 5 levels, paint (14) and rim colours (5)
- [x] Body kits: flares, spoilers/wing, splitter, diffuser fins, vents, intakes, LED lights, two-tone roofs
- [x] Modes: Endless, Two-Way (oncoming lanes, x2 points, +35% cash), Time Trial (checkpoints add time)
- [x] Time of day: Daytime, Golden Hour (LV 3), Night (LV 5) with headlights and lamp pools
- [x] Levels/XP with level-up cash, daily reward streak, rotating missions
- [x] Settings: volumes, buttons/tilt steering, sensitivity, camera, battery saver, km/h or mph
- [ ] Music, more environments (desert, snow), police chase, leaderboards
- [ ] APK is 80 MB: compress the sky photos

**0.4.0 – Driving feel**
- [x] Steering wheel replaces the arrow buttons: drag it round (grab anywhere on the rim), it self-centres, slightly progressive response
- [x] Arrow buttons back for now (with a horn button above them); the wheel is parked in `hud.gd` ("wheel" mode) and not offered in settings
- [x] Car damage: each crash dents the car (harder hits more, about 3 typical hits), the one that takes it to 0% wrecks it and ends the run. Starting a Flow Drive repairs 25%. Distance points halved so near misses matter more; a crash-free run of 1 km+ pays 30% extra cash
- [x] Wheel hub is the horn: the car ahead in your lane signals and moves over if it can
- [x] Gas and brake pedals (thumb can slide between them); "Automatic" accelerator option; desktop defaults to automatic
- [x] Round speedometer with needle, red zone and gear indicator
- [x] Hood camera (Settings > Camera > Hood)
- [x] Realistic acceleration: power falls off with speed; engine braking when you lift off the gas
- [x] Cars: body-coloured C-pillars (no more black box around the rear glass), third brake light, roof antenna, rounded mirrors, smoother tail panels
- [x] New traffic: coach bus

**0.5.0 – Sound and the wreck**
- [x] Smooth engine sound: steady firing-rate harmonics (no random per-pulse jitter or hiss), loops without a seam
- [x] Quiet background music: a 46-second mellow lo-fi loop (pads, electric piano, bass, soft drums), synthesised by `make_sfx.py`; Music slider in Settings; dips during crashes and the pause menu
- [x] Crashes end the run again by default (Settings > Crashes > Keep driving still exists; older saves are switched over once)
- [x] The wreck: slow motion, hard hits flip and tumble the car, sparks/glass/body panels fly, sparks on each landing and while it slides on its roof, engine smoke, the camera circles the wreck, then the results

**0.6.0 – Tilt and views**
- [x] Tilt steering fixed: reads the phone's turn like a wheel (it read the forward/back lean before), centres on how you hold it at the start of a run and after a pause (`scripts/core/tilt_steer.gd`, tested for both sensor sign conventions)
- [x] Tilt works in the web build too: the page feeds `devicemotion` to the game; iPhones are asked for motion access on the first tap after choosing tilt
- [x] WHEEL / TILT switch on the Choose-a-mode screen
- [x] Five camera views (Close, Far, High, Hood, Bumper) and an in-game camera button (or C) that cycles them

**0.6.1 – GYRO**
- [x] Phone-turning steering is called GYRO (setting value stays "tilt" in saves)
- [x] GYRO layout like Traffic Racer: brake pedal bottom-left, gas bottom-right, each half of the screen is one big pedal
- [x] If no motion data arrives for 3 s (desktop, or a page embedded in claude.ai on iPhone), it switches to the arrow buttons and says so
- [ ] Known limit: the claude.ai artifact view gets no motion sensor data, so GYRO only works in an installed app (Android APK; iPhone needs a Mac/Apple developer account)
**Stage 5 – Mobile**: real-device profiling, quality tiers, safe-area check on notched phones, tilt controls.
**Stage 6 – Release**: final name, icon, store assets, privacy policy, release signing, iOS via Codemagic.

## Asset licences

| Asset | Source | Licence |
|---|---|---|
| All vehicles | Generated by `tools/blender/build_cars.py` (original) | Ours |
| All sound effects | Synthesised by `tools/audio/make_sfx.py` (original) | Ours |
| Sky HDRI `assets/env/sky.hdr` | Poly Haven "Kloofendal 48d Partly Cloudy (Pure Sky)" | CC0 |
| Trees `assets/env/trees/*` | Rendered from Poly Haven "Island Tree 02" and "Fir Sapling Medium" | CC0 |
| Textures `assets/env/textures/*` | ambientCG Asphalt031, Grass004, Gravel023, Concrete034 | CC0 |
| UI font `assets/fonts/*` | Barlow Semi Condensed (Google Fonts) | SIL OFL 1.1 (`assets/fonts/OFL.txt`) |
| App icon | Rendered from our own car model | Ours |

## Commands

Godot lives at `C:\dev\godot\Godot_v4.7.2-stable_win64.exe` (open `C:\dev\flowline\project.godot` with it and press F5 to play).

```
G=/c/dev/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . -s res://tests/run_tests.gd                 # tests
$G --path . -- --autopilot --shots=5,15 --shot-prefix=C:/tmp/s --quit-at=20 --bench
$G --path . -- --autopilot --crash-at=6 --shots=6.3,7.2 --shot-prefix=C:/tmp/c --quit-at=11   # see a wreck
$G --headless --path . --export-debug "Android" build/flowline-debug.apk
adb install -r build/flowline-debug.apk && adb shell am start -n com.flowline.game/com.godot.game.GodotAppLauncher
python tools/audio/make_sfx.py [name ...]                           # regenerate sounds (all, or e.g. music)
```

Controls: phone — left thumb steers with the two arrow buttons (the round button above them honks), right thumb works the gas and brake pedals (or set the accelerator to Automatic). Keyboard — A/D or arrows steer, W/Up gas, S/Down/Space brake, H horn, C camera view, Esc pauses. GYRO: choose GYRO on the mode screen and turn the phone like a steering wheel (installed app only).

Rebuild vehicles and preview renders:

```
"C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" -b --factory-startup -P tools/blender/build_cars.py
"C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" -b --factory-startup -P tools/blender/build_cars.py -- --only vanta --no-render
```

## Phone test builds and the website

- `bash tools/build_release.sh` → signed `build/flowline.apk` (arm64).
- The signing key is **outside the repo** in `C:\dev\flowline_keys\` (`flowline-release.jks` + password in `flowline-release.properties`). **Back this folder up** (e.g. to D: like Bubblop's key): without it, future versions cannot install over the old one.
- Website: GitHub Pages from `docs/` → https://nicole292.github.io/flowline/ . The download button points at the latest GitHub Release asset `flowline.apk`, so publishing a new release updates the page automatically.
- Raw downloaded sources (tree models, full texture sets) live in `C:\dev\flowline_raw\` and are not in the repo.

## Known issues

- Package id `com.flowline.game` and the name are placeholders until a final name is chosen.
- No app icon yet (export warns).
- Emulator frame rate is not representative; real-phone performance is untested.
- Screenshot harness causes a ~140 ms frame when it saves a PNG (test-only).

- Cars are procedural: no badges or textures, fronts are still the weakest part.
- Interiors are not modelled; the glass is opaque and tinted dark (cheap on mobile, standard for the genre).
