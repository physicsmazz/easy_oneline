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

create table if not exists public.conductor_catalog (
    material text not null check (material in ('Copper', 'AAAC', 'AAC', 'ACSR', 'Covered')),
    wire_size text not null,
    description text not null default '',
    primary key (material, wire_size)
);

insert into public.conductor_catalog (material, wire_size, description)
select material, wire_size, 'Common ' || material || ' conductor'
from unnest(array['Copper', 'AAAC', 'AAC', 'ACSR', 'Covered']) as materials(material)
cross join unnest(array['1/0', '2/0', '4/0', '2', '4', '6', '8', '10', '12', '14', '16', '18']) as sizes(wire_size)
on conflict (material, wire_size) do nothing;

alter table public.conductor_catalog enable row level security;
drop policy if exists "anyone can read conductor catalog" on public.conductor_catalog;
create policy "anyone can read conductor catalog" on public.conductor_catalog for select using (true);

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
