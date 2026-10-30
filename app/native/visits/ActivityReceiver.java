package com.normalreviews.visits;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.google.android.gms.location.ActivityTransitionResult;

/** The motion sensor changed: still, or moving again. */
public class ActivityReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        if (!ActivityTransitionResult.hasResult(i)) return;
        ActivityTransitionResult r = ActivityTransitionResult.extractResult(i);
        if (r == null) return;
        PendingResult pr = goAsync();
        Context app = c.getApplicationContext();
        new Thread(() -> { try { Detector.onActivity(app, r.getTransitionEvents()); } finally { pr.finish(); } }).start();
    }
}
