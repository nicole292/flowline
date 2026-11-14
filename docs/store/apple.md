# FLOWLINE on the App Store

Everything to paste into App Store Connect. Screenshots are in `docs/store/apple/`.

## New app (Apps → + → New App)
| Field | Value |
|---|---|
| Platform | iOS |
| Name | FLOWLINE: Near-Miss Drive |
| Primary language | English (U.S.) |
| Bundle ID | com.elishakov.flowline |
| SKU | flowline-ios-001 |
| User access | Full access |

## App Information
| Field | Value |
|---|---|
| Subtitle (max 30) | Fill the Flow, score double |
| Category | Games, subcategories Racing and Arcade |
| Secondary category | (none) |
| Content rights | Yes, it contains third-party content, and I have the rights (free CC0 textures and sky from Poly Haven and ambientCG, CC0 MakeHuman body) |
| Age rating | Every question "None" / "No" (no violence against people, no ads, no chat, no web access, no gambling, no purchases). Result: 4+ |
| Privacy policy URL | https://nicole292.github.io/flowline/privacy.html |

## App Privacy
Get Started → "No, we do not collect data from this app" → Publish. Label: **Data Not Collected**.

## Pricing and Availability
Price: Free (0). Availability: all countries.

## Version page (1.0 Prepare for Submission)

**Promotional text** (max 170):
Close passes fill your Flow meter. Fill it and every point counts double, until you bump. Bends, tunnels, crash sites and a real cockpit view. No ads, no accounts.

**Description** (max 4000):
FLOWLINE is a driving game about one thing: the close pass.

Every time you slip past a car with centimetres to spare, your Flow meter fills. Fill it and Flow Drive starts: every point counts double until the next time you touch another car. So you're not just driving fast, you're choosing how close to cut it.

FLOW, NOT GAME OVER
• Near misses fill the Flow meter. The closer the pass, the more it fills.
• Flow Drive doubles every point until your next bump.
• Bumps dent your car and break your Flow, but the run goes on. A full wreck ends it.

A ROAD THAT CHANGES
• Long sweeping bends and tunnels with their own lighting.
• Crash sites ahead: police, cones and smoke close a lane, and traffic squeezes over.
• Day, sunset and night.

SIT INSIDE THE CAR
• A full cockpit view: dashboard, lit dials and centre screen, your hands turning the wheel.
• A working rear-view mirror that shows the traffic behind you.
• Choose your hands' skin tone in Settings.

THREE WAYS TO PLAY
• Endless: how long can you keep the Flow going?
• Two-way: oncoming traffic on the left. Pass on the wrong side for big points.
• Time attack: race the clock from checkpoint to checkpoint.

CARS AND MOTORBIKES
• Cars and motorbikes, each with its own handling. Bikes lean into the turns.
• Upgrade engine, brakes and handling. Paint, rims and your own number plate.
• Steering wheel, arrows or gyro steering. Chase, top and cockpit cameras.

No ads. No purchases. No accounts. No data collected. Plays offline.

**Keywords** (max 100, commas, no spaces; words already in the name are left out):
flow,traffic,car,driving,motorbike,cockpit,tunnel,arcade,offline,endless,overtake,racing,highway

| Field | Value |
|---|---|
| Support URL | https://nicole292.github.io/flowline/ |
| Marketing URL | https://nicole292.github.io/flowline/ |
| Copyright | 2026 Elishakov Studio |
| iPhone 6.9" screenshots | `iphone-69-1.png` … `iphone-69-6.png` (2868 × 1320, landscape). Order matters: 1 Flow Drive, 2 cockpit with mirror, 3 bend with crash site warning, 4 tunnel, 5 motorbike, 6 garage |
| iPhone 6.3" screenshots | `iphone-63-1.png` … `iphone-63-6.png` (2556 × 1179), same order |
| iPad 13" screenshots | `ipad-13-1.png` … `ipad-13-6.png` (2732 × 2048, landscape). Needed since build 17: the game now runs full-screen on iPad. 1 Flow Drive, 2 cockpit, 3 crash site warning, 4 tunnel, 5 bend, 6 garage |
| Build | the one Codemagic uploaded ("iOS release (TestFlight)") |

**App Review Information**
- Sign-in required: No
- Contact: your name, phone and elishakov.studio@gmail.com
- Notes (rewritten 2026-11-05 after the Guideline 2.1 "Information Needed" reply; replace the link placeholder):

