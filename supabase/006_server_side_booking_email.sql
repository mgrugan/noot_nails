-- Noot Nails — update 006: send the booking email from the database
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.
--
-- Before: the customer's browser sent the email after booking, which can
-- silently fail (blocked request, page closed early). Now book_slot() queues
-- it on the server with pg_net, so every saved booking emails the studio.
-- It also stops sending the studio's email address to the customer's browser.

create extension if not exists pg_net;

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
    when 'short'   then 35
    when 'medium'  then 40
    when 'long'    then 40
    when 'xl'      then 45
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

  -- Email the studio. pg_net queues the request and sends it right after
  -- the booking is saved; a mail problem never blocks the booking itself.
  select value into v_notify from public.settings where key = 'notify_email';
  if v_notify is not null and v_notify like '%@%' then
    begin
      perform net.http_post(
        url     := 'https://formsubmit.co/ajax/' || v_notify,
        body    := jsonb_build_object(
          '_subject',    'New booking: ' || p_name || ' — ' || to_char(s.date, 'FMDay, FMMonth FMDD'),
          '_template',   'box',
          '_captcha',    'false',
          'name',        p_name,
          'email',       p_email,
          'phone',       p_phone,
          'appointment', to_char(s.date, 'FMDay, FMMonth FMDD') || ' at ' || lower(to_char(s.time, 'FMHH12:MIAM')),
          'service',     case p_nail_service
                           when 'short' then 'Short' when 'medium' then 'Medium' when 'long' then 'Long'
                           when 'xl' then 'XL' when 'natural' then 'Natural nails' end
                         || coalesce(' + ' || nullif(array_to_string(array(
                              select case x
                                when 'french' then 'Basic French' when 'dots' then 'Dots / stripes'
                                when 'art' then 'Nail art' when '3d' then '3D gel art'
                                when 'charms' then 'Charms / gems' when 'removal' then 'Existing nail removal'
                                else x end
                              from unnest(p_designs) x), ', '), ''), ''),
          'total',       '$' || v_total || ' (paid in person)',
          'notes',       coalesce(nullif(p_notes, ''), 'None')
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Accept',       'application/json',
          'Referer',      'https://nootnails.com/',
          'Origin',       'https://nootnails.com'
        )
      );
    exception when others then
      raise warning 'booking email not queued: %', sqlerrm;
    end;
  end if;

  return json_build_object('total', v_total);
end;
$$;

revoke all on function public.book_slot(uuid, text, text, text, text, text, text[]) from public;
grant execute on function public.book_slot(uuid, text, text, text, text, text, text[]) to anon, authenticated;
