package com.normalreviews.visits;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** After a restart or an app update Android forgets our watchers; set them up again. */
public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c, Intent i) {
        String a = i.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) {
            Context app = c.getApplicationContext();
            PendingResult pr = goAsync();
            new Thread(() -> { try { Detector.register(app); } finally { pr.finish(); } }).start();
        }
    }
}
