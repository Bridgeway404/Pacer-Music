# Pacer Integrations — honest status matrix

Legend: **WORKING** · **PARTIALLY WORKING** · **MOCKED/DEMO** · **BLOCKED BY PROVIDER**
· **FUTURE NATIVE IMPLEMENTATION**

## Cadence sources

| Source | Status | Notes |
| --- | --- | --- |
| Cadence Simulator | **WORKING** | Deterministic core (`SimulatedRunnerCore`) + timer wrapper; steerable live (150/154/162/170/180/stop) from the diagnostics panel; noisy + ramped like a real runner. |
| Manual Tap | **WORKING** | Tap-per-step; median-interval SPM; idle→stop detection. Works in the Simulator. |
| Core Motion (CMPedometer) | **WORKING (device-only)** | `CMPedometerData.currentCadence` (steps/sec → ×60). Requires a physical iPhone with a motion coprocessor + Motion & Fitness permission; the iOS Simulator reports nothing, and CI can only compile it. Falls back to steps/interval when instantaneous cadence is momentarily nil. |
| DeviceMotion (web) | **MOCKED/DEMO** | Experimental accelerometer peak-detection exists in the TS reference (`/web/src/core/cadence/devicemotion.ts`); superseded by Core Motion on iOS. |
| Apple Watch / HealthKit | **FUTURE NATIVE IMPLEMENTATION** | HealthKit workout sessions would give background-safe cadence + history (see below). Not a prerequisite for the MVP. |
| Nike Run Club | **BLOCKED BY PROVIDER** | No public API; scraping is off the table by policy. If Nike ever exposes workout data via HealthKit, it arrives through the HealthKit track automatically. |

## Music providers

### Demo Mode — **WORKING**
- Seven synthesized loops (82–180 BPM) authored by `scripts/generate-demo-audio.mjs`;
  the project owns these recordings outright, so tempo manipulation is fully permitted.
- `DemoTempoEngine` = AVAudioEngine + `AVAudioUnitTimePitch`: **pitch-preserving**
  time-stretch, eased 2.5 s ramps, rate clamped to 0.6–1.6.
- This is the proof of the core concept: 150 SPM → ~150 BPM, accelerate to 165 SPM →
  the *same song* glides to ~165 BPM.
- The sequencer switches loops when a target would need a stretch outside 0.8–1.25×.

### Apple Music (MusicKit) — **PARTIALLY WORKING**
Implemented (official APIs only): authorization (`MusicAuthorization`), library
playlists (`MusicLibraryRequest<Playlist>`), playlist tracks (`playlist.with([.tracks])`),
metadata/artwork, playback via `ApplicationMusicPlayer` (queue, play/pause/skip),
background playback via the audio background mode.

Provider constraints (verified against current MusicKit — not worked around):
- **No BPM/tempo metadata.** MusicKit's catalog/library items expose no tempo
  attribute. Pacer ranks unknown-BPM tracks low and supports per-user manual BPM via
  `user_track_overrides`. (The old iTunes "BPM" ID3 field is user-entered library
  metadata and is not exposed through MusicKit either.)
- **No tempo manipulation of protected streams.** `ApplicationMusicPlayer` offers no
  supported time-stretch, and circumventing DRM is prohibited — so Apple Music mode is
  a cadence-aware track **selection** engine, exactly as designed.
- Requires: active Apple Music subscription on the device, and the **MusicKit app
  service enabled for the App ID** in the Apple Developer portal (account-owner step).
  Playback does not function in the iOS Simulator.

### Spotify — **MOCKED/DEMO (schema-ready, not wired)**
The `MusicProviding` abstraction, DB schema (`music_connections` +
`music_connection_secrets` token vault, `playlists`, `tracks`), and the TS playlist-URL
parser (fully tested) exist. Not yet implemented in the iOS app. The correct
architecture when it's wired:

- OAuth (PKCE) from the app → token exchange in a **Supabase Edge Function** holding
  `SPOTIFY_CLIENT_ID`/`SPOTIFY_CLIENT_SECRET`; refresh tokens live in
  `music_connection_secrets` (RLS: no policies ⇒ server-only). Tokens never touch the
  client.
- Playlists/tracks via the Web API; **playback control requires Spotify Premium** and
  an active device (Connect API). iOS in-app playback would use the Spotify iOS SDK.
- **Audio Features (tempo/BPM) is deprecated for new Spotify apps** (API changes of
  Nov 2024) — new client IDs get 403s. So Spotify BPMs must come from manual tagging
  or other legitimate sources, same as Apple Music.
- No tempo manipulation of Spotify audio, ever — selection only.

### User-provided audio files — **FUTURE (engine ready)**
`DemoTempoEngine.load(url:sourceBpm:)` already plays arbitrary local files with
pitch-preserving stretch; a file-picker UI + user rights confirmation is the remaining
work.

## Backend

| Piece | Status | Notes |
| --- | --- | --- |
| Supabase Postgres schema + RLS | **WORKING** | Applied to project `hpxrgcvvvovofpbgjbie`; migrations in-repo; advisors clean (one intentional INFO: the token vault has RLS-no-policies by design). |
| Supabase Auth (email/password) | **WORKING** | Via supabase-swift; profile auto-created by trigger. |
| Sign in with Apple | **FUTURE NATIVE IMPLEMENTATION** | Supabase supports it (`signInWithIdToken`); needs the Sign in with Apple capability + Apple Developer config. Natural default auth for the App Store build. |
| Run session persistence | **WORKING** | Cloud when signed in, local JSON otherwise; History merges both. |

## HealthKit — investigation track
`HKWorkoutSession` (watchOS) / workout builders enable background-safe live metrics;
historical running cadence can be derived from `HKQuantityType(.runningStrideLength)` /
steps, and workouts logged by Nike Run Club appear in HealthKit if the user enables
sharing — the legitimate path to "Nike data" without scraping. Not needed for the live
MVP: Core Motion covers live cadence today.
