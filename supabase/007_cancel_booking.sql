-- Noot Nails — update 007: admins can cancel a booking
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.
--
-- Deletes the booking and puts its time back into availability:
-- re-opens the original slot, or re-creates it if that slot was deleted.

create or replace function public.cancel_booking(p_booking_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  b public.bookings%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Not allowed.';
  end if;

  delete from public.bookings where id = p_booking_id returning * into b;
  if not found then
    raise exception 'Booking not found — it may already be cancelled.';
  end if;

  if b.slot_id is not null then
    update public.slots set booked = false where id = b.slot_id;
    if found then return; end if;
  end if;

  -- original slot is gone: re-create it (skip if another slot already starts then)
  insert into public.slots (date, time, service, duration_minutes)
  values (b.date, b.time, coalesce(b.service, '2-hour session'), 120)
  on conflict (date, time) do nothing;
end;
$$;

revoke all on function public.cancel_booking(uuid) from public;
grant execute on function public.cancel_booking(uuid) to authenticated;
