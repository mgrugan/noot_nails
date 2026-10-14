-- Noot Nails — update 009: two sessions a day, 3–5pm and 6–8pm
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.
-- Safe whether or not update 008 was run. Booked sessions are never touched.

-- 1) Open 7–9pm sessions (today onward) move to 6–8pm.
update public.slots s
   set time = '18:00'
 where s.time = '19:00'
   and s.booked = false
   and s.date >= (now() at time zone 'America/New_York')::date
   and not exists (
     select 1 from public.slots o where o.date = s.date and o.time = '18:00'
   );

-- 2) Remove open 5–7pm sessions (today onward).
delete from public.slots
 where time = '17:00'
   and booked = false
   and date >= (now() at time zone 'America/New_York')::date;

-- 3) If a 5–7pm is already BOOKED that day, remove the open 6–8pm that would overlap it.
delete from public.slots s
 where s.time = '18:00'
   and s.booked = false
   and s.date >= (now() at time zone 'America/New_York')::date
   and exists (
     select 1 from public.slots o where o.date = s.date and o.time = '17:00' and o.booked
   );

-- 4) Future auto-filled weekdays get only 3–5pm and 6–8pm.
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
        (d, '18:00', '2-hour session', 120)
      on conflict (date, time) do nothing;
    end if;
  end loop;

  insert into public.settings (key, value) values ('autofill_through', v_end::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.autofill_slots() to anon, authenticated;
