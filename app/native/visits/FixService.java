package com.normalreviews.visits;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import com.google.android.gms.location.CurrentLocationRequest;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;
import com.google.android.gms.tasks.CancellationTokenSource;

import java.util.ArrayList;
import java.util.List;

/**
 * Runs for about a minute and a half after you stop: waits a minute (so traffic lights don't count),
 * then takes up to 3 precise readings and hands them to Detector. Android shows a quiet notification while it runs.
 */
public class FixService extends Service {
    static volatile FixService running;
    final Handler h = new Handler(Looper.getMainLooper());
    final List<Location> got = new ArrayList<>();
    CancellationTokenSource cts;
    int tries = 0;
    boolean started = false, done = false;

    static void begin(Context c) {
        try { ContextCompat.startForegroundService(c, new Intent(c, FixService.class)); }
        catch (Exception e) {
            /* Android didn't allow it (rare): fall back to one ordinary reading */
            Detector.note(c, "Couldn't start the precise check; using a quick reading");
            quick(c);
        }
    }
    static void cancelRunning() { FixService s = running; if (s != null) s.h.post(() -> s.finish(false)); }

    @SuppressLint("MissingPermission")
    static void quick(Context c) {
        try {
            LocationServices.getFusedLocationProviderClient(c)
                .getCurrentLocation(new CurrentLocationRequest.Builder().setPriority(Priority.PRIORITY_HIGH_ACCURACY).setMaxUpdateAgeMillis(60_000).setDurationMillis(20_000).build(), null)
                .addOnCompleteListener(t -> {
                    List<Location> l = new ArrayList<>();
                    if (t.isSuccessful() && t.getResult() != null) l.add(t.getResult());
                    new Thread(() -> Detector.onFixes(c.getApplicationContext(), l)).start();
                });
        } catch (Exception ignored) {}
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationChannel ch = new NotificationChannel("nr_check", "Checking stops", NotificationManager.IMPORTANCE_MIN);
                ch.setShowBadge(false);
                ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
            }
            Notification n = new NotificationCompat.Builder(this, "nr_check")
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle("Normal Reviews")
                .setContentText("Checking if you stopped at a restaurant")
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setOngoing(true).build();
            if (Build.VERSION.SDK_INT >= 29) startForeground(71, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            else startForeground(71, n);
        } catch (Exception e) {
            Detector.note(this, "Couldn't start the precise check; using a quick reading");
            quick(getApplicationContext());
            stopSelf();
            return START_NOT_STICKY;
        }
        if (!started) {
            started = true; running = this;
            h.postDelayed(this::take, 60_000);
            h.postDelayed(() -> finish(true), 150_000);
        }
        return START_NOT_STICKY;
    }

    @SuppressLint("MissingPermission")
    void take() {
        if (done) return;
        tries++;
        cts = new CancellationTokenSource();
        try {
            LocationServices.getFusedLocationProviderClient(this)
                .getCurrentLocation(new CurrentLocationRequest.Builder().setPriority(Priority.PRIORITY_HIGH_ACCURACY).setMaxUpdateAgeMillis(0).setDurationMillis(25_000).build(), cts.getToken())
                .addOnCompleteListener(t -> {
                    if (done) return;
                    if (t.isSuccessful() && t.getResult() != null) got.add(t.getResult());
                    float best = 1e9f;
                    for (Location l : got) if (l.hasAccuracy()) best = Math.min(best, l.getAccuracy());
                    if (tries < 3 && !(got.size() >= 2 && best <= 20)) h.postDelayed(this::take, 8_000);
                    else finish(true);
                });
        } catch (Exception e) { finish(true); }
    }

    void finish(boolean use) {
        if (done) return;
        done = true;
        h.removeCallbacksAndMessages(null);
        if (cts != null) cts.cancel();
        final List<Location> g = new ArrayList<>(got);
        final Context app = getApplicationContext();
        if (!use) { end(); return; }
        new Thread(() -> {
            try { Detector.onFixes(app, g); } catch (Exception ignored) {}
            h.post(this::end);
        }).start();
    }
    void end() {
        running = null;
        try { if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE); else stopForeground(true); } catch (Exception ignored) {}
        stopSelf();
    }
    @Override public void onDestroy() { if (running == this) running = null; super.onDestroy(); }
    @Override public IBinder onBind(Intent intent) { return null; }
}
