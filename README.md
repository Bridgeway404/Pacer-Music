# Pacer

**Your run has a rhythm.** Pacer is a personal running DJ for iPhone: it measures your
running cadence (steps per minute) and matches the music experience to it.

- **Follow Me** — run naturally; Pacer detects sustained cadence changes and moves the
  musical target with you within ~10–15 seconds, while ignoring noise and brief spikes.
- **Pace Me** — pick the cadence you *want* (e.g. 170 SPM); the music centers on that
  tempo and pulls you toward it, while the UI shows your live gap to target.

The product is a **native iOS app (Swift + SwiftUI)**. A TypeScript reference
implementation of the algorithms lives in `/web` and serves as the behavioral spec +
cross-check test suite.

## Repository layout

```
/ios
  project.yml          XcodeGen spec (the .xcodeproj is generated, not committed)
  Pacer/               SwiftUI app (Run screen, onboarding, history, auth, settings)
  PacerKit/            SwiftPM package: ALL business logic + Swift Testing suites
/web                   TypeScript reference implementation + Vitest suites (secondary)
/supabase/migrations   Postgres schema (applied to the Supabase "Pacer" project)
/scripts               Demo-audio generator (synthesized loops we own outright)
/docs                  ARCHITECTURE.md, INTEGRATIONS.md
BUILD_STATUS.md        Current, honest status of everything
```

## The core loop

```
CoreMotion (CMPedometer)  ──┐
Cadence Simulator         ──┼──▶ CadenceProvider ──▶ CadenceEngine ──▶ target SPM
Manual Tap                ──┘        (raw SPM)        (median + EMA,
                                                       hysteresis,
                                                       sustained-change)
                                                            │
                              ┌─────────────────────────────┤
                              ▼                             ▼
                        Sequencer (Up Next)           TempoEngine (demo audio)
                        BPM matching ½x/1x/2x         AVAudioUnitTimePitch
                        recency/skip/transition       pitch-preserving stretch
                              │                             │
                              └──────────▶ SwiftUI ◀────────┘
```

## Building the iOS app

Requirements: macOS with Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ios
xcodegen generate          # produces Pacer.xcodeproj from project.yml
open Pacer.xcodeproj       # build & run the "Pacer" scheme on an iOS 17+ simulator/device
```

CI (GitHub Actions) does the same on every push: PacerKit tests on Linux + macOS, a
full unsigned iOS Simulator build, and the web reference Vitest suite.

Run the engine tests directly:

```bash
swift test --package-path ios/PacerKit    # any platform with a Swift 6 toolchain
cd web && npm ci && npx vitest run        # TypeScript reference suite
```

## Demo Mode (no accounts, no subscriptions)

Demo Mode works with zero external credentials:

- **Cadence Simulator** produces a realistic noisy runner you can steer from the
  diagnostics panel (150 → 170 SPM ramps, stops, spikes).
- **Bundled demo audio** — seven drum/bass loops synthesized by
  `scripts/generate-demo-audio.mjs` (this project authors the recordings, so
  tempo-shifting them is fully permitted).
- **DemoTempoEngine** (AVAudioEngine + AVAudioUnitTimePitch) actually *stretches the
  same song* smoothly toward the runner's cadence with pitch preserved — the proof of
  Pacer's central concept.
- Manual Tap mode demonstrates live cadence on any device with zero sensors.
- Runs persist locally (JSON in Documents) and appear in History.

## Supabase backend

Project: `Pacer` (ref `hpxrgcvvvovofpbgjbie`, us-west-1). Schema lives in
`supabase/migrations/` and is applied to the hosted project. Highlights:

- `profiles`, `music_connections` (+ token vault table with **no** RLS policies —
  server-only), `playlists`, `tracks`, `playlist_tracks`, `user_track_overrides`,
  `run_sessions`, `cadence_samples`, `playback_decisions`.
- **RLS on every table**; users can only touch their own rows.
- The iOS app embeds only the **publishable** key (`sb_publishable_…`), which is
  designed to be public and is constrained entirely by RLS. No service-role key exists
  in the app or repo.
- Email/password auth via the Supabase Swift SDK. Runs sync to the cloud when signed
  in; Demo Mode never requires an account.

## Environment / secrets

The iOS app needs no secret configuration. For future integrations:

- `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` — server-side only (Supabase Edge
  Function), never in the app binary. See `docs/INTEGRATIONS.md`.
- Apple Music requires no keys in-app (MusicKit auto-tokens) but does require the
  MusicKit app service on the App ID — an Apple Developer portal step.

Never commit `.env`, tokens, or Apple signing assets; `.gitignore` already excludes
them.

## Testing

- `ios/PacerKit/Tests` — Swift Testing suites for the cadence engine (stable, noisy,
  160→170 transition, spikes, gradual accel/decel, stop/resume), BPM matching,
  sequencer ranking, tap math, simulator core, session stats.
- `web/src/core/**/*.test.ts` — the same scenarios in TypeScript (Vitest), kept as an
  executable cross-check of the spec.

## Current limitations

See `docs/INTEGRATIONS.md` for the full honest matrix. Headlines: MusicKit exposes no
BPM metadata and no tempo control of protected streams (so Apple Music mode is
cadence-aware track *selection*, not time-stretching); Spotify is scaffolded at the
schema level but not yet wired; Core Motion cadence requires a physical iPhone.
