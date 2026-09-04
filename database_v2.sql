-- =========================================================
-- KKJ EQUIPMENT LOAN SYSTEM V2 - SUPABASE POSTGRESQL
-- Kolej Kemahiran Johor
-- Jalankan SEMUA kod ini dalam Supabase > SQL Editor
-- =========================================================

create extension if not exists "pgcrypto";

do $$ begin
  create type public.user_role as enum ('admin', 'technician', 'lecturer', 'student');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.asset_status as enum (
    'Tersedia','Dipinjam','Dalam Penyelenggaraan','Rosak','Hilang','Dilupuskan'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.asset_condition as enum (
    'Baik','Sederhana','Perlu Dibaiki','Rosak'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.request_status as enum (
    'Pending','Approved','Rejected','Cancelled','Checked Out','Returned','Overdue'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.damage_status as enum ('Reported','Under Review','Resolved');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.maintenance_status as enum ('Scheduled','In Progress','Completed','Cancelled');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.user_role not null default 'student',
  student_staff_id text unique,
  department text,
  class_name text,
  phone text,
  is_active boolean not null default true,
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
  qr_code text unique,
  status public.asset_status not null default 'Tersedia',
  condition public.asset_condition not null default 'Baik',
  purchase_date date,
  purchase_price numeric(12,2) check (purchase_price is null or purchase_price >= 0),
  warranty_until date,
  image_url text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.loan_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  purpose text not null,
  borrow_date date not null,
  due_date date not null,
  status public.request_status not null default 'Pending',
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  rejected_at timestamptz,
  rejection_reason text,
  checkout_at timestamptz,
  returned_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (due_date >= borrow_date)
);

create table if not exists public.loan_items (
  id uuid primary key default gen_random_uuid(),
  loan_request_id uuid not null references public.loan_requests(id) on delete cascade,
  asset_id uuid not null references public.assets(id) on delete restrict,
  condition_before public.asset_condition,
  condition_after public.asset_condition,
  checkout_notes text,
  return_notes text,
  created_at timestamptz not null default now(),
  unique (loan_request_id, asset_id)
);

create table if not exists public.checkouts (
  id uuid primary key default gen_random_uuid(),
  loan_request_id uuid not null unique references public.loan_requests(id) on delete cascade,
  handed_over_by uuid references auth.users(id) on delete set null,
  received_by uuid references auth.users(id) on delete set null,
  checkout_at timestamptz not null default now(),
  notes text
);

create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  loan_request_id uuid not null unique references public.loan_requests(id) on delete cascade,
  received_by uuid references auth.users(id) on delete set null,
  returned_at timestamptz not null default now(),
  late_days integer not null default 0 check (late_days >= 0),
  notes text
);

create table if not exists public.damage_reports (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete restrict,
  loan_request_id uuid references public.loan_requests(id) on delete set null,
  reported_by uuid references auth.users(id) on delete set null,
  report_type text not null check (report_type in ('Damage', 'Lost')),
  description text not null,
  image_url text,
  status public.damage_status not null default 'Reported',
  resolution_notes text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.maintenance_records (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete cascade,
  title text not null,
  description text,
  technician_name text,
  cost numeric(12,2) check (cost is null or cost >= 0),
  scheduled_date date,
  completed_date date,
  status public.maintenance_status not null default 'Scheduled',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  is_read boolean not null default false,
  related_type text,
  related_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_assets_category on public.assets(category_id);
create index if not exists idx_assets_location on public.assets(location_id);
create index if not exists idx_assets_status on public.assets(status);
create index if not exists idx_assets_asset_tag on public.assets(asset_tag);
create index if not exists idx_loan_requests_requester on public.loan_requests(requester_id);
create index if not exists idx_loan_requests_status on public.loan_requests(status);
create index if not exists idx_loan_requests_due_date on public.loan_requests(due_date);
create index if not exists idx_loan_items_request on public.loan_items(loan_request_id);
create index if not exists idx_loan_items_asset on public.loan_items(asset_id);
create index if not exists idx_damage_reports_asset on public.damage_reports(asset_id);
create index if not exists idx_maintenance_asset on public.maintenance_records(asset_id);
create index if not exists idx_notifications_user on public.notifications(user_id, is_read);
create index if not exists idx_audit_logs_user on public.audit_logs(user_id);
create index if not exists idx_audit_logs_created_at on public.audit_logs(created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

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

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role() in ('admin','technician','lecturer'), false);
$$;

grant execute on function public.is_staff() to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id, full_name, role, student_staff_id, department, class_name, phone
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    case
      when new.raw_user_meta_data ->> 'role' in ('admin','technician','lecturer','student')
      then (new.raw_user_meta_data ->> 'role')::public.user_role
      else 'student'::public.user_role
    end,
    new.raw_user_meta_data ->> 'student_staff_id',
    new.raw_user_meta_data ->> 'department',
    new.raw_user_meta_data ->> 'class_name',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.calculate_late_days(p_due_date date, p_returned_at timestamptz)
returns integer
language sql
immutable
as $$
  select greatest(0, (p_returned_at::date - p_due_date));
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_assets_updated_at on public.assets;
create trigger trg_assets_updated_at before update on public.assets
for each row execute function public.set_updated_at();

drop trigger if exists trg_loan_requests_updated_at on public.loan_requests;
create trigger trg_loan_requests_updated_at before update on public.loan_requests
for each row execute function public.set_updated_at();

drop trigger if exists trg_damage_reports_updated_at on public.damage_reports;
create trigger trg_damage_reports_updated_at before update on public.damage_reports
for each row execute function public.set_updated_at();

drop trigger if exists trg_maintenance_updated_at on public.maintenance_records;
create trigger trg_maintenance_updated_at before update on public.maintenance_records
for each row execute function public.set_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace view public.active_loans as
select
  lr.id,
  lr.requester_id,
  lr.borrow_date,
  lr.due_date,
  lr.status,
  case
    when lr.returned_at is null and current_date > lr.due_date then (current_date - lr.due_date)
    else 0
  end as overdue_days
from public.loan_requests lr
where lr.status in ('Approved','Checked Out','Overdue');

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.locations enable row level security;
alter table public.assets enable row level security;
alter table public.loan_requests enable row level security;
alter table public.loan_items enable row level security;
alter table public.checkouts enable row level security;
alter table public.returns enable row level security;
alter table public.damage_reports enable row level security;
alter table public.maintenance_records enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select to authenticated
using (id = auth.uid() or public.is_staff());

drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update" on public.profiles for update to authenticated
using (id = auth.uid() or public.current_user_role() = 'admin')
with check (id = auth.uid() or public.current_user_role() = 'admin');

drop policy if exists "categories_read" on public.categories;
create policy "categories_read" on public.categories for select to authenticated using (true);

drop policy if exists "categories_admin_manage" on public.categories;
create policy "categories_admin_manage" on public.categories for all to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

drop policy if exists "locations_read" on public.locations;
create policy "locations_read" on public.locations for select to authenticated using (true);

drop policy if exists "locations_admin_manage" on public.locations;
create policy "locations_admin_manage" on public.locations for all to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

drop policy if exists "assets_read" on public.assets;
create policy "assets_read" on public.assets for select to authenticated using (true);

drop policy if exists "assets_staff_insert" on public.assets;
create policy "assets_staff_insert" on public.assets for insert to authenticated
with check (public.is_staff());

drop policy if exists "assets_staff_update" on public.assets;
create policy "assets_staff_update" on public.assets for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "assets_admin_delete" on public.assets;
create policy "assets_admin_delete" on public.assets for delete to authenticated
using (public.current_user_role() = 'admin');

drop policy if exists "loan_requests_select" on public.loan_requests;
create policy "loan_requests_select" on public.loan_requests for select to authenticated
using (requester_id = auth.uid() or public.is_staff());

drop policy if exists "loan_requests_insert" on public.loan_requests;
create policy "loan_requests_insert" on public.loan_requests for insert to authenticated
with check (requester_id = auth.uid());

drop policy if exists "loan_requests_update" on public.loan_requests;
create policy "loan_requests_update" on public.loan_requests for update to authenticated
using ((requester_id = auth.uid() and status in ('Pending','Cancelled')) or public.is_staff())
with check (requester_id = auth.uid() or public.is_staff());

drop policy if exists "loan_items_select" on public.loan_items;
create policy "loan_items_select" on public.loan_items for select to authenticated
using (
  exists (
    select 1 from public.loan_requests lr
    where lr.id = loan_request_id
      and (lr.requester_id = auth.uid() or public.is_staff())
  )
);

drop policy if exists "loan_items_insert" on public.loan_items;
create policy "loan_items_insert" on public.loan_items for insert to authenticated
with check (
  exists (
    select 1 from public.loan_requests lr
    where lr.id = loan_request_id
      and lr.requester_id = auth.uid()
      and lr.status = 'Pending'
  ) or public.is_staff()
);

drop policy if exists "loan_items_staff_update" on public.loan_items;
create policy "loan_items_staff_update" on public.loan_items for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "checkouts_select" on public.checkouts;
create policy "checkouts_select" on public.checkouts for select to authenticated
using (
  public.is_staff()
  or exists (
    select 1 from public.loan_requests lr
    where lr.id = loan_request_id and lr.requester_id = auth.uid()
  )
);

drop policy if exists "checkouts_staff_manage" on public.checkouts;
create policy "checkouts_staff_manage" on public.checkouts for all to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "returns_select" on public.returns;
create policy "returns_select" on public.returns for select to authenticated
using (
  public.is_staff()
  or exists (
    select 1 from public.loan_requests lr
    where lr.id = loan_request_id and lr.requester_id = auth.uid()
  )
);

drop policy if exists "returns_staff_manage" on public.returns;
create policy "returns_staff_manage" on public.returns for all to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "damage_reports_select" on public.damage_reports;
create policy "damage_reports_select" on public.damage_reports for select to authenticated
using (reported_by = auth.uid() or public.is_staff());

drop policy if exists "damage_reports_insert" on public.damage_reports;
create policy "damage_reports_insert" on public.damage_reports for insert to authenticated
with check (reported_by = auth.uid() or public.is_staff());

drop policy if exists "damage_reports_staff_update" on public.damage_reports;
create policy "damage_reports_staff_update" on public.damage_reports for update to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "maintenance_read" on public.maintenance_records;
create policy "maintenance_read" on public.maintenance_records for select to authenticated using (true);

drop policy if exists "maintenance_staff_manage" on public.maintenance_records;
create policy "maintenance_staff_manage" on public.maintenance_records for all to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "notifications_select" on public.notifications;
create policy "notifications_select" on public.notifications for select to authenticated
using (user_id = auth.uid());

drop policy if exists "notifications_update" on public.notifications;
create policy "notifications_update" on public.notifications for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "notifications_insert" on public.notifications;
create policy "notifications_insert" on public.notifications for insert to authenticated
with check (public.is_staff() or user_id = auth.uid());

drop policy if exists "audit_logs_admin_select" on public.audit_logs;
create policy "audit_logs_admin_select" on public.audit_logs for select to authenticated
using (public.current_user_role() = 'admin');

drop policy if exists "audit_logs_insert" on public.audit_logs;
create policy "audit_logs_insert" on public.audit_logs for insert to authenticated
with check (user_id = auth.uid());

insert into public.categories (name, description) values
  ('Desktop Computer', 'Komputer desktop makmal'),
  ('Laptop', 'Komputer riba'),
  ('Monitor', 'Monitor dan paparan'),
  ('Projector', 'Projektor untuk pembelajaran dan pembentangan'),
  ('Server', 'Server fizikal'),
  ('Network Switch', 'Switch rangkaian'),
  ('Router', 'Router rangkaian'),
  ('Printer', 'Printer dan multifunction printer'),
  ('Cable Tester', 'Peralatan pengujian kabel rangkaian'),
  ('Toolkit', 'Set peralatan teknikal'),
  ('ICT Accessory', 'Keyboard, mouse, cable dan aksesori ICT')
on conflict (name) do nothing;

insert into public.locations (name, code, description) values
  ('Makmal DSK 1', 'DSK1', 'Makmal Sistem Komputer'),
  ('Makmal DSK 2', 'DSK2', 'Makmal Sistem Komputer'),
  ('Bilik Server', 'SRV', 'Bilik server dan peralatan rangkaian'),
  ('Stor ICT', 'STOR', 'Simpanan aset dan peralatan ICT')
on conflict (name) do nothing;

-- Jadikan user pertama sebagai admin selepas akaun dicipta:
-- update public.profiles
-- set role = 'admin', full_name = 'Nama Admin'
-- where id = (select id from auth.users where email = 'admin@email.com');
