package com.normalreviews.visits;

import android.Manifest;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

/** The bridge between the web app and the on-phone visit detector. */
@CapacitorPlugin(name = "VisitDetector", permissions = {
    @Permission(alias = "location", strings = {Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}),
    @Permission(alias = "background", strings = {"android.permission.ACCESS_BACKGROUND_LOCATION"}),
    @Permission(alias = "activity", strings = {"android.permission.ACTIVITY_RECOGNITION"}),
    @Permission(alias = "notifications", strings = {"android.permission.POST_NOTIFICATIONS"})
})
public class VisitDetectorPlugin extends Plugin {
    private boolean has(String alias) {
        if (("background".equals(alias) || "activity".equals(alias)) && Build.VERSION.SDK_INT < 29) return true;
        if ("notifications".equals(alias) && Build.VERSION.SDK_INT < 33) return true;
        return getPermissionState(alias) == PermissionState.GRANTED;
    }
    private JSObject perms() {
        JSObject o = new JSObject();
        for (String a : new String[]{"location", "background", "activity", "notifications"}) o.put(a, has(a));
        return o;
    }

    @PluginMethod public void status(PluginCall call) {
        JSObject r;
        try { r = new JSObject(Detector.status(getContext()).toString()); } catch (Exception e) { r = new JSObject(); }
        r.put("perms", perms());
        r.put("sdk", Build.VERSION.SDK_INT);
        call.resolve(r);
    }
    @PluginMethod public void ask(PluginCall call) {
        String w = call.getString("which", "location");
        if (has(w)) { JSObject r = new JSObject(); r.put("granted", true); call.resolve(r); return; }
        requestPermissionForAlias(w, call, "asked");
    }
    @PermissionCallback private void asked(PluginCall call) {
        JSObject r = new JSObject();
        r.put("granted", has(call.getString("which", "location")));
        call.resolve(r);
    }
    @PluginMethod public void start(PluginCall call) {
        Detector.start(getContext(), call.getString("base", ""), call.getInt("minDwell", 10));
        status(call);
    }
    @PluginMethod public void stop(PluginCall call) {
        Detector.stop(getContext());
        call.resolve();
    }
    @PluginMethod public void takeVisits(PluginCall call) {
        JSObject r = new JSObject();
        try { r.put("visits", new JSArray(Detector.take(getContext()).toString())); } catch (Exception e) { r.put("visits", new JSArray()); }
        call.resolve(r);
    }
    @PluginMethod public void setDeck(PluginCall call) {
        Detector.setDeck(getContext(), call.getInt("n", 0));
        call.resolve();
    }
    @PluginMethod public void openSettings(PluginCall call) {
        try {
            Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getContext().getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(i);
        } catch (Exception ignored) {}
        call.resolve();
    }
}
