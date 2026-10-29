# Normal Reviews (beta)

Honest restaurant scores from verified visits, curved so a 3.00 means normal.

- `site/` is the web app. Netlify publishes this folder to https://normalreviews.netlify.app
  - `index.html`: the whole app (screens, scoring, Timeline import, matching, Supabase sync)
  - `config.js`: Supabase project URL and publishable key (public by design)
  - `places/`: restaurant and other-place maps for CA, OR, WA, NV in 0.25° tiles, fetched only
    for the areas around a user's stops and matched on the phone (Overture Maps Foundation;
    © OpenStreetMap contributors). `manifest.json` lists tiles; `f/` has restaurants with names,
    `o/` has other places (location and type only)
  - `privacy.html`: what testers share
- `tools/build_tiles.py`: rebuilds `site/places/` from the Overture notebook output
- `setup.sql`: the Supabase database (tables, privacy rules, functions). Run once in the SQL Editor.
- `SETUP-CHECKLIST.md`: how the beta was set up.

Privacy rule for every change: Timelines, stops, times and non-restaurant places never leave the phone.
Only rated restaurants (place, visit day, tier, optional comment/reasons/photo) are stored.

Matching rules (in `index.html`, `judge()`): a restaurant within 15 m names the stop (best fit for the
length and time of the stay wins, others become one-tap fixes); a non-food place more than 5 m closer
skips it; nothing within 15 m skips it, unless it was a 40+ minute mealtime stay with restaurants within
40 m, which asks "Were you at…". Skipped stops can be restored.
