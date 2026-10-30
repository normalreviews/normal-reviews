package com.normalreviews.visits;

import android.annotation.SuppressLint;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.os.Build;
import android.os.SystemClock;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import com.google.android.gms.location.ActivityRecognition;
import com.google.android.gms.location.ActivityTransition;
import com.google.android.gms.location.ActivityTransitionEvent;
import com.google.android.gms.location.ActivityTransitionRequest;
import com.google.android.gms.location.DetectedActivity;
import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingRequest;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Visit detection, all on the phone.
 *
 * The motion sensor says when you become still. About a minute later FixService takes a few precise readings,
 * and Food checks the spot against the restaurant map. No restaurant nearby: the stop is forgotten at once.
 * Restaurant nearby: the spot and arrival time are kept, and a ~100 m geofence tells us when you leave.
 * A stay of 10+ minutes becomes a "visit", waiting for the app to pick it up (deleted after 48 hours if it doesn't).
 * Locations other apps already computed ("passive") confirm you're still there, notice you leaving,
 * and catch stops the motion sensor missed. Raw locations are never stored; only the spot you're at right now.
 */
public final class Detector {
    static final String PREFS = "nr_visits";
    static final Object LOCK = new Object();
    static final long MIN = 60_000L, HOUR = 60 * MIN;

    /* ---------- state (app-private storage) ---------- */
    static JSONObject load(Context c) {
        try { return new JSONObject(c.getSharedPreferences(PREFS, 0).getString("s", "{}")); }
        catch (Exception e) { return new JSONObject(); }
    }
    static void save(Context c, JSONObject s) {
        c.getSharedPreferences(PREFS, 0).edit().putString("s", s.toString()).commit();
    }
    static void log(JSONObject s, String msg) {
        try {
            JSONArray a = s.optJSONArray("log");
            if (a == null) a = new JSONArray();
            JSONObject e = new JSONObject();
            e.put("t", System.currentTimeMillis());
            e.put("m", msg);
            a.put(e);
            JSONArray b = new JSONArray();
            for (int i = Math.max(0, a.length() - 40); i < a.length(); i++) b.put(a.get(i));
            s.put("log", b);
        } catch (Exception ignored) {}
    }
    static String phase(JSONObject s) { return s.optString("phase", "moving"); }
    static void put(JSONObject o, String k, Object v) { try { o.put(k, v); } catch (Exception ignored) {} }

    static double meters(double la1, double ln1, double la2, double ln2) {
        double dy = (la1 - la2) * 110540, dx = (ln1 - ln2) * Math.cos(la1 * Math.PI / 180) * 111320;
        return Math.hypot(dx, dy);
    }
    static long wallTime(long elapsedNanos) {
        return System.currentTimeMillis() - (SystemClock.elapsedRealtimeNanos() - elapsedNanos) / 1_000_000L;
    }
    static PendingIntent pi(Context c, Class<?> cls, int code) {
        int f = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
        return PendingIntent.getBroadcast(c, code, new Intent(c, cls), f);
    }
    static boolean granted(Context c, String p) {
        return ContextCompat.checkSelfPermission(c, p) == PackageManager.PERMISSION_GRANTED;
    }

    /* ---------- on / off ---------- */
    static void start(Context c, String base, int minDwell) {
        synchronized (LOCK) {
            JSONObject s = load(c);
            boolean was = s.optBoolean("enabled");
            put(s, "enabled", true);
            if (base != null && !base.isEmpty()) put(s, "base", base);
            put(s, "minDwell", Math.max(1, minDwell));
            if (!was) { put(s, "phase", "moving"); log(s, "Visit detection on"); }
            save(c, s);
        }
        register(c);
    }
    static void stop(Context c) {
        unregister(c);
        FixService.cancelRunning();
        c.getSharedPreferences(PREFS, 0).edit().clear().commit();
    }

    @SuppressLint("MissingPermission")
    static void register(Context c) {
        JSONObject s0 = load(c);
        if (!s0.optBoolean("enabled")) return;
        try {
            List<ActivityTransition> t = new ArrayList<>();
            t.add(tr(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            t.add(tr(DetectedActivity.STILL, ActivityTransition.ACTIVITY_TRANSITION_EXIT));
            t.add(tr(DetectedActivity.WALKING, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            t.add(tr(DetectedActivity.RUNNING, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            t.add(tr(DetectedActivity.ON_BICYCLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            t.add(tr(DetectedActivity.IN_VEHICLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER));
            ActivityRecognition.getClient(c)
                .requestActivityTransitionUpdates(new ActivityTransitionRequest(t), pi(c, ActivityReceiver.class, 1))
                .addOnFailureListener(e -> note(c, "Couldn't watch for stops (motion): " + e.getMessage()));
        } catch (Exception e) { note(c, "Couldn't watch for stops (motion): " + e.getMessage()); }
        try {
            LocationRequest r = new LocationRequest.Builder(Priority.PRIORITY_PASSIVE, 60_000L).build();
            LocationServices.getFusedLocationProviderClient(c)
                .requestLocationUpdates(r, pi(c, PassiveReceiver.class, 2))
                .addOnFailureListener(e -> note(c, "Couldn't listen for other apps' locations: " + e.getMessage()));
        } catch (Exception e) { note(c, "Couldn't listen for other apps' locations: " + e.getMessage()); }
        synchronized (LOCK) {
            JSONObject s = load(c);
            JSONObject st = s.optJSONObject("stop");
            if ("here".equals(phase(s)) && st != null) addFence(c, st);
        }
    }
    static ActivityTransition tr(int type, int dir) {
        return new ActivityTransition.Builder().setActivityType(type).setActivityTransition(dir).build();
    }
    @SuppressLint("MissingPermission")
    static void unregister(Context c) {
        try { ActivityRecognition.getClient(c).removeActivityTransitionUpdates(pi(c, ActivityReceiver.class, 1)); } catch (Exception ignored) {}
        try { LocationServices.getFusedLocationProviderClient(c).removeLocationUpdates(pi(c, PassiveReceiver.class, 2)); } catch (Exception ignored) {}
        removeFence(c);
    }
    static void note(Context c, String m) {
        synchronized (LOCK) { JSONObject s = load(c); if (!s.optBoolean("enabled")) return; log(s, m); save(c, s); }
    }

    /* ---------- the leave-the-spot fence ---------- */
    @SuppressLint("MissingPermission")
    static void addFence(Context c, JSONObject st) {
        try {
            float r = (float) Math.max(100, Math.min(250, st.optDouble("acc", 30) * 2));
            Geofence g = new Geofence.Builder().setRequestId(fenceId(st))
                .setCircularRegion(st.optDouble("lat"), st.optDouble("lng"), r)
                .setExpirationDuration(7 * HOUR)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_EXIT)
                .setNotificationResponsiveness(60_000)
                .build();
            GeofencingRequest req = new GeofencingRequest.Builder().setInitialTrigger(0).addGeofence(g).build();
            LocationServices.getGeofencingClient(c).addGeofences(req, pi(c, GeofenceReceiver.class, 3))
                .addOnFailureListener(e -> note(c, "Couldn't watch for leaving (will check on the next stop instead)"));
        } catch (Exception e) { note(c, "Couldn't watch for leaving (will check on the next stop instead)"); }
    }
    static String fenceId(JSONObject st) { return "s" + st.optLong("start"); }
    /* all of them (turning off) */
    static void removeFence(Context c) {
        try { LocationServices.getGeofencingClient(c).removeGeofences(pi(c, GeofenceReceiver.class, 3)); } catch (Exception ignored) {}
    }
    /* just this stop's, so a new stop's fence added right after isn't caught by the removal */
    static void removeFence(Context c, JSONObject st) {
        try { LocationServices.getGeofencingClient(c).removeGeofences(Collections.singletonList(fenceId(st))); } catch (Exception ignored) {}
    }

    /* ---------- housekeeping on every event ---------- */
    static void tidy(Context c, JSONObject s) {
        long now = System.currentTimeMillis();
        JSONObject st = s.optJSONObject("stop");
        if ("here".equals(phase(s)) && st != null && now - st.optLong("start") > 6 * HOUR) {
            close(c, s, st.optLong("last", st.optLong("start")));
        }
        if ("settling".equals(phase(s)) && now - s.optLong("settleAt") > 10 * MIN) put(s, "phase", "moving");
        JSONArray p = s.optJSONArray("pending");
        if (p != null) {
            JSONArray q = new JSONArray();
            for (int i = 0; i < p.length(); i++) { JSONObject v = p.optJSONObject(i); if (v != null && now - v.optLong("end") < 48 * HOUR) q.put(v); }
            if (q.length() != p.length()) { put(s, "pending", q); log(s, (p.length() - q.length()) + " visit(s) not picked up in 48 hours · deleted"); }
        }
    }

    /* ---------- motion ---------- */
    static void onActivity(Context c, List<ActivityTransitionEvent> events) {
        List<ActivityTransitionEvent> ev = new ArrayList<>(events);
        Collections.sort(ev, (a, b) -> Long.compare(a.getElapsedRealTimeNanos(), b.getElapsedRealTimeNanos()));
        for (ActivityTransitionEvent e : ev) {
            long t = wallTime(e.getElapsedRealTimeNanos());
            boolean still = e.getActivityType() == DetectedActivity.STILL && e.getTransitionType() == ActivityTransition.ACTIVITY_TRANSITION_ENTER;
            if (still) onStill(c, t); else onMove(c, t);
        }
    }
    static void onStill(Context c, long t) {
        boolean fix = false;
        synchronized (LOCK) {
            JSONObject s = load(c);
            if (!s.optBoolean("enabled")) return;
            tidy(c, s);
            String ph = phase(s);
            if ("here".equals(ph)) {
                JSONObject st = s.optJSONObject("stop");
                if (st != null && st.has("moved") && t - st.optLong("moved") > 3 * MIN) {
                    /* you moved for a while and stopped again: still at the same place, or somewhere new? */
                    put(s, "recheck", true); put(s, "stillAt", t); put(s, "settleAt", System.currentTimeMillis()); fix = true;
                } else if (st != null) { st.remove("moved"); put(st, "last", t); }
            } else if (!"settling".equals(ph)) {
                put(s, "phase", "settling"); put(s, "stillAt", t); put(s, "settleAt", System.currentTimeMillis()); s.remove("recheck");
                fix = true;
            }
            save(c, s);
        }
        if (fix) FixService.begin(c);
    }
    static void onMove(Context c, long t) {
        boolean cancel = false;
        synchronized (LOCK) {
            JSONObject s = load(c);
            if (!s.optBoolean("enabled")) return;
            tidy(c, s);
            String ph = phase(s);
            if ("settling".equals(ph)) { put(s, "phase", "moving"); cancel = true; }
            else if ("other".equals(ph)) put(s, "phase", "moving");
            else if ("here".equals(ph)) {
                JSONObject st = s.optJSONObject("stop");
                if (st != null && !st.has("moved")) put(st, "moved", t);
                if (s.optBoolean("recheck")) { s.remove("recheck"); cancel = true; }
            }
            save(c, s);
        }
        if (cancel) FixService.cancelRunning();
    }

    /* ---------- the precise readings after you stop (called off the main thread) ---------- */
    static void onFixes(Context c, List<Location> fixes) {
        double[] pt = average(fixes);
        JSONObject s0 = load(c);
        if (!s0.optBoolean("enabled")) return;
        if (pt == null) {
            synchronized (LOCK) {
                JSONObject s = load(c);
                if ("settling".equals(phase(s))) { put(s, "phase", "other"); log(s, "Stopped · no good location reading, skipped"); }
                s.remove("recheck");
                save(c, s);
            }
            return;
        }
        /* moved somewhere new after a stay? close the old one first */
        synchronized (LOCK) {
            JSONObject s = load(c);
            JSONObject st = s.optJSONObject("stop");
            if (s.optBoolean("recheck") && "here".equals(phase(s)) && st != null) {
                s.remove("recheck");
                if (meters(st.optDouble("lat"), st.optDouble("lng"), pt[0], pt[1]) <= 150) {
                    st.remove("moved"); put(st, "last", System.currentTimeMillis()); save(c, s); return;
                }
                close(c, s, st.optLong("moved", st.optLong("last")));
                put(s, "phase", "settling");
                save(c, s);
            } else if (!"settling".equals(phase(s))) return;
        }
        int food = Food.check(c, s0.optString("base", ""), pt[0], pt[1], Math.max(60, pt[2]));
        synchronized (LOCK) {
            JSONObject s = load(c);
            if (!"settling".equals(phase(s))) return;
            arrive(c, s, pt, s.optLong("stillAt", System.currentTimeMillis()), food, "Stopped");
            JSONObject an = s.optJSONObject("anchor");
            if (an != null && meters(an.optDouble("lat"), an.optDouble("lng"), pt[0], pt[1]) < 80) put(an, "done", true);
            save(c, s);
        }
    }
    static double[] average(List<Location> fixes) {
        double w = 0, la = 0, ln = 0, best = 1e9;
        for (Location l : fixes) {
            float a = l.hasAccuracy() ? l.getAccuracy() : 50;
            if (a > 60) continue;
            double k = 1.0 / Math.max(25, a * a);
            w += k; la += k * l.getLatitude(); ln += k * l.getLongitude(); best = Math.min(best, a);
        }
        if (w == 0) {
            Location b = null;
            for (Location l : fixes) if (l.hasAccuracy() && l.getAccuracy() <= 150 && (b == null || l.getAccuracy() < b.getAccuracy())) b = l;
            return b == null ? null : new double[]{b.getLatitude(), b.getLongitude(), b.getAccuracy()};
        }
        return new double[]{la / w, ln / w, best};
    }
    /* food: 1 restaurant nearby, 0 none (forget), -1 couldn't check (keep; the app decides) */
    static void arrive(Context c, JSONObject s, double[] pt, long start, int food, String how) {
        if (food == 0) {
            put(s, "phase", "other"); s.remove("stop");
            log(s, how + " · no restaurant nearby, forgotten");
            return;
        }
        JSONObject st = new JSONObject();
        put(st, "lat", pt[0]); put(st, "lng", pt[1]); put(st, "acc", pt[2]);
        put(st, "start", start); put(st, "last", System.currentTimeMillis()); put(st, "food", food);
        put(s, "stop", st); put(s, "phase", "here");
        addFence(c, st);
        log(s, how + (food == 1 ? " · restaurant nearby" : " · couldn't check the map yet, the app will"));
    }

    /* ---------- leaving ---------- */
    static void onExit(Context c, long t) {
        synchronized (LOCK) {
            JSONObject s = load(c);
            if (!s.optBoolean("enabled")) return;
            JSONObject st = s.optJSONObject("stop");
            if (!"here".equals(phase(s)) || st == null) return;
            long moved = st.optLong("moved", 0);
            close(c, s, moved > 0 && t - moved < 20 * MIN ? moved : t);
            save(c, s);
        }
    }
    static void close(Context c, JSONObject s, long end) {
        JSONObject st = s.optJSONObject("stop");
        s.remove("stop"); s.remove("recheck"); put(s, "phase", "moving");
        if (st == null) return;
        removeFence(c, st);
        long start = st.optLong("start");
        long mins = (end - start) / MIN;
        int min = s.optInt("minDwell", 10);
        if (mins >= min && mins <= 360) {
            JSONArray p = s.optJSONArray("pending");
            if (p == null) p = new JSONArray();
            JSONObject v = new JSONObject();
            put(v, "lat", st.optDouble("lat")); put(v, "lng", st.optDouble("lng")); put(v, "acc", st.optDouble("acc"));
            put(v, "start", start); put(v, "end", end); put(v, "food", st.optInt("food", -1));
            p.put(v); put(s, "pending", p);
            log(s, "Left after " + mins + " min · visit saved for the app");
            nudge(c, s);
        } else if (mins < min) log(s, "Left after " + Math.max(0, mins) + " min · too short, forgotten");
        else log(s, "Stay over 6 hours · forgotten");
    }

    /* ---------- other apps' locations (no extra battery) ---------- */
    static void onPassive(Context c, List<Location> locs) {
        double[] check = null; long t0 = 0;
        synchronized (LOCK) {
            JSONObject s = load(c);
            if (!s.optBoolean("enabled")) return;
            tidy(c, s);
            int min = s.optInt("minDwell", 10);
            List<Location> ls = new ArrayList<>(locs);
            Collections.sort(ls, (a, b) -> Long.compare(a.getTime(), b.getTime()));
            for (Location l : ls) {
                float acc = l.hasAccuracy() ? l.getAccuracy() : 100;
                if (acc > 100) continue;
                long t = l.getTime();
                String ph = phase(s);
                JSONObject st = s.optJSONObject("stop");
                if ("here".equals(ph) && st != null) {
                    double d = meters(st.optDouble("lat"), st.optDouble("lng"), l.getLatitude(), l.getLongitude());
                    if (d <= Math.max(60, acc * 1.5)) { put(st, "last", Math.max(st.optLong("last"), t)); continue; }
                    if (acc <= 50 && d > 150) {
                        long moved = st.optLong("moved", 0);
                        close(c, s, moved > 0 && t - moved < 20 * MIN ? moved : t);
                    } else continue;
                }
                JSONObject an = s.optJSONObject("anchor");
                if (an != null && meters(an.optDouble("lat"), an.optDouble("lng"), l.getLatitude(), l.getLongitude()) <= Math.max(60, acc * 1.5)) {
                    put(an, "t1", t);
                    if (acc <= 40) {
                        int n = an.optInt("n", 1);
                        put(an, "lat", (an.optDouble("lat") * n + l.getLatitude()) / (n + 1));
                        put(an, "lng", (an.optDouble("lng") * n + l.getLongitude()) / (n + 1));
                        put(an, "n", n + 1); put(an, "acc", Math.min(an.optDouble("acc", acc), acc));
                    }
                    boolean idle = "moving".equals(phase(s)) || "other".equals(phase(s));
                    if (!an.optBoolean("done") && idle && t - an.optLong("t0") >= min * MIN) {
                        put(an, "done", true);
                        check = new double[]{an.optDouble("lat"), an.optDouble("lng"), an.optDouble("acc", acc)};
                        t0 = an.optLong("t0");
                    }
                } else {
                    JSONObject a = new JSONObject();
                    put(a, "lat", l.getLatitude()); put(a, "lng", l.getLongitude()); put(a, "acc", acc);
                    put(a, "t0", t); put(a, "t1", t); put(a, "n", 1);
                    put(s, "anchor", a);
                }
            }
            save(c, s);
        }
        if (check != null) {
            JSONObject s0 = load(c);
            int food = Food.check(c, s0.optString("base", ""), check[0], check[1], Math.max(60, check[2]));
            synchronized (LOCK) {
                JSONObject s = load(c);
                String ph = phase(s);
                if ("moving".equals(ph) || "other".equals(ph)) {
                    arrive(c, s, check, t0, food, "Stop found from other apps' locations");
                    save(c, s);
                }
            }
        }
    }

    /* ---------- handing visits to the app ---------- */
    static JSONArray take(Context c) {
        synchronized (LOCK) {
            JSONObject s = load(c);
            tidy(c, s);
            JSONArray p = s.optJSONArray("pending");
            if (p == null) p = new JSONArray();
            put(s, "pending", new JSONArray());
            if (p.length() > 0) log(s, p.length() + " visit(s) handed to the app");
            save(c, s);
            return p;
        }
    }
    static JSONObject status(Context c) {
        synchronized (LOCK) {
            JSONObject s = load(c);
            JSONObject r = new JSONObject();
            put(r, "enabled", s.optBoolean("enabled"));
            put(r, "phase", phase(s));
            JSONArray p = s.optJSONArray("pending");
            put(r, "pending", p == null ? 0 : p.length());
            JSONArray lg = s.optJSONArray("log");
            put(r, "log", lg == null ? new JSONArray() : lg);
            return r;
        }
    }
    static void setDeck(Context c, int n) {
        synchronized (LOCK) { JSONObject s = load(c); put(s, "deck", n); save(c, s); }
    }

    /* ---------- "visits to rate" reminder ---------- */
    static void nudge(Context c, JSONObject s) {
        JSONArray p = s.optJSONArray("pending");
        int n = (p == null ? 0 : p.length()) + s.optInt("deck", 0);
        long now = System.currentTimeMillis();
        if (n < 5 || now - s.optLong("nudged", 0) < 20 * HOUR) return;
        if (Build.VERSION.SDK_INT >= 33 && !granted(c, "android.permission.POST_NOTIFICATIONS")) return;
        try {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 26)
                nm.createNotificationChannel(new NotificationChannel("nr_remind", "Visits to rate", NotificationManager.IMPORTANCE_DEFAULT));
            Intent open = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
            PendingIntent tap = open == null ? null : PendingIntent.getActivity(c, 9, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            NotificationCompat.Builder b = new NotificationCompat.Builder(c, "nr_remind")
                .setSmallIcon(android.R.drawable.star_on)
                .setContentTitle(n + " visits to rate")
                .setContentText("Swipe through them while you still remember the food.")
                .setAutoCancel(true);
            if (tap != null) b.setContentIntent(tap);
            nm.notify(5005, b.build());
            put(s, "nudged", now);
        } catch (Exception ignored) {}
    }
}
