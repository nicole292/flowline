# FLOWLINE release checklist

Tick items as you go (in VS Code: change `[ ]` to `[x]`). Works the same way as
Bubblop's checklist; the Play Console steps are identical (see
`C:\dev\project_pop\docs\MOBILE_RELEASE_GUIDE.md`, section 9B).

## Done for you (2026-11-03)
- [x] Version 0.7.0 (build 9), committed (`b25b981`)
- [x] 63 automated tests pass
- [x] Signed Play bundle `build/flowline.aab` (preset "Android Play": Gradle build, arm64, target API 36)
- [x] Store texts and questionnaire answers (`docs/store/listing.md`)
- [x] Store images (`docs/store/assets/`)
- [x] Privacy and download pages (`docs/privacy.html`, `docs/index.html`)

## Decide first
- [x] Name: FLOWLINE: Highway Racer, package id `com.elishakov.flowline`
- [ ] Back up the signing key folder `C:\dev\flowline_keys` off this PC (USB stick or Google Drive).
      Losing it means you can never update the app.
- [ ] Create the GitHub repo and switch on Pages, so the privacy URL works (needs your OK to make it public).

## Real-phone checks (Android)
- [ ] Install the build from the internal testing track and play 10 minutes
- [ ] Smooth: camera switching, first crash, first crash site, settings scrolling
- [ ] Sound, music, vibration; pause when a call comes in; progress kept after reopening
- [ ] Each steering mode: arrows, wheel, gyro

## Google Play (same account as Bubblop)
- [ ] Create app, Game, Free
- [ ] App content (answers in `docs/store/listing.md`)
- [ ] Main store listing: texts, icon, feature graphic, screenshots
- [ ] Internal testing: upload `flowline.aab`, accept Play App Signing, install on your phone
- [ ] Closed testing track sent for review. **Start this right away; it does not have to wait for Bubblop.**
- [ ] 12+ testers opted in (the Bubblop testers can join this test too)
- [ ] Day 1 of 14: ____ · Day 14: ____
- [ ] Apply for production access, then production release sent for review
- [ ] **Live on Google Play**

## App Store (later)
- [ ] Apple Developer Program ($99), same as Bubblop
- [ ] iOS export from Godot needs a Mac or Codemagic; not set up yet
- [ ] Gyro steering checked on a real iPhone (only possible in the native app)
