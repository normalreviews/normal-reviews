package com.normalreviews.visits;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.google.android.gms.location.LocationResult;

/** A copy of a location some other app already asked for. Costs no extra battery. */
public class PassiveReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        if (!LocationResult.hasResult(i)) return;
        LocationResult r = LocationResult.extractResult(i);
        if (r == null) return;
        PendingResult pr = goAsync();
        Context app = c.getApplicationContext();
        new Thread(() -> { try { Detector.onPassive(app, r.getLocations()); } finally { pr.finish(); } }).start();
    }
}
