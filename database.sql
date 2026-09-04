-- =========================================================
-- KKJ INVENTORY V1 - SUPABASE POSTGRESQL
-- Jalankan SEMUA kod ini dalam Supabase > SQL Editor
-- =========================================================

create extension if not exists "pgcrypto";

-- ---------- ENUM ----------
do $$ begin
  create type public.user_role as enum ('admin', 'technician');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.asset_status as enum ('Aktif', 'Dalam Penyelenggaraan', 'Rosak', 'Dilupuskan');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.asset_condition as enum ('Baik', 'Sederhana', 'Perlu Dibaiki', 'Rosak');
exception when duplicate_object then null;
end $$;

-- ---------- TABLES ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.user_role not null default 'technician',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  asset_tag text not null unique,
  asset_name text not null,
  category_id uuid not null references public.categories(id) on delete restrict,
  location_id uuid not null references public.locations(id) on delete restrict,
  serial_number text,
  brand text,
  model text,
  status public.asset_status not null default 'Aktif',
  condition public.asset_condition not null default 'Baik',
  purchase_date date,
  purchase_price numeric(12,2) check (purchase_price is null or purchase_price >= 0),
  warranty_until date,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_assets_category on public.assets(category_id);
create index if not exists idx_assets_location on public.assets(location_id);
create index if not exists idx_assets_status on public.assets(status);
create index if not exists idx_assets_asset_tag on public.assets(asset_tag);

-- ---------- HELPERS ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_assets_updated_at on public.assets;
create trigger trg_assets_updated_at
before update on public.assets
for each row execute function public.set_updated_at();

-- Auto create profile apabila user dicipta dalam Supabase Auth
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    'technician'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Helper untuk semak role pengguna semasa
create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

grant execute on function public.current_user_role() to authenticated;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.locations enable row level security;
alter table public.assets enable row level security;

-- Profiles: user boleh lihat profil sendiri; admin boleh lihat semua.
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select"
on public.profiles for select
to authenticated
using (id = auth.uid() or public.current_user_role() = 'admin');

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update"
on public.profiles for update
to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

-- Categories / Locations: semua authenticated boleh baca, admin sahaja ubah.
drop policy if exists "categories_read" on public.categories;
create policy "categories_read"
on public.categories for select to authenticated using (true);

drop policy if exists "categories_admin_insert" on public.categories;
create policy "categories_admin_insert"
on public.categories for insert to authenticated
with check (public.current_user_role() = 'admin');

drop policy if exists "categories_admin_update" on public.categories;
create policy "categories_admin_update"
on public.categories for update to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

drop policy if exists "categories_admin_delete" on public.categories;
create policy "categories_admin_delete"
on public.categories for delete to authenticated
using (public.current_user_role() = 'admin');

drop policy if exists "locations_read" on public.locations;
create policy "locations_read"
on public.locations for select to authenticated using (true);

drop policy if exists "locations_admin_insert" on public.locations;
create policy "locations_admin_insert"
on public.locations for insert to authenticated
with check (public.current_user_role() = 'admin');

drop policy if exists "locations_admin_update" on public.locations;
create policy "locations_admin_update"
on public.locations for update to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

drop policy if exists "locations_admin_delete" on public.locations;
create policy "locations_admin_delete"
on public.locations for delete to authenticated
using (public.current_user_role() = 'admin');

-- Assets:
-- Admin + Technician boleh read, insert dan update.
-- Hanya Admin boleh delete.
drop policy if exists "assets_read" on public.assets;
create policy "assets_read"
on public.assets for select to authenticated using (true);

drop policy if exists "assets_insert" on public.assets;
create policy "assets_insert"
on public.assets for insert to authenticated
with check (auth.uid() is not null);

drop policy if exists "assets_update" on public.assets;
create policy "assets_update"
on public.assets for update to authenticated
using (auth.uid() is not null)
with check (auth.uid() is not null);

drop policy if exists "assets_admin_delete" on public.assets;
create policy "assets_admin_delete"
on public.assets for delete to authenticated
using (public.current_user_role() = 'admin');

-- ---------- SEED DATA ----------
insert into public.categories (name, description) values
  ('Desktop Computer', 'Komputer desktop makmal'),
  ('Laptop', 'Komputer riba'),
  ('Monitor', 'Monitor dan paparan'),
  ('Server', 'Server fizikal'),
  ('Network Switch', 'Switch rangkaian'),
  ('Router', 'Router rangkaian'),
  ('Printer', 'Printer dan multifunction printer'),
  ('ICT Accessory', 'Keyboard, mouse, cable dan aksesori ICT')
on conflict (name) do nothing;

insert into public.locations (name, code, description) values
  ('Makmal DSK 1', 'DSK1', 'Makmal Sistem Komputer'),
  ('Makmal DSK 2', 'DSK2', 'Makmal Sistem Komputer'),
  ('Bilik Server', 'SRV', 'Bilik server dan peralatan rangkaian'),
  ('Stor ICT', 'STOR', 'Simpanan aset dan peralatan ICT')
on conflict (name) do nothing;

-- =========================================================
-- CARA JADIKAN USER PERTAMA SEBAGAI ADMIN
-- 1) Cipta user di Authentication > Users.
-- 2) Login sekali / pastikan profile terhasil.
-- 3) Jalankan query berikut dengan email sebenar:
--
-- update public.profiles
-- set role = 'admin', full_name = 'Nama Admin'
-- where id = (select id from auth.users where email = 'admin@email.com');
-- =========================================================
