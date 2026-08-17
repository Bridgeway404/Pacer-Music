import { describe, expect, it } from "vitest";
import { parseSpotifyPlaylistUrl } from "./parse";

const ID = "37i9dQZF1DXcBWIGoYBM5M";

describe("parseSpotifyPlaylistUrl", () => {
  it("parses a standard playlist URL", () => {
    expect(parseSpotifyPlaylistUrl(`https://open.spotify.com/playlist/${ID}`)).toEqual({
      playlistId: ID,
    });
  });

  it("parses a URL with query params (?si=…)", () => {
    expect(
      parseSpotifyPlaylistUrl(`https://open.spotify.com/playlist/${ID}?si=abc123&pt=xyz`),
    ).toEqual({ playlistId: ID });
  });

  it("parses locale-prefixed URLs", () => {
    expect(parseSpotifyPlaylistUrl(`https://open.spotify.com/intl-de/playlist/${ID}`)).toEqual({
      playlistId: ID,
    });
  });

  it("parses spotify: URIs", () => {
    expect(parseSpotifyPlaylistUrl(`spotify:playlist:${ID}`)).toEqual({ playlistId: ID });
  });

  it("parses a bare playlist id", () => {
    expect(parseSpotifyPlaylistUrl(ID)).toEqual({ playlistId: ID });
  });

  it("tolerates surrounding whitespace", () => {
    expect(parseSpotifyPlaylistUrl(`  https://open.spotify.com/playlist/${ID}  `)).toEqual({
      playlistId: ID,
    });
  });

  it("rejects track/album/artist URLs", () => {
    expect(parseSpotifyPlaylistUrl(`https://open.spotify.com/track/${ID}`)).toBeNull();
    expect(parseSpotifyPlaylistUrl(`https://open.spotify.com/album/${ID}`)).toBeNull();
    expect(parseSpotifyPlaylistUrl(`spotify:track:${ID}`)).toBeNull();
  });

  it("rejects non-Spotify hosts", () => {
    expect(parseSpotifyPlaylistUrl(`https://example.com/playlist/${ID}`)).toBeNull();
    expect(parseSpotifyPlaylistUrl(`https://open.spotify.com.evil.com/playlist/${ID}`)).toBeNull();
  });

  it("rejects malformed ids and junk", () => {
    expect(parseSpotifyPlaylistUrl("")).toBeNull();
    expect(parseSpotifyPlaylistUrl("not a url")).toBeNull();
    expect(parseSpotifyPlaylistUrl("https://open.spotify.com/playlist/short")).toBeNull();
    expect(parseSpotifyPlaylistUrl("https://open.spotify.com/playlist/")).toBeNull();
    expect(parseSpotifyPlaylistUrl("https://open.spotify.com/playlist/has spaces here!!")).toBeNull();
  });
});
