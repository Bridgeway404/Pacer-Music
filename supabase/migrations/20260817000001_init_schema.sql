-- Pacer initial schema
-- Applied to the Supabase "Pacer" project; kept in-repo as the source of truth.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles — one row per auth user
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  default_mode text not null default 'follow_me'
    check (default_mode in ('follow_me', 'pace_me')),
  preferred_cadence integer
    check (preferred_cadence between 100 and 220),
  cadence_tolerance integer not null default 6
    check (cadence_tolerance between 1 and 30),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: select own" on public.profiles
  for select using ((select auth.uid()) = id);
create policy "profiles: insert own" on public.profiles
  for insert with check ((select auth.uid()) = id);
create policy "profiles: update own" on public.profiles
  for update using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile when a user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- music_connections — provider link metadata (NO tokens here)
-- ---------------------------------------------------------------------------
create table public.music_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('spotify', 'apple_music', 'demo')),
  provider_user_id text,
  connection_status text not null default 'connected'
    check (connection_status in ('connected', 'expired', 'revoked', 'error')),
  scopes text,
  token_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);

create index music_connections_user_idx on public.music_connections (user_id);
alter table public.music_connections enable row level security;

-- Users may see and disconnect their own connections; token metadata only.
create policy "music_connections: select own" on public.music_connections
  for select using ((select auth.uid()) = user_id);
create policy "music_connections: delete own" on public.music_connections
  for delete using ((select auth.uid()) = user_id);
-- Inserts/updates happen server-side (OAuth callback) with the secret key.

create trigger music_connections_updated_at
  before update on public.music_connections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- music_connection_secrets — provider tokens. RLS enabled with NO policies:
-- completely invisible to browser clients; only server code using the
-- secret (service-role) key can touch it. Never expose via views or RPC.
-- ---------------------------------------------------------------------------
create table public.music_connection_secrets (
  connection_id uuid primary key references public.music_connections (id) on delete cascade,
  access_token text not null,
  refresh_token text,
  access_token_expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.music_connection_secrets enable row level security;
-- (no policies on purpose)

create trigger music_connection_secrets_updated_at
  before update on public.music_connection_secrets
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tracks — shared, deduped track metadata across users
-- ---------------------------------------------------------------------------
create table public.tracks (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('spotify', 'apple_music', 'demo')),
  provider_track_id text not null,
  name text not null,
  artist text not null default '',
  artwork_url text,
  duration_ms integer,
  original_bpm numeric(6, 2),
  bpm_source text check (bpm_source in ('provider', 'manual', 'estimated', 'known')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_track_id)
);

alter table public.tracks enable row level security;

-- Shared catalog: readable by any signed-in user; written only by the server
-- (playlist import runs server-side), so no insert/update policies.
create policy "tracks: select authenticated" on public.tracks
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- playlists + playlist_tracks
-- ---------------------------------------------------------------------------
create table public.playlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('spotify', 'apple_music', 'demo')),
  provider_playlist_id text not null,
  name text not null,
  artwork_url text,
  track_count integer not null default 0,
  synced_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, provider, provider_playlist_id)
);

create index playlists_user_idx on public.playlists (user_id);
alter table public.playlists enable row level security;

create policy "playlists: select own" on public.playlists
  for select using ((select auth.uid()) = user_id);
create policy "playlists: insert own" on public.playlists
  for insert with check ((select auth.uid()) = user_id);
create policy "playlists: update own" on public.playlists
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "playlists: delete own" on public.playlists
  for delete using ((select auth.uid()) = user_id);

create table public.playlist_tracks (
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  track_id uuid not null references public.tracks (id) on delete cascade,
  position integer not null,
  added_at timestamptz not null default now(),
  primary key (playlist_id, position)
);

create index playlist_tracks_track_idx on public.playlist_tracks (track_id);
alter table public.playlist_tracks enable row level security;

create policy "playlist_tracks: select via playlist" on public.playlist_tracks
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and p.user_id = (select auth.uid())
    )
  );
create policy "playlist_tracks: insert via playlist" on public.playlist_tracks
  for insert with check (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and p.user_id = (select auth.uid())
    )
  );
create policy "playlist_tracks: delete via playlist" on public.playlist_tracks
  for delete using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and p.user_id = (select auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- user_track_overrides — per-user manual BPM corrections
-- ---------------------------------------------------------------------------
create table public.user_track_overrides (
  user_id uuid not null references auth.users (id) on delete cascade,
  track_id uuid not null references public.tracks (id) on delete cascade,
  bpm numeric(6, 2) check (bpm between 30 and 300),
  updated_at timestamptz not null default now(),
  primary key (user_id, track_id)
);

alter table public.user_track_overrides enable row level security;

create policy "user_track_overrides: all own" on public.user_track_overrides
  for all using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create trigger user_track_overrides_updated_at
  before update on public.user_track_overrides
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- run_sessions
-- ---------------------------------------------------------------------------
create table public.run_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  mode text not null check (mode in ('follow_me', 'pace_me')),
  requested_target_spm integer check (requested_target_spm between 100 and 220),
  average_cadence numeric(6, 2),
  peak_cadence numeric(6, 2),
  on_beat_percent numeric(5, 2) check (on_beat_percent between 0 and 100),
  playlist_id uuid references public.playlists (id) on delete set null,
  playlist_name text,
  cadence_source text,
  songs_played jsonb not null default '[]'::jsonb,
  target_changes jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create index run_sessions_user_started_idx on public.run_sessions (user_id, started_at desc);
alter table public.run_sessions enable row level security;

create policy "run_sessions: all own" on public.run_sessions
  for all using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- cadence_samples — downsampled per-session cadence trace
-- ---------------------------------------------------------------------------
create table public.cadence_samples (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.run_sessions (id) on delete cascade,
  captured_at timestamptz not null,
  raw_spm numeric(6, 2),
  smoothed_spm numeric(6, 2),
  source text not null default 'unknown'
);

create index cadence_samples_session_idx on public.cadence_samples (session_id, captured_at);
alter table public.cadence_samples enable row level security;

create policy "cadence_samples: select via session" on public.cadence_samples
  for select using (
    exists (
      select 1 from public.run_sessions s
      where s.id = session_id and s.user_id = (select auth.uid())
    )
  );
create policy "cadence_samples: insert via session" on public.cadence_samples
  for insert with check (
    exists (
      select 1 from public.run_sessions s
      where s.id = session_id and s.user_id = (select auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- playback_decisions — cadence-engine decisions, for debugging/tuning
-- ---------------------------------------------------------------------------
create table public.playback_decisions (
  id bigint generated always as identity primary key,
  session_id uuid not null references public.run_sessions (id) on delete cascade,
  decided_at timestamptz not null,
  decision_type text not null,
  reason text,
  target_spm numeric(6, 2),
  previous_target_spm numeric(6, 2),
  track_ref text,
  details jsonb not null default '{}'::jsonb
);

create index playback_decisions_session_idx on public.playback_decisions (session_id, decided_at);
alter table public.playback_decisions enable row level security;

create policy "playback_decisions: select via session" on public.playback_decisions
  for select using (
    exists (
      select 1 from public.run_sessions s
      where s.id = session_id and s.user_id = (select auth.uid())
    )
  );
create policy "playback_decisions: insert via session" on public.playback_decisions
  for insert with check (
    exists (
      select 1 from public.run_sessions s
      where s.id = session_id and s.user_id = (select auth.uid())
    )
  );
