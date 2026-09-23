-- Noot Nails — update 002: automatic weekday sessions + price picker
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.

-- ---------- Session length ----------
alter table public.slots
  add column if not exists duration_minutes integer not null default 120;

-- ---------- What the client picked ----------
alter table public.bookings
  add column if not exists nail_service text,
  add column if not exists designs      text[] not null default '{}',
  add column if not exists total        integer;

-- ---------- Automatic weekday sessions ----------
-- Keeps the next 14 days filled with 2-hour sessions on weekdays:
-- 3–5pm, 5–7pm, 7–9pm (all finish before 10pm). Each day is only ever
-- filled once, so a session you delete stays deleted.
create or replace function public.autofill_slots()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_today   date := (now() at time zone 'America/New_York')::date;
  v_end     date := v_today + 14;
  v_through date;
  d         date;
begin
  select value::date into v_through from public.settings where key = 'autofill_through';
  if v_through is null then v_through := v_today - 1; end if;
  if v_through >= v_end then return; end if;

  for d in
    select g::date from generate_series(greatest(v_through + 1, v_today), v_end, interval '1 day') g
  loop
    if extract(isodow from d) <= 5 then   -- Monday–Friday
      insert into public.slots (date, time, service, duration_minutes) values
        (d, '15:00', '2-hour session', 120),
        (d, '17:00', '2-hour session', 120),
        (d, '19:00', '2-hour session', 120)
      on conflict (date, time) do nothing;
    end if;
  end loop;

  insert into public.settings (key, value) values ('autofill_through', v_end::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.autofill_slots() to anon, authenticated;

-- ---------- Booking with price selection ----------
-- Prices live here so the total saved with a booking can't be tampered
-- with from the browser. Keep in sync with PRICES in index.html.
drop function if exists public.book_slot(uuid, text, text, text, text);

create or replace function public.book_slot(
  p_slot_id      uuid,
  p_name         text,
  p_email        text,
  p_phone        text,
  p_notes        text default '',
  p_nail_service text default null,
  p_designs      text[] default '{}'
)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  s        public.slots%rowtype;
  v_notify text;
  v_total  integer;
  v_add    integer;
  d        text;
begin
  p_name  := btrim(coalesce(p_name, ''));
  p_email := btrim(coalesce(p_email, ''));
  p_phone := btrim(coalesce(p_phone, ''));
  p_notes := btrim(coalesce(p_notes, ''));
  p_designs := array(select distinct x from unnest(coalesce(p_designs, '{}')) x);

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

  v_total := case p_nail_service
    when 'short'   then 30
    when 'medium'  then 35
    when 'long'    then 40
    when 'xl'      then 40
    when 'natural' then 30
  end;
  if v_total is null then
    raise exception 'Please choose a nail service.';
  end if;

  foreach d in array p_designs loop
    v_add := case d
      when 'french' then 5
      when 'dots'   then 2
      when 'art'    then 5
      when '3d'     then 5
      when 'charms' then 0
    end;
    if v_add is null then raise exception 'Unknown design option.'; end if;
    v_total := v_total + v_add;
  end loop;

  update public.slots
     set booked = true
   where id = p_slot_id
     and booked = false
     and date >= current_date - 1
  returning * into s;

  if not found then
    raise exception 'Sorry, that time was just booked. Please pick another.';
  end if;

  insert into public.bookings
    (slot_id, date, time, service, name, email, phone, notes, nail_service, designs, total)
  values
    (s.id, s.date, s.time, s.service, p_name, p_email, p_phone, nullif(p_notes, ''),
     p_nail_service, p_designs, v_total);

  select value into v_notify from public.settings where key = 'notify_email';
  return json_build_object('notify_email', v_notify, 'total', v_total);
end;
$$;

revoke all on function public.book_slot(uuid, text, text, text, text, text, text[]) from public;
grant execute on function public.book_slot(uuid, text, text, text, text, text, text[]) to anon, authenticated;
