-- Noot Nails — update 008: evening session moves from 7–9pm to 6–8pm
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.

-- 1) Move every open (not booked) 7pm session from today onward to 6pm.
--    Booked 7pm sessions are left alone. Skips a day if it already has a 6pm slot.
update public.slots s
   set time = '18:00'
 where s.time = '19:00'
   and s.booked = false
   and s.date >= (now() at time zone 'America/New_York')::date
   and not exists (
     select 1 from public.slots o where o.date = s.date and o.time = '18:00'
   );

-- 2) Future auto-filled weekdays use 3–5pm, 5–7pm and 6–8pm.
--    Note: 5–7pm and 6–8pm overlap by an hour.
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
        (d, '18:00', '2-hour session', 120)
      on conflict (date, time) do nothing;
    end if;
  end loop;

  insert into public.settings (key, value) values ('autofill_through', v_end::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;

grant execute on function public.autofill_slots() to anon, authenticated;