```
SCREEN RECORDING (physical iPhone 13 Pro, iOS 26.7.2; recording starts at app launch):
<paste video link here>

1. PURPOSE AND AUDIENCE
FLOWLINE: Near-Miss Drive is an offline arcade driving game for casual players aged 4+ (racing fans, short play sessions). You weave a car or motorbike through highway traffic; close passes fill a "Flow" meter that doubles your points. It offers quick, skill-based entertainment that works anywhere without a connection.

2. HOW TO USE THE APP
No account, login or setup is needed. Launch the app and tap PLAY.
- Steering: on-screen steering wheel, arrow buttons, or GYRO (tilt the phone); choose it on the mode screen or in Settings. Gas and brake pedals are on screen.
- Bumping into traffic dents the car but does not end the run. To finish a run tap Pause, then End run, to see the results.
- Coins earned while driving are spent in the Garage on cars, motorbikes, upgrades, paint, rims and a custom number plate.
- Modes: Endless, Two-way, Time attack. Cameras: chase, top, cockpit.
There is no account system (so no account deletion is needed), no user-generated content, no chat, no ads and no in-app purchases. All content is free and unlocked by playing.

3. EXTERNAL SERVICES
None. The app makes no network requests and uses no third-party SDKs, analytics, ads, authentication, payments or AI services. It is built with the open-source Godot Engine. Progress is saved only on the device. The only device permission used is the motion sensor, for optional gyro steering.

4. REGIONAL DIFFERENCES
None. The app works the same in all regions. It is in English only.

5. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not a regulated industry. The game contains no licensed brands, real car makes or protected third-party material. All cars and bikes are original models. Bundled free assets: Poly Haven sky and trees (CC0), ambientCG textures (CC0), MakeHuman base body (CC0), Barlow font (SIL Open Font License), engine and exhaust sound recordings from Freesound (CC0; sources listed in the project's docs/audio_sources.md).
```

- Screen recording for review: on the iPhone (latest iOS, TestFlight build), Control Center screen recording. Start on the home screen, tap the icon, PLAY, drive ~40 s with near misses and one bump, Pause → End run, Garage purchase with earned coins, switch to GYRO and drive a few seconds. Upload unlisted (YouTube) or Drive "anyone with the link".

**Version release**: Manually release this version (you choose the day after approval).

## Export compliance
Already answered inside the app (ITSAppUsesNonExemptEncryption = NO), so App Store Connect won't ask.

## Guideline 4.3(a) "Spam" rejection (2026-11-14)
Apple matched the app to the many template traffic racers. What changed for the resubmission: build 14 (fix: after a wreck on a bend the next run started with the car tilted), new name/subtitle/description/keywords above, new screenshots that lead with what no template has (Flow Drive, cockpit with live mirror, bends, tunnels, crash sites), a more detailed car interior.

Reply to paste under the rejection in App Store Connect (App Review message):

```
Hello, and thank you for the review.

FLOWLINE is not built from a template, purchased code or another app. It was written from scratch in the open-source Godot Engine, and no other app, ours or anyone else's, shares its code or assets. The full development history is public: https://github.com/nicole292/flowline

All 3D cars, motorbikes, riders and the car interior are original models generated by our own Blender scripts. Sounds are our own mixes of CC0 recordings. No asset packs or template art are used.

We know highway driving is a popular genre, so here is what FLOWLINE does that others don't:

1. Flow Drive: close passes fill a Flow meter. When it's full, points double until your next bump, so the game rewards precise, risky driving rather than raw speed.
2. Bumps don't end the run. They dent the car and break your Flow, and you keep driving.
3. A living road: real bends and tunnels with lighting changes, and crash sites with police, cones and smoke that close lanes and make traffic move over.
4. A full cockpit view: dashboard, lit dials, centre screen, modelled hands that turn the wheel (skin tone selectable), and a working rear-view mirror showing the traffic behind you.
5. Cars and motorbikes with different handling (bikes lean), three steering styles (wheel, arrows, gyro), and three modes including Two-way and Time attack.
6. Garage with upgrades, paint, rims and a custom number plate you type yourself.
7. No ads, no purchases, no accounts, no data collected. Fully offline.

With this resubmission we also changed the name, subtitle, description and screenshots so the store page shows these features first, and uploaded build 14, which fixes a bug where restarting after a wreck could leave the car tilted.

If anything still looks too similar to another app, please tell us what you would need to see and we will change it.

Thank you.
```

If this reply is rejected too: appeal to the App Review Board (developer.apple.com/contact/app-store/?topic=appeal).
