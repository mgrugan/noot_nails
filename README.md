# Noot Nails

Static site for Noot Nails, served with GitHub Pages.

Live site: https://nootnails.com (also https://mgrugan.github.io/noot_nails/)

## Booking backend (Supabase)

Slots, bookings and admin sign-in are stored in [Supabase](https://supabase.com) (free tier is fine).
The page holds no passwords — admin access is enforced by database rules.

1. Create a project at supabase.com.
2. **SQL Editor** → paste the contents of [`supabase/setup.sql`](supabase/setup.sql) → **Run**.
3. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up".
4. **Authentication → Users → Add user**: your email + a strong password, tick *Auto Confirm User*.
5. Back in the SQL Editor, make that user the admin:
   ```sql
   insert into public.admins (user_id)
     select id from auth.users where email = 'you@example.com';
   ```
6. **Project Settings → API**: copy the *Project URL* and the *anon public* key into
   `SUPABASE_URL` and `SUPABASE_ANON_KEY` near the bottom of `index.html`.
   (The anon key is designed to be public; the rules in `setup.sql` decide what it can do.)

7. Run [`supabase/002_sessions_and_pricing.sql`](supabase/002_sessions_and_pricing.sql) the same way
   (automatic weekday 2-hour sessions 3–9pm + the price picker).
8. Run [`supabase/003_medium_price_and_notify.sql`](supabase/003_medium_price_and_notify.sql)
   (Medium → $40, booking emails to noor.nagi07@gmail.com).
9. Run [`supabase/004_charms_and_removal.sql`](supabase/004_charms_and_removal.sql)
   (charms/gems → $5, removal add-on $15).
10. Run [`supabase/005_short_xl_prices.sql`](supabase/005_short_xl_prices.sql)
    (Short → $35, XL → $45).
11. Run [`supabase/006_server_side_booking_email.sql`](supabase/006_server_side_booking_email.sql)
    (booking emails sent by the database instead of the visitor's browser).
12. Run [`supabase/007_cancel_booking.sql`](supabase/007_cancel_booking.sql)
    (admins can cancel a booking; its time goes back into availability).
13. Run [`supabase/008_evening_6_to_8.sql`](supabase/008_evening_6_to_8.sql)
    (open 7–9pm sessions move to 6–8pm; future auto-fill uses 6pm).
14. Run [`supabase/009_two_sessions_3_and_6.sql`](supabase/009_two_sessions_3_and_6.sql)
    (only 3–5pm and 6–8pm each weekday; supersedes 008).

Then open the site → **Admin** (footer) → sign in with that email and password.
