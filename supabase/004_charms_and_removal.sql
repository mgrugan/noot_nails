-- Noot Nails — update 004: charms/gems now $5, removal add-on $15
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.

-- ---------- Booking with price selection ----------
-- Prices live here so the total saved with a booking can't be tampered
-- with from the browser. Keep in sync with PRICES in index.html.
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
    when 'medium'  then 40
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
      when 'charms'  then 5
      when 'removal' then 15
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
