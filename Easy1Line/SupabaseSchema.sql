-- Easy1Line / drawing storage
-- Run this in Supabase SQL Editor.

create extension if not exists postgis;

create table if not exists public.drawings (
    id uuid primary key,
    name text not null,
    owner_id uuid references auth.users(id),
    data jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists drawings_owner_id_idx on public.drawings(owner_id);
create index if not exists drawings_data_gin_idx on public.drawings using gin(data);

alter table public.drawings enable row level security;

-- Anonymous mode: drawings are readable and writable while the app is prototyping.
-- Replace these policies with owner_id = auth.uid() policies before account-based access.
drop policy if exists "anonymous can read drawings" on public.drawings;
drop policy if exists "anonymous can insert drawings" on public.drawings;
drop policy if exists "anonymous can update drawings" on public.drawings;
drop policy if exists "anonymous can delete drawings" on public.drawings;
create policy "anonymous can read drawings" on public.drawings for select using (true);
create policy "anonymous can insert drawings" on public.drawings for insert with check (true);
create policy "anonymous can update drawings" on public.drawings for update using (true) with check (true);
create policy "anonymous can delete drawings" on public.drawings for delete using (true);

-- Create an image bucket in the Supabase dashboard named target-icons.
-- Image paths should be stored in drawing data, not embedded as base64 long-term.
