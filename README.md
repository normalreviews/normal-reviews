# Normal Reviews (beta)

Honest restaurant scores from verified visits, curved so a 3.00 means normal.

- `site/` is the web app. Netlify publishes this folder to https://normalreviews.netlify.app
  - `index.html`: the whole app (screens, scoring, Timeline import, matching, Supabase sync)
  - `config.js`: Supabase project URL and publishable key (public by design)
  - `restaurants.json`, `places-other.txt`: Bay Area place lists used for on-device matching
    (Overture Maps Foundation; © OpenStreetMap contributors)
  - `privacy.html`: what testers share
- `setup.sql`: the Supabase database (tables, privacy rules, functions). Run once in the SQL Editor.
- `SETUP-CHECKLIST.md`: how the beta was set up.

Privacy rule for every change: Timelines, stops, times and non-restaurant places never leave the phone.
Only rated restaurants (place, visit day, tier, optional comment/reasons/photo) are stored.
