# Little Clan Diary — production path

## Stack
- Static PWA hosted on GitHub Pages
- Supabase Auth + Postgres + RLS
- Web Push subscriptions + Supabase Edge Function
- Android Trusted Web Activity (TWA) via Bubblewrap

## Files
- `index.html` — app UI and Supabase client
- `manifest.webmanifest` — installable PWA manifest
- `sw.js` — offline shell + Web Push notifications
- `push-notifications.sql` — notifications, push subscriptions, RLS and triggers
- `supabase/functions/send-push/` — server-side Web Push sender
- `twa/` — Bubblewrap/TWA templates and instructions
- `.github/workflows/deploy-pages.yml` — automatic GitHub Pages deployment

## One-time Supabase steps
1. Run `push-notifications.sql` after the existing schema/grants.
2. Create/deploy the `send-push` Edge Function.
3. Set these Edge Function secrets:
   - `VAPID_PUBLIC_KEY`
   - `VAPID_PRIVATE_KEY`
   - `WEBHOOK_SECRET`
   - Supabase secret/service-role key (use the current secret key mechanism shown in your Dashboard).
4. Create a Database Webhook for `public.notifications` INSERT -> the `send-push` Edge Function and add header `x-webhook-secret: <same WEBHOOK_SECRET>`.

The browser only contains the Supabase publishable key and VAPID public key. Never put the Supabase secret/service-role key or VAPID private key into this repository.

## GitHub Pages
1. Create a public repository named `little-clan-diary` if using GitHub Free.
2. Upload the contents of this folder to the repository root.
3. Settings -> Pages -> Source -> GitHub Actions.
4. Push/commit to `main`; the included workflow deploys the site.
5. Your URL will be `https://YOUR-GITHUB-USERNAME.github.io/little-clan-diary/`.

## Android TWA
After the Pages URL works, follow `twa/README.md`. The final TWA must have Digital Asset Links at `/.well-known/assetlinks.json` using the release certificate SHA-256 fingerprint.
