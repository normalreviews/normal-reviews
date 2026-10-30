package com.normalreviews.visits;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.location.Location;

import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingEvent;

/** You left the ~100 m circle around the place. */
public class GeofenceReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        GeofencingEvent e = GeofencingEvent.fromIntent(i);
        if (e == null || e.hasError() || e.getGeofenceTransition() != Geofence.GEOFENCE_TRANSITION_EXIT) return;
        Location l = e.getTriggeringLocation();
        long t = l != null && l.getTime() > 0 ? l.getTime() : System.currentTimeMillis();
        PendingResult pr = goAsync();
        Context app = c.getApplicationContext();
        new Thread(() -> { try { Detector.onExit(app, t); } finally { pr.finish(); } }).start();
    }
}
