package com.normalreviews.visits;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * "Is there a restaurant near this spot?" using the same restaurant map the app uses
 * (places/manifest.json + places/f/<tile>.json from the app's own website), kept on the phone for 30 days.
 * Only the map tile for the area is downloaded; the spot itself never leaves the phone.
 */
final class Food {
    static final double TILE = 0.25;
    static final long FRESH = 30L * 24 * 3600 * 1000;

    /** 1 = a restaurant within r meters, 0 = none, -1 = couldn't check (no connection yet) */
    static int check(Context c, String base, double lat, double lng, double r) {
        JSONObject tiles = manifest(c, base);
        if (tiles == null) return -1;
        Set<String> ids = new LinkedHashSet<>();
        for (double a : new double[]{-0.001, 0, 0.001})
            for (double b : new double[]{-0.0013, 0, 0.0013}) ids.add(id(lat + a, lng + b));
        boolean unknown = false;
        for (String id : ids) {
            JSONArray t = tiles.optJSONArray(id);
            if (t == null || t.optInt(0, 0) == 0) continue;                  /* no restaurants mapped in this tile */
            JSONArray p = tile(c, base, id);
            if (p == null) { unknown = true; continue; }
            for (int i = 0; i < p.length(); i++) {
                JSONArray a = p.optJSONArray(i);
                if (a == null) continue;
                if (Detector.meters(lat, lng, a.optDouble(0) / 1e5, a.optDouble(1) / 1e5) <= r) return 1;
            }
        }
        return unknown ? -1 : 0;
    }
    static String id(double la, double ln) { return (int) Math.floor(la / TILE) + "_" + (int) Math.floor(ln / TILE); }

    static JSONObject manifest(Context c, String base) {
        String s = cached(c, "manifest", 7L * 24 * 3600 * 1000, base, "/places/manifest.json");
        try { return s == null ? null : new JSONObject(s).optJSONObject("tiles"); } catch (Exception e) { return null; }
    }
    static JSONArray tile(Context c, String base, String id) {
        String s = cached(c, "f_" + id, FRESH, base, "/places/f/" + id + ".json");
        try { return s == null ? null : new JSONObject(s).optJSONArray("p"); } catch (Exception e) { return null; }
    }
    /* the cached copy if fresh, else a new download, else the old copy */
    static String cached(Context c, String name, long fresh, String base, String path) {
        File dir = new File(c.getFilesDir(), "nrtiles");
        if (!dir.exists()) dir.mkdirs();
        File f = new File(dir, name + ".json");
        String old = f.exists() ? read(f) : null;
        if (old != null && System.currentTimeMillis() - f.lastModified() < fresh) return old;
        if (base == null || base.isEmpty()) return old;
        try {
            HttpURLConnection h = (HttpURLConnection) new URL(base.replaceAll("/+$", "") + path).openConnection();
            h.setConnectTimeout(12000); h.setReadTimeout(20000);
            if (h.getResponseCode() == 200) {
                String body = readAll(h.getInputStream());
                if (body.trim().startsWith("{")) {
                    try (FileOutputStream o = new FileOutputStream(f)) { o.write(body.getBytes(StandardCharsets.UTF_8)); }
                    return body;
                }
            }
        } catch (Exception ignored) {}
        return old;
    }
    static String read(File f) { try (InputStream in = new FileInputStream(f)) { return readAll(in); } catch (Exception e) { return null; } }
    static String readAll(InputStream in) throws java.io.IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[16384]; int n;
        while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
        in.close();
        return b.toString("UTF-8");
    }
}
