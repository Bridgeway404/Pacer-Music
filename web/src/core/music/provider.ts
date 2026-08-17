import type { Playlist, PlaylistWithTracks, Track, MusicProviderId } from "../shared/types";

/**
 * MusicProvider — abstraction over music sources (Demo, Spotify, Apple Music).
 *
 * Provider-specific restrictions (DRM, missing tempo data, premium-only
 * playback) must stay inside a provider implementation and never leak into
 * the cadence engine or sequencer. Capabilities are declared explicitly so
 * the UI can adapt honestly to what each provider is allowed to do.
 */

export interface PlaybackState {
  isPlaying: boolean;
  track: Track | null;
  positionMs: number;
  /** Device/context info where playback is happening, if known. */
  deviceName?: string | null;
}

export interface MusicProviderCapabilities {
  /** Can we retrieve BPM/tempo metadata from the provider? */
  bpmMetadata: boolean;
  /** Can we start/stop/skip playback through an official API? */
  playbackControl: boolean;
  /** Can we legally change the playback tempo of the audio? */
  tempoShift: boolean;
  /** Notes shown in diagnostics/docs about what limits apply. */
  limitations: string[];
}

export interface MusicProvider {
  readonly id: MusicProviderId;
  readonly label: string;
  readonly capabilities: MusicProviderCapabilities;

  /** True when the user has a usable connection (tokens valid, etc.). */
  isConnected(): Promise<boolean>;
  getPlaylists(): Promise<Playlist[]>;
  getPlaylist(playlistId: string): Promise<PlaylistWithTracks>;
  getTracks(playlistId: string): Promise<Track[]>;

  // Optional playback surface — only where officially supported.
  getCurrentPlayback?(): Promise<PlaybackState | null>;
  play?(trackId?: string): Promise<void>;
  pause?(): Promise<void>;
  next?(): Promise<void>;
}
