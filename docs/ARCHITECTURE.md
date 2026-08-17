# Pacer Architecture

## Guiding rules

1. **All business logic lives in PacerKit** (`ios/PacerKit`), a SwiftPM package that
   imports nothing but Foundation. It compiles and tests on Linux, macOS, and iOS.
   SwiftUI, CoreMotion, MusicKit, AVFoundation, and Supabase never appear inside it.
2. **Platform services are adapters.** The app layer (`ios/Pacer`) adapts
   CMPedometer → `CadenceProviding`, MusicKit → `MusicProviding`,
   AVAudioEngine → `DemoTempoEngine`, and hands plain values to PacerKit.
3. **Determinism.** The cadence engine takes time from sample timestamps and explicit
   `tick(now:)` calls — never the wall clock — so every scenario is unit-testable.
4. **Honest capabilities.** Every music provider declares
   `MusicProviderCapabilities` (bpmMetadata / playbackControl / tempoShift +
   limitations). UI and docs derive from that; nothing pretends a provider can do
   something it can't.

## Data flow

```
CMPedometer / Simulator / Tap
        │  CadenceSample (raw SPM, timestamp, source)
        ▼
CadenceEngine (PacerKit)
  median(5) → EMA(0.3) over a 10 s rolling window
  hysteresis: |smoothed − target| < 4 SPM ⇒ no change
  sustained-change: candidate must hold ≥ 5 s ⇒ retarget
  stop detection: zero samples or 4 s silence
        │  CadenceEngineUpdate (+ CadenceDecision on lock/retarget/stop/resume)
        ▼
RunCoordinator (@MainActor @Observable)
  Follow Me: engine target = musical target
  Pace Me:   user target   = musical target (engine still runs for the gap UI)
        │
        ├──▶ Sequencer.buildQueue → adaptive Up Next (BPM match ½x/1x/2x,
        │     recency penalty, skip penalty, transition-jump penalty)
        │
        ├──▶ Demo source: BpmMatcher.recommendedTargetTempo →
        │     DemoTempoEngine.setTargetBpm (eased ramp, rate clamped 0.6–1.6,
        │     track switch when the stretch would exceed 0.8–1.25x)
        │
        ├──▶ Apple Music source: queue re-ranking only (no tempo control is
        │     permitted on protected streams — selection, not manipulation)
        │
        └──▶ SessionRecorder → summary (avg/peak/on-beat%/trace/decisions)
              → SupabaseService (signed in) or LocalSessionStore (JSON)
```

## Cadence engine tuning

All constants live in `CadenceEngineConfig` (Swift) / `CadenceEngineConfig` (TS):

| Constant | Default | Meaning |
| --- | --- | --- |
| `window` | 10 s | rolling raw-sample window |
| `medianWindow` | 5 | median pre-filter width (spike killer) |
| `emaAlpha` | 0.3 | responsiveness of the smoothed signal |
| `changeThresholdSpm` | 4 | hysteresis band around the locked target |
| `sustain` | 5 s | how long a candidate change must persist |
| `minSamplesForLock` | 5 | samples before the first lock |
| `stopTimeout` | 4 s | silence ⇒ stopped |

End-to-end latency for a real sustained change ≈ smoothing lag (~3–5 s) + sustain
(5 s) ≈ **8–12 s**, verified by the transition tests in both languages.

## Why a TypeScript twin exists

The `/web` tree contains the original TS implementation of the same algorithms with a
matching Vitest suite. It is (a) the executable behavioral spec the Swift port was
verified against, (b) a future web/marketing playground. CI runs both suites; if they
ever disagree on a scenario, that's a bug in one of them.

## Concurrency model (app layer)

- `RunCoordinator` is `@MainActor @Observable`; SwiftUI reads it directly.
- Cadence providers expose `AsyncStream<CadenceSample>`; the coordinator consumes the
  stream in a Task and hops to the main actor per sample (sample rates are ~1–2 Hz —
  trivial load).
- `DemoTempoEngine` guards its status with a lock and marshals callbacks to the main
  actor.

## Background behavior

- The `audio` background mode + `AVAudioSession(.playback)` keeps demo-audio playback
  alive when the screen locks.
- `CMPedometer.startUpdates` callbacks continue while the app is backgrounded-but-
  running (audio keeps the process alive). True suspended-state cadence would need a
  workout session via HealthKit — an investigation track, not in the MVP.

## Persistence

- Signed in → `run_sessions` + downsampled `cadence_samples` (≤600 points) +
  `playback_decisions` in Supabase, all RLS-scoped to the user.
- Signed out → the same summary as JSON in the app's Documents directory.
- History merges both.
