# Normal Reviews beta: setup checklist

About 1–1.5 hours, no coding. If anything shows red error text, copy it (or take a screenshot) and send it to Claude.

**In this folder**
- `site/` is the app. This whole folder goes to Netlify.
- `setup.sql` is the database setup, pasted into Supabase once.
- `SETUP-CHECKLIST.md` is this file.

---

## Part A: Supabase, your shared database (30–45 min)

1. Go to **supabase.com** → **Start your project** → sign up with your business email.
2. Click **New project**:
   - Name: `normal-reviews-beta`
   - Database password: click **Generate** and save it in your password manager (you won't need it day to day)
   - Region: **West US** (closest to the Bay Area)
   - Plan: Free
   - Wait about 2 minutes while it sets up.
3. Left sidebar → **SQL Editor** → **New query**.
   Open `setup.sql` in a text editor, copy everything, paste it in, and click **Run**.
   ✅ You should see **"Success. No rows returned."**
4. **Make sign-in emails include a code.** Typing a code is more reliable on phones than tapping a link, because email apps often open links in the wrong browser.
   Left sidebar → **Authentication** → **Emails** (sometimes called *Email Templates*):
   - Open the **Magic Link** template and replace the message with:
     ```
     <h2>Your Normal Reviews code</h2>
     <p>Enter this code in the app: <b>{{ .Token }}</b></p>
     ```
     Click **Save**.
   - Do the same for the **Confirm signup** template. New testers get this one the first time.
5. **Authentication** → **Sign In / Providers** → check that **Email** is turned on (it is by default).
6. **Copy your two keys.** Go to **Project Settings** (gear icon) → **API** (may be called *Data API* or *API Keys*):
   - **Project URL**, which looks like `https://abcdxyz.supabase.co`
   - **anon public** key, a long text starting with `eyJ…`
     If you only see a **publishable** key (`sb_publishable_…`), look for a **Legacy API keys** tab and copy the **anon** key there. If there isn't one, use the publishable key and tell Claude if sign-in fails.

   The anon key is designed to be public. Your data is protected by the privacy rules from step 3, not by hiding this key.

## Part B: Put your keys in the app (5 min)

7. Open `site/config.js` with a plain text editor:
   - **Windows:** right-click → Open with → **Notepad**
   - **Mac:** right-click → Open With → **TextEdit**
8. Replace the two `PASTE_…` values with your Project URL and anon key. Keep the quote marks. Save.

   It should look like:
   ```
   window.NR_CONFIG = {
     url: "https://abcdxyz.supabase.co",
     key: "eyJhbGciOi...(long)..."
   };
   ```

## Part C: Put it online with Netlify (10 min)

9. Go to **app.netlify.com** and **sign up** (free), ideally with your business email. Sign up *before* uploading, or the site disappears after an hour.
10. **Add new site** → **Deploy manually**, then drag the **`site`** folder onto the page. Drag that folder only, not the zip or the outer folder.
11. Netlify gives you an address like `https://random-words-123.netlify.app`.
    Optional: **Site configuration** → **Change site name** → `normal-reviews-beta` gives `https://normal-reviews-beta.netlify.app` (if that name is free).
12. Back in **Supabase** → **Authentication** → **URL Configuration**:
    - **Site URL:** your Netlify address
    - **Redirect URLs:** add the same address
    - Save.

## Part D: Test it yourself first (10 min)

13. On your Android phone, open your Netlify address in **Chrome**.
14. Sign in: type your email → check your inbox → type the code → choose the name friends will see.
15. Chrome menu **⋮** → **Add to Home screen** (or **Install app**). It now opens full-screen like an app.
16. Import your Timeline and rate one visit.
17. Check it worked: Supabase → **Table Editor** → **ratings**. You should see one row with the restaurant, the day and your rating, and no stop times or other locations.

## Part E: Invite your testers

18. Send each tester:
    - your Netlify address
    - the privacy page: your address + `/privacy.html`
    - the Timeline export steps: **Settings → Location → Location services → Timeline → Export Timeline data**
19. Testers sign in and add each other on the **Friends** tab using **friend codes**.
20. **Email limit:** Supabase's free built-in email sender only sends a few emails per hour. If a tester doesn't get their code, wait an hour and try again. Each person only signs in once per phone. If this gets in the way, Claude can walk you through connecting a free email service.

---

## Later

- **Updating the app:** when Claude sends you new files, go to Netlify → your site → **Deploys** and drag the new `site` folder in. Keep your edited `config.js`.
- **See your data:** Supabase → **Table Editor** → `profiles`, `friends`, `ratings`.
- **Free plan pausing:** free Supabase projects pause after about a week with no activity. Click **Restore** in the dashboard if that happens, or move to the paid plan (~$25/month) when the beta is active.
- **The old Claude link** keeps working as a just-for-you version, separate from this one. Unshare it if you haven't (Share → Unshare).
