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

Then open the site → **Admin** (footer) → sign in with that email and password.
