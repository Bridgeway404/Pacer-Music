/**
 * Shared domain types for Pacer.
 *
 * Everything in `src/core` is framework-free TypeScript: no React, no Next.js,
 * no DOM assumptions unless a file is explicitly a browser adapter. This keeps
 * the cadence/music logic portable to a future native (iOS) client.
 */

/** Where a cadence sample came from. */
export type CadenceSource =
  | "simulator"
  | "tap"
  | "devicemotion"
  | "native"
  | "unknown";

/** A single cadence observation in steps-per-minute. */
export interface CadenceSample {
  /** Epoch milliseconds when the sample was captured. */
  capturedAt: number;
  /** Raw steps-per-minute value. 0 means "no steps detected". */
  spm: number;
  source: CadenceSource;
}

/** The two primary Pacer run modes. */
export type RunMode = "follow_me" | "pace_me";

/** Music providers Pacer knows about. */
export type MusicProviderId = "demo" | "spotify" | "apple_music";

export interface Track {
  id: string;
  provider: MusicProviderId;
  providerTrackId: string;
  name: string;
  artist: string;
  artworkUrl: string | null;
  durationMs: number;
  /** Known BPM of the recording, when legally/API-accessibly available. */
  bpm: number | null;
  /** Provider-specific extras (e.g. uri, previewUrl, audioUrl for demo). */
  metadata?: Record<string, unknown>;
}

export interface Playlist {
  id: string;
  provider: MusicProviderId;
  providerPlaylistId: string;
  name: string;
  artworkUrl: string | null;
  trackCount: number;
}

export interface PlaylistWithTracks extends Playlist {
  tracks: Track[];
}

/** A persisted run session (mirrors the `run_sessions` table). */
export interface RunSessionSummary {
  id: string;
  startedAt: number;
  endedAt: number | null;
  mode: RunMode;
  requestedTargetSpm: number | null;
  averageCadence: number | null;
  peakCadence: number | null;
  playlistId: string | null;
  playlistName?: string | null;
  onBeatPercent: number | null;
  cadenceSamples: Array<{ t: number; raw: number; smoothed: number }>;
  songsPlayed: Array<{ trackId: string; name: string; artist: string; startedAt: number }>;
  targetChanges: Array<{ t: number; targetSpm: number; reason: string }>;
}
