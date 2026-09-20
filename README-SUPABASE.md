# Little Clan Diary — Supabase-connected MVP

This build uses the real Supabase project configured for Little Clan.

## Included
- Supabase Auth login (email + password)
- Real PostgreSQL data
- RLS-based access control
- Admin dashboard
- Classes and children
- Weekly schedule
- Teacher observations
- Attendance
- Parent view limited by `child_parents`
- Weekly PDF via browser print dialog
- Mobile-friendly PWA shell

## Important
The browser contains only the Supabase **publishable** key. This is expected. Supabase documents that publishable keys are intended for browser/mobile apps; RLS controls what the signed-in user can access. Never put a `sb_secret_...` key in this file.

## Before first launch
1. In Supabase SQL Editor, run `data-api-grants.sql` once.
2. Make sure the admin Auth user exists and has a row in `public.profiles` with role `admin` and the Little Clan `school_id`.
3. Open `index.html` through a web server/hosting service. Do not rely on `file://` for the final deployment.

## Current limitation
Creating Auth users (teachers/parents) is intentionally not done from browser code. For now create the Auth user in Supabase Authentication, then create/link the profile. We can add a protected Edge Function invitation flow next.

## Security model
- Authentication: Supabase Auth
- Authorization: PostgreSQL RLS
- Browser key: publishable only
- No passwords are stored in the application database
- Parent access is determined by `child_parents`

## Local testing
A simple static server can serve this folder:

```bash
python3 -m http.server 8080
```

Then open `http://localhost:8080/`.
