# Pacer — Build Status

_Last updated: 2026-08-17 (iOS-first pivot session)._

## Working now

- **PacerKit** (Swift package, framework-free): cadence engine (median+EMA smoothing,
  hysteresis, sustained-change detection, stop/resume), BPM matcher (½x/1x/2x),
  adaptive sequencer, tap-cadence math, simulator core, session recorder — with full
  Swift Testing suites ported 1:1 from the TypeScript reference implementation.
- **TypeScript reference implementation** (`/web/src/core`) with 57 passing Vitest
  tests — the executable behavioral spec for the Swift port; both run in CI.
- **iOS app (SwiftUI, iOS 17+)**: onboarding (concept → music source → mode), the
  flagship Run screen (cadence dial + beat pulse, music target, Follow Me / Pace Me,
  target presets + fine stepper, pace-gap readout, now-playing card, adaptive Up Next
  queue, play/pause/skip, diagnostics panel toggle), session summary (stats + cadence
  chart + target changes + songs), history (cloud + local), email auth, settings.
- **Cadence providers**: Core Motion (CMPedometer, device-only), realistic simulator
  (steerable live), manual tap.
- **DemoTempoEngine**: AVAudioEngine + AVAudioUnitTimePitch pitch-preserving tempo
  shifting of the seven bundled synthesized loops (82–180 BPM) — the live proof that
  the same song follows the runner's cadence.
- **Supabase backend**: dedicated `Pacer` project, full schema + RLS applied,
  migrations in-repo, security advisors clean; Swift SDK wired for auth + run
  persistence; local JSON persistence when signed out.
- **CI (GitHub Actions)**: PacerKit tests on Linux + macOS, unsigned iOS Simulator
  build via XcodeGen, web Vitest suite.

## GitHub

- Repo: `Bridgeway404/Pacer-Music` — branch `claude/pacer-running-dj-mvp-mbx6s2`.
- ⚠️ The repo is currently **public**. You originally asked for private — flip it in
  GitHub → Settings → General → Danger Zone if you still want that (owner-only).

## Supabase

- Project **Pacer**, ref `hpxrgcvvvovofpbgjbie`, region us-west-1, **$10/month**
  (created with your pre-authorization; pause/delete it in the dashboard if
  unwanted). URL: `https://hpxrgcvvvovofpbgjbie.supabase.co`.
- Applied migrations: `init_schema` (all tables, RLS, triggers, indexes),
  `harden_functions` (revoked RPC access to trigger helpers).
- The iOS app embeds only the publishable key (`sb_publishable_…`) — safe by design;
  no service-role key anywhere client-side.

## Integrations (full detail in docs/INTEGRATIONS.md)

| Integration | Status |
| --- | --- |
| Demo audio + tempo-shift | **Working** (bundled synthesized loops we own) |
| Cadence simulator / tap | **Working** |
| Core Motion cadence | **Working on device** (Simulator can't produce pedometer data) |
| Apple Music (MusicKit) | **Partially working**: auth/playlists/playback implemented; blocked by provider on BPM metadata + tempo-shift of protected streams (selection engine instead) — needs your Apple Developer MusicKit setup to run on device |
| Spotify | **Not wired yet** — schema + URL parser + provider abstraction ready; needs a Supabase Edge Function for token exchange (design in docs) |
| HealthKit / Nike | **Investigation track** — via HealthKit only, no scraping |
| Vercel / web deploy | **Dropped by design** — product pivoted to native iOS; `/web` is a reference implementation only |

## What I need from Michael

1. **iOS Simulator/device run**: open `ios/` on a Mac (`xcodegen generate`, open
   `Pacer.xcodeproj`, run). CI builds it unsigned; running on *your* iPhone needs your
   Apple ID/team in Signing & Capabilities (free account is fine for device installs).
2. **Apple Music on device**: enable the **MusicKit app service** for
   `com.bridgeway404.pacer` in the Apple Developer portal (Certificates → Identifiers)
   and run on a device signed into an Apple Music subscription.
3. **Repo visibility**: make the repo private if still desired (Settings toggle).
4. **Supabase billing**: confirm you're OK with the $10/month Pacer project.
5. (When you want Spotify) create a Spotify Developer app and provide the client
   ID/secret as Supabase Edge Function secrets — never in the repo.

## Recommended next build

Wire **Sign in with Apple** (Supabase `signInWithIdToken`) and a **user-audio
import flow** (file picker + rights confirmation + BPM tagger) so the tempo-shift
demo works with the user's own legally-owned tracks — then the Spotify Edge-Function
OAuth loop.
