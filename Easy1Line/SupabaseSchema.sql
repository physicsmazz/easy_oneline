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

alter table public.drawings add column if not exists created_by_name text not null default '';
alter table public.drawings add column if not exists updated_by_name text not null default '';

create table if not exists public.profiles (
    id uuid primary key default gen_random_uuid(),
    display_name text not null unique,
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
drop policy if exists "anonymous can read profiles" on public.profiles;
drop policy if exists "anonymous can create profiles" on public.profiles;
create policy "anonymous can read profiles" on public.profiles for select using (true);
create policy "anonymous can create profiles" on public.profiles for insert with check (true);

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

-- Normalized live model. drawings.data remains an export/import snapshot.
create table if not exists public.target_types (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid references auth.users(id),
    kind text not null,
    name text not null,
    symbol text,
    image_path text,
    color_hex text not null default '31D7E8',
    max_connections integer,
    scale double precision not null default 1,
    connection_angle double precision not null default 0,
    connection_angles jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

insert into public.target_types (kind, name, symbol, color_hex, max_connections)
select seed.kind, seed.name, seed.symbol, seed.color_hex, seed.max_connections
from (values
    ('source', 'Source', 'bolt.fill', 'FF9F43', 2),
    ('utilitySource', 'Utility source', 'powerplug.fill', 'FF9F43', 2),
    ('transformer', 'Transformer', 'arrow.left.arrow.right', 'F59E0B', 2),
    ('breaker', 'Breaker', 'bolt.shield.fill', 'F87171', 2),
    ('fuse', 'Fuse', 'circle.slash.fill', 'F87171', 2),
    ('disconnect', 'Disconnect', 'poweroff', 'F87171', 2),
    ('panel', 'Panel', 'rectangle.split.3x1', '60A5FA', 8),
    ('bus', 'Bus', 'line.3.horizontal', '60A5FA', 8),
    ('meter', 'Meter', 'gauge.with.dots.needle.bottom.50percent', 'A78BFA', 2),
    ('generator', 'Generator', 'engine.combustion.fill', 'FB923C', 2),
    ('motor', 'Motor', 'fanblades.fill', '34D399', 2),
    ('ground', 'Ground', 'arrow.down.to.line', '94A3B8', 2),
    ('load', 'Load', 'lightbulb.fill', 'FFD166', 2)
) as seed(kind, name, symbol, color_hex, max_connections)
where not exists (
    select 1 from public.target_types existing
    where existing.owner_id is null and existing.kind = seed.kind and existing.name = seed.name
);

create table if not exists public.drawing_line_definitions (
    id uuid primary key default gen_random_uuid(),
    drawing_id uuid not null references public.drawings(id) on delete cascade,
    name text not null,
    color_hex text not null default '31D7E8',
    wire_size text not null,
    material text not null check (material in ('Copper', 'AAAC', 'AAC', 'ACSR', 'Covered')),
    display_width double precision not null default 3,
    description text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.drawing_targets (
    id uuid primary key,
    drawing_id uuid not null references public.drawings(id) on delete cascade,
    target_type_id uuid references public.target_types(id) on delete set null,
    kind text not null,
    name text not null,
    canvas_x double precision not null,
    canvas_y double precision not null,
    location geography(Point, 4326),
    symbol text,
    image_path text,
    color_hex text not null default '31D7E8',
    max_connections integer,
    scale double precision not null default 1,
    connection_angle double precision not null default 0,
    connection_angles jsonb not null default '[]'::jsonb,
    is_compact boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.drawing_segments (
    id uuid primary key,
    drawing_id uuid not null references public.drawings(id) on delete cascade,
    start_target_id uuid not null references public.drawing_targets(id) on delete cascade,
    end_target_id uuid not null references public.drawing_targets(id) on delete cascade,
    start_slot integer,
    end_slot integer,
    name text not null,
    color_hex text not null default '31D7E8',
    wire_size text not null,
    material text not null check (material in ('Copper', 'AAAC', 'AAC', 'ACSR', 'Covered')),
    display_width double precision not null default 3,
    description text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (start_target_id <> end_target_id)
);

create index if not exists target_types_owner_idx on public.target_types(owner_id);

-- Shared wire library. Drawing-specific color, thickness, routes, and net data stay on the drawing instance.
create table if not exists public.wire_definitions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid references auth.users(id),
    name text not null,
    wire_size text not null,
    wire_type text not null,
    material text not null default 'Copper',
    misc text not null default '',
    description text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

insert into public.wire_definitions (name, wire_size, wire_type, material, misc, description)
select seed.name, seed.wire_size, seed.wire_type, seed.material, seed.misc, seed.description
from (values
    ('1/0 AAAC', '1/0', 'AAAC', 'AAAC', 'Bare overhead', 'Aluminum alloy overhead conductor'),
    ('1/0 ACSR', '1/0', 'ACSR', 'ACSR', 'Bare overhead', 'Aluminum conductor steel reinforced'),
    ('12/3 SO', '12/3', 'SO', 'Copper', 'Flexible cord', 'Common portable cord'),
    ('14/3 SO', '14/3', 'SO', 'Copper', 'Flexible cord', 'Common portable cord'),
    ('#4 Solid Copper', '#4', 'Solid Copper', 'Copper', 'Solid', 'Solid copper conductor')
) as seed(name, wire_size, wire_type, material, misc, description)
where not exists (
    select 1 from public.wire_definitions existing where existing.owner_id is null and existing.name = seed.name
);

create index if not exists wire_definitions_owner_idx on public.wire_definitions(owner_id);
alter table public.wire_definitions enable row level security;
drop policy if exists "anonymous can read wire definitions" on public.wire_definitions;
drop policy if exists "anonymous can manage wire definitions" on public.wire_definitions;
create policy "anonymous can read wire definitions" on public.wire_definitions for select using (true);
create policy "anonymous can manage wire definitions" on public.wire_definitions for all using (true) with check (true);

create index if not exists drawing_line_definitions_drawing_idx on public.drawing_line_definitions(drawing_id);
create index if not exists drawing_targets_drawing_idx on public.drawing_targets(drawing_id);
create index if not exists drawing_targets_location_idx on public.drawing_targets using gist(location);
create index if not exists drawing_segments_drawing_idx on public.drawing_segments(drawing_id);

-- One-call normalized save used by the app. The JSON payload remains the portable snapshot.
create or replace function public.save_drawing(p_id uuid, p_name text, p_data jsonb, p_created_by_name text default '', p_updated_by_name text default '')
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.drawings (id, name, data, created_by_name, updated_by_name, updated_at)
    values (p_id, p_name, p_data, p_created_by_name, p_updated_by_name, now())
    on conflict (id) do update set name = excluded.name, data = excluded.data, updated_by_name = excluded.updated_by_name, updated_at = now();

    delete from public.drawing_segments where drawing_id = p_id;
    delete from public.drawing_targets where drawing_id = p_id;
    delete from public.drawing_line_definitions where drawing_id = p_id;

    insert into public.drawing_line_definitions (id, drawing_id, name, color_hex, wire_size, material, display_width, description)
    select (line->>'id')::uuid, p_id, line->>'name', coalesce(line->>'colorHex', '31D7E8'), coalesce(line->>'wireSize', '14 AWG'), coalesce(line->>'material', 'Copper'), coalesce((line->>'displayWidth')::double precision, 3), coalesce(line->>'description', '')
    from jsonb_array_elements(coalesce(p_data->'lineDefinitions', '[]'::jsonb)) as line;

    -- Swift's Codable encodes CGPoint as [x, y]; also accept {"x":..,"y":..}.
    insert into public.drawing_targets (id, drawing_id, kind, name, canvas_x, canvas_y, symbol, image_path, color_hex, max_connections, scale, connection_angle, connection_angles, is_compact)
    select (target->>'id')::uuid, p_id, target->>'kind', target->>'name',
        coalesce(target->'position'->>'x', target->'position'->>0)::double precision,
        coalesce(target->'position'->>'y', target->'position'->>1)::double precision,
        target->>'symbol', null, coalesce(target->>'colorHex', '31D7E8'), (target->>'maxConnections')::integer, coalesce((target->>'scale')::double precision, 1), coalesce((target->>'connectionAngle')::double precision, 0), coalesce(target->'connectionAngles', '[]'::jsonb), coalesce((target->>'isCompact')::boolean, false)
    from jsonb_array_elements(coalesce(p_data->'targets', '[]'::jsonb)) as target;

    insert into public.drawing_segments (id, drawing_id, start_target_id, end_target_id, start_slot, end_slot, name, color_hex, wire_size, material, display_width, description)
    select (segment->>'id')::uuid, p_id, (segment->>'startID')::uuid, (segment->>'endID')::uuid, (segment->>'startSlot')::integer, (segment->>'endSlot')::integer, segment->>'name', coalesce(segment->>'colorHex', '31D7E8'), coalesce(segment->>'wireSize', '14 AWG'), coalesce(segment->>'material', 'Copper'), coalesce((segment->>'displayWidth')::double precision, 3), coalesce(segment->>'description', '')
    from jsonb_array_elements(coalesce(p_data->'segments', '[]'::jsonb)) as segment;
end;
$$;

grant execute on function public.save_drawing(uuid, text, jsonb, text, text) to anon, authenticated;

-- Anonymous prototype policies. Replace with owner checks when auth is enabled.
alter table public.target_types enable row level security;
alter table public.drawing_line_definitions enable row level security;
alter table public.drawing_targets enable row level security;
alter table public.drawing_segments enable row level security;

drop policy if exists "anonymous can read target types" on public.target_types;
drop policy if exists "anonymous can manage target types" on public.target_types;
create policy "anonymous can read target types" on public.target_types for select using (true);
create policy "anonymous can manage target types" on public.target_types for all using (true) with check (true);

drop policy if exists "anonymous can manage drawing line definitions" on public.drawing_line_definitions;
drop policy if exists "anonymous can manage drawing targets" on public.drawing_targets;
drop policy if exists "anonymous can manage drawing segments" on public.drawing_segments;
create policy "anonymous can manage drawing line definitions" on public.drawing_line_definitions for all using (true) with check (true);
create policy "anonymous can manage drawing targets" on public.drawing_targets for all using (true) with check (true);
create policy "anonymous can manage drawing segments" on public.drawing_segments for all using (true) with check (true);

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

-- Wire catalog: normalized wire sizes, types, and misc items
create table if not exists public.wire_sizes (
    id serial primary key,
    size_value text not null unique,
    description text not null default '',
    created_at timestamptz not null default now()
);

insert into public.wire_sizes (size_value, description)
select * from (values
    ('14 AWG', 'American Wire Gauge 14'),
    ('12 AWG', 'American Wire Gauge 12'),
    ('10 AWG', 'American Wire Gauge 10'),
    ('8 AWG', 'American Wire Gauge 8'),
    ('6 AWG', 'American Wire Gauge 6'),
    ('4 AWG', 'American Wire Gauge 4'),
    ('2 AWG', 'American Wire Gauge 2'),
    ('1/0', 'One-aught'),
    ('2/0', 'Two-aught'),
    ('3/0', 'Three-aught'),
    ('4/0', 'Four-aught'),
    ('250', '250 kcmil'),
    ('300', '300 kcmil'),
    ('336', '336 kcmil'),
    ('350', '350 kcmil'),
    ('500', '500 kcmil'),
    ('600', '600 kcmil'),
    ('750', '750 kcmil'),
    ('1000', '1000 kcmil')
) as sizes(size_value, description)
on conflict (size_value) do nothing;

create table if not exists public.wire_types (
    id serial primary key,
    type_name text not null unique,
    color_hex text not null default '31D7E8',
    description text not null default '',
    created_at timestamptz not null default now()
);

insert into public.wire_types (type_name, color_hex, description)
select * from (values
    ('Copper', 'B87333', 'Solid or stranded copper conductor'),
    ('ACSR', 'A9A9A9', 'Aluminum Conductor Steel Reinforced'),
    ('AAC', 'C0C0C0', 'All Aluminum Conductor'),
    ('AAAC', 'E8E8E8', 'All Aluminum Alloy Conductor'),
    ('Aluminum', 'E8E8E8', 'Aluminum conductor'),
    ('CU', 'B87333', 'Copper'),
    ('AL', 'C0C0C0', 'Aluminum')
) as types(type_name, color_hex, description)
on conflict (type_name) do nothing;

create table if not exists public.wire_misc (
    id serial primary key,
    misc_value text not null unique,
    description text not null default '',
    category text not null default 'insulation',
    created_at timestamptz not null default now()
);

insert into public.wire_misc (misc_value, category, description)
select * from (values
    ('BARE', 'insulation', 'Bare, uninsulated'),
    ('INSULATED', 'insulation', 'Insulated'),
    ('POLYETHYLENE', 'insulation', 'Polyethylene insulation'),
    ('RUBBER', 'insulation', 'Rubber insulation'),
    ('PTFE', 'insulation', 'PTFE insulation'),
    ('PVC', 'insulation', 'Polyvinyl chloride insulation'),
    ('EPR', 'insulation', 'Ethylene propylene rubber'),
    ('Prysmyan', 'manufacturer', 'Prysmyan cable manufacturer'),
    ('Southwire', 'manufacturer', 'Southwire cable manufacturer'),
    ('Nexans', 'manufacturer', 'Nexans cable manufacturer'),
    ('General Cable', 'manufacturer', 'General Cable manufacturer'),
    ('Corning', 'manufacturer', 'Corning cable manufacturer')
) as misc_items(misc_value, category, description)
on conflict (misc_value) do nothing;

-- Wire library: combination of size, type, and misc for standard wire configurations
create table if not exists public.wire_library (
    id serial primary key,
    size_id integer not null references public.wire_sizes(id) on delete restrict,
    type_id integer not null references public.wire_types(id) on delete restrict,
    misc_id integer not null references public.wire_misc(id) on delete restrict,
    description text not null default '',
    display_size numeric not null default 2.0,
    color_hex text not null default '31D7E8',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(size_id, type_id, misc_id)
);

-- Add RLS policies for wire catalog tables
alter table public.wire_sizes enable row level security;
alter table public.wire_types enable row level security;
alter table public.wire_misc enable row level security;
alter table public.wire_library enable row level security;

drop policy if exists "anonymous can read wire sizes" on public.wire_sizes;
drop policy if exists "anonymous can read wire types" on public.wire_types;
drop policy if exists "anonymous can read wire misc" on public.wire_misc;
drop policy if exists "anonymous can read wire library" on public.wire_library;
drop policy if exists "anonymous can manage wire library" on public.wire_library;

create policy "anonymous can read wire sizes" on public.wire_sizes for select using (true);
create policy "anonymous can read wire types" on public.wire_types for select using (true);
create policy "anonymous can read wire misc" on public.wire_misc for select using (true);
create policy "anonymous can read wire library" on public.wire_library for select using (true);
create policy "anonymous can manage wire library" on public.wire_library for all using (true) with check (true);

-- Indexes for better query performance
create index if not exists wire_library_size_id_idx on public.wire_library(size_id);
create index if not exists wire_library_type_id_idx on public.wire_library(type_id);
create index if not exists wire_library_misc_id_idx on public.wire_library(misc_id);
