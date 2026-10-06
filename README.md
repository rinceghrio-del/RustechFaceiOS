# RUSTECH Face (iOS) — Phase 1

iOS port ng RUSTECH_APP_ESP32 para gawing "mukha" ng robot ang iPhone 8.
Naka-build sa GitHub Actions (walang Mac), unsigned `.ipa`, i-sideload gamit ang Sideloadly.

## Ano ang laman (Phase 1)
- RoboEyes (cyan na mata: kumukurap, lumilingon, happy / angry / searching) — port ng RoboEyesView.kt
- Front camera + Apple Vision face detection -> face tracking: LEFT / RIGHT / FORWARD / BACKWARD / STOP + servo (parehong logic at thresholds ng Android)
- ESP32 HTTP: `/command?dir=X&servo=N`, `/ping`, `dir=PLAY&track=N` (DFPlayer)
- Custom voice commands (CommandStore): "||" variants, pinakamahabang trigger ang panalo, may mga default galing sa Android, kasama ang `dfplayer play N`
- Voice input: Apple Speech (fil-PH, fallback en-PH / en-US)
- TTS: ElevenLabs na may fallback sa lokal na iOS TTS
- Voice Log, Settings (IP, ElevenLabs key / voice ID, thresholds, flip L/R, flip servo, ipakita ang camera)

## Hindi pa kasama (Phase 2)
Face enroll/recognition + greeting tracks, YOLO / Camera Nav (obstacle), Gemini, head scan, take-a-picture, Vosk offline.

## Paano i-build
1. Gumawa ng bagong GitHub repo (hal. `RUSTECH_APP_IOS`). Public para libre ang macOS minutes.
2. I-upload ang LAHAT ng laman ng zip na ito, kasama ang `.github/workflows/build-ios.yml`, sa `main` branch.
3. GitHub > Actions > "Build iOS (unsigned IPA)" > Run workflow (o automatic sa push).
4. Pag green na, i-download ang artifact `RustechFace-unsigned-ipa` (zip na may `RustechFace-unsigned.ipa`).
5. Kung may error: i-download ang artifact `build-log` at ipadala sa akin.

## Paano i-install sa iPhone 8
1. Sideloadly (Windows: iTunes at iCloud galing mismo sa apple.com).
2. Isaksak ang iPhone, i-drag ang `.ipa` sa Sideloadly, ilagay ang Apple ID, Start.
3. iPhone: Settings > General > VPN & Device Management > i-trust ang Apple ID mo.
4. iOS 16: Settings > Privacy & Security > Developer Mode > On (restart).
5. 7 days ang bisa — i-refresh gamit ang Sideloadly (o AltStore).

## Unang takbo
1. I-allow: Camera, Microphone, Speech Recognition, Local Network.
2. Connect ang iPhone sa WiFi ng ESP32 (SoftAP). Kapag tinanong "Use Without Internet Connection?" piliin ang **Use Without Internet**. Naka-ON ang Cellular Data para sa speech at ElevenLabs.
3. Gear icon (kanang-taas) > IP `192.168.4.1` > **Test Ping**.
4. Kung baliktad ang liko ng robot: i-toggle ang "Baliktad ang kaliwa/kanan". Kung baliktad ang tingin pataas/pababa: "Baliktad ang taas/baba".
5. ElevenLabs API key at voice ID: ilagay sa Settings > Boses (hindi ito naka-hardcode sa app).
