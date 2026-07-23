-- Cinema — Supabase Schema
-- Apply this in Supabase SQL Editor (Dashboard → SQL Editor → New query)

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────
create table public.users (
  id            uuid references auth.users(id) on delete cascade primary key,
  username      text unique not null,
  display_name  text,
  avatar_url    text,
  bio           text,
  onboarded     boolean not null default false, -- false until 10-Movie Wall complete
  created_at    timestamptz not null default now()
);

alter table public.users enable row level security;

create policy "Users can read any profile"
  on public.users for select using (true);

create policy "Users can update own profile"
  on public.users for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.users for insert with check (auth.uid() = id);

-- ─────────────────────────────────────────────
-- RANKED ITEMS
-- Current ELO score + rank for each user's media
-- ─────────────────────────────────────────────
create table public.ranked_items (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.users(id) on delete cascade not null,
  tmdb_id       integer not null,
  media_type    text not null check (media_type in ('movie', 'tv')),
  elo_score     numeric not null default 1000,
  rank_position integer,
  added_at      timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, tmdb_id, media_type)
);

alter table public.ranked_items enable row level security;

create policy "Anyone can read ranked items"
  on public.ranked_items for select using (true);

create policy "Users can manage own ranked items"
  on public.ranked_items for all using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- ELO MATCHES
-- Immutable log of every "This or That" battle
-- ─────────────────────────────────────────────
create table public.elo_matches (
  id              uuid default uuid_generate_v4() primary key,
  user_id         uuid references public.users(id) on delete cascade not null,
  winner_tmdb_id  integer not null,
  loser_tmdb_id   integer not null,
  media_type      text not null check (media_type in ('movie', 'tv', 'mixed')),
  winner_elo_before numeric,
  loser_elo_before  numeric,
  winner_elo_after  numeric,
  loser_elo_after   numeric,
  created_at      timestamptz not null default now()
);

alter table public.elo_matches enable row level security;

create policy "Users can read own matches"
  on public.elo_matches for select using (auth.uid() = user_id);

create policy "Users can insert own matches"
  on public.elo_matches for insert with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- FOLLOWS
-- ─────────────────────────────────────────────
create table public.follows (
  follower_id   uuid references public.users(id) on delete cascade not null,
  following_id  uuid references public.users(id) on delete cascade not null,
  created_at    timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id != following_id)
);

alter table public.follows enable row level security;

create policy "Anyone can read follows"
  on public.follows for select using (true);

create policy "Users can manage own follows"
  on public.follows for all using (auth.uid() = follower_id);

-- ─────────────────────────────────────────────
-- FEED EVENTS
-- Denormalized feed: written on each ranking action
-- Realtime subscription source for the social feed
-- ─────────────────────────────────────────────
create table public.feed_events (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.users(id) on delete cascade not null,
  event_type    text not null check (event_type in ('ranked', 'added', 'reranked')),
  tmdb_id       integer not null,
  media_type    text not null check (media_type in ('movie', 'tv')),
  elo_score     numeric,
  rank_position integer,
  created_at    timestamptz not null default now()
);

alter table public.feed_events enable row level security;

create policy "Anyone can read feed events"
  on public.feed_events for select using (true);

create policy "Users can insert own feed events"
  on public.feed_events for insert with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- WATCHLIST
-- Films the user wants to see but hasn't ranked yet
-- ─────────────────────────────────────────────
create table public.watchlist (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.users(id) on delete cascade not null,
  tmdb_id     integer not null,
  media_type  text not null check (media_type in ('movie', 'tv')),
  added_at    timestamptz not null default now(),
  unique (user_id, tmdb_id)
);

alter table public.watchlist enable row level security;

create policy "Users can manage own watchlist"
  on public.watchlist for all using (auth.uid() = user_id);

create index on public.watchlist (user_id, added_at desc);

-- ─────────────────────────────────────────────
-- CUSTOM LISTS
-- User-created lists (e.g. "Funny Movies"), separate from Watched/Watchlist
-- ─────────────────────────────────────────────
create table public.custom_lists (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.users(id) on delete cascade not null,
  name        text not null,
  created_at  timestamptz not null default now(),
  unique (user_id, name)
);

alter table public.custom_lists enable row level security;

create policy "Users can manage own custom lists"
  on public.custom_lists for all using (auth.uid() = user_id);

create table public.list_items (
  id          uuid default uuid_generate_v4() primary key,
  list_id     uuid references public.custom_lists(id) on delete cascade not null,
  tmdb_id     integer not null,
  media_type  text not null check (media_type in ('movie', 'tv')),
  added_at    timestamptz not null default now(),
  unique (list_id, tmdb_id, media_type)
);

alter table public.list_items enable row level security;

create policy "Users can manage items in own lists"
  on public.list_items for all using (
    exists (select 1 from public.custom_lists where custom_lists.id = list_items.list_id and custom_lists.user_id = auth.uid())
  );

create index on public.custom_lists (user_id, created_at desc);
create index on public.list_items (list_id);

-- ─────────────────────────────────────────────
-- FILM NOTES
-- Private per-user note on any film, independent of ranked/watchlist
-- status — works even for films the user hasn't watched yet. No public
-- select policy: only the owning user can read their own notes.
-- ─────────────────────────────────────────────
create table public.film_notes (
  id          uuid default uuid_generate_v4() primary key,
  user_id     uuid references public.users(id) on delete cascade not null,
  tmdb_id     integer not null,
  media_type  text not null check (media_type in ('movie', 'tv')),
  note        text not null default '',
  updated_at  timestamptz not null default now(),
  unique (user_id, tmdb_id, media_type)
);

alter table public.film_notes enable row level security;

create policy "Users can manage own film notes"
  on public.film_notes for all using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────
create index on public.ranked_items (user_id, elo_score desc);
create index on public.elo_matches (user_id, created_at desc);
create index on public.feed_events (user_id, created_at desc);
create index on public.follows (following_id);

-- ─────────────────────────────────────────────
-- REALTIME
-- Enable realtime on feed_events for live social feed
-- ─────────────────────────────────────────────
alter publication supabase_realtime add table public.feed_events;
