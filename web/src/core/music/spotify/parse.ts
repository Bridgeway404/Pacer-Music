/**
 * Spotify URL/URI parsing — pure functions, heavily unit-tested.
 */

export interface SpotifyPlaylistRef {
  playlistId: string;
}

const PLAYLIST_ID_RE = /^[a-zA-Z0-9]{16,34}$/;

/**
 * Accepts any of:
 *   https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
 *   https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123
 *   https://open.spotify.com/intl-de/playlist/37i9dQZF1DXcBWIGoYBM5M
 *   spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
 *   37i9dQZF1DXcBWIGoYBM5M   (bare id)
 * Returns null for anything else (tracks, albums, malformed input).
 */
export function parseSpotifyPlaylistUrl(input: string): SpotifyPlaylistRef | null {
  const trimmed = input.trim();
  if (!trimmed) return null;

  // spotify:playlist:<id>
  const uriMatch = trimmed.match(/^spotify:playlist:([a-zA-Z0-9]+)$/);
  if (uriMatch && PLAYLIST_ID_RE.test(uriMatch[1])) {
    return { playlistId: uriMatch[1] };
  }

  // Bare playlist id
  if (PLAYLIST_ID_RE.test(trimmed) && !trimmed.includes(".")) {
    return { playlistId: trimmed };
  }

  // URL forms
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }
  if (url.hostname !== "open.spotify.com" && url.hostname !== "play.spotify.com") {
    return null;
  }
  // Path may include a locale segment: /intl-de/playlist/<id>
  const segments = url.pathname.split("/").filter(Boolean);
  const playlistIdx = segments.indexOf("playlist");
  if (playlistIdx === -1 || playlistIdx + 1 >= segments.length) return null;
  const id = segments[playlistIdx + 1];
  if (!PLAYLIST_ID_RE.test(id)) return null;
  return { playlistId: id };
}
