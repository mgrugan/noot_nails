-- Noor Nails — Supabase setup
-- Run this once in: Supabase dashboard → SQL Editor → New query → paste → Run.
--
-- Security model:
--   * Anyone can SEE open slots and BOOK one (only through book_slot()).
--   * Only accounts listed in public.admins can add/delete slots,
--     read bookings, or change settings. Row-level security enforces
--     this inside the database, so it can't be bypassed from the browser.

-- ---------- Tables ----------
create table if not exists public.slots (
  id         uuid primary key default gen_random_uuid(),
  date       date not null,
  time       time not null,
  service    text check (char_length(service) <= 100),
  booked     boolean not null default false,
  created_at timestamptz not null default now(),
  unique (date, time)
);

create table if not exists public.bookings (
  id         uuid primary key default gen_random_uuid(),
  slot_id    uuid unique references public.slots(id) on delete set null,
  date       date not null,
  time       time not null,
  service    text,
  name       text not null,
  email      text not null,
  phone      text not null,
  notes      text,
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  key   text primary key,
  value text
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ---------- Admin check ----------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- Row-level security ----------
alter table public.slots    enable row level security;
alter table public.bookings enable row level security;
alter table public.settings enable row level security;
alter table public.admins   enable row level security;   -- no policies = nobody can read/write via the API

drop policy if exists "public sees open slots" on public.slots;
create policy "public sees open slots" on public.slots
  for select to anon, authenticated
  using (booked = false or public.is_admin());

drop policy if exists "admin manages slots" on public.slots;
create policy "admin manages slots" on public.slots
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin reads bookings" on public.bookings;
create policy "admin reads bookings" on public.bookings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin manages settings" on public.settings;
create policy "admin manages settings" on public.settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- Public booking ----------
-- Books a slot atomically: the UPDATE only succeeds if the slot is still
-- open, so two people can never book the same time.
create or replace function public.book_slot(
  p_slot_id uuid,
  p_name    text,
  p_email   text,
  p_phone   text,
  p_notes   text default ''
)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  s public.slots%rowtype;
  v_notify text;
begin
  p_name  := btrim(coalesce(p_name, ''));
  p_email := btrim(coalesce(p_email, ''));
  p_phone := btrim(coalesce(p_phone, ''));
  p_notes := btrim(coalesce(p_notes, ''));

  if char_length(p_name) = 0 or char_length(p_name) > 100 then
    raise exception 'Please enter your name.';
  end if;
  if p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or char_length(p_email) > 200 then
    raise exception 'Please enter a valid email.';
  end if;
  if char_length(p_phone) = 0 or char_length(p_phone) > 40 then
    raise exception 'Please enter your phone number.';
  end if;
  if char_length(p_notes) > 1000 then
    raise exception 'Notes are too long (1000 characters max).';
  end if;

  update public.slots
     set booked = true
   where id = p_slot_id
     and booked = false
     and date >= current_date
  returning * into s;

  if not found then
    raise exception 'Sorry, that time was just booked. Please pick another.';
  end if;

  insert into public.bookings (slot_id, date, time, service, name, email, phone, notes)
  values (s.id, s.date, s.time, s.service, p_name, p_email, p_phone, nullif(p_notes, ''));

  select value into v_notify from public.settings where key = 'notify_email';
  return json_build_object('notify_email', v_notify);
end;
$$;

revoke all on function public.book_slot(uuid, text, text, text, text) from public;
grant execute on function public.book_slot(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------- Make yourself the admin ----------
-- 1. Authentication → Users → "Add user" → enter your email + a strong password
--    (tick "Auto Confirm User").
-- 2. Then run this line with your email:
--
-- insert into public.admins (user_id)
--   select id from auth.users where email = 'you@example.com';
