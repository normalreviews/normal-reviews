// Adds permissions, the on-phone visit detector (native/visits), and the version number to the generated Android project.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'android', 'app');
const main = path.join(root, 'src', 'main');
const man = path.join(main, 'AndroidManifest.xml');
let m = fs.readFileSync(man, 'utf8');

const perms = [
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_BACKGROUND_LOCATION',     // "Allow all the time": notice stops while the app is closed
  'android.permission.ACTIVITY_RECOGNITION',           // motion sensor: still vs. moving (Android 10+)
  'com.google.android.gms.permission.ACTIVITY_RECOGNITION', // the same on Android 9 and older
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_LOCATION',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.RECEIVE_BOOT_COMPLETED'          // set the watchers up again after a restart
].filter(p => !m.includes(`"${p}"`)).map(p => `    <uses-permission android:name="${p}" />`).join('\n');
m = m.replace('</manifest>', `${perms}\n    <uses-feature android:name="android.hardware.location.gps" android:required="false" />\n</manifest>`);

const parts = `
        <receiver android:name="com.normalreviews.visits.ActivityReceiver" android:exported="false" />
        <receiver android:name="com.normalreviews.visits.GeofenceReceiver" android:exported="false" />
        <receiver android:name="com.normalreviews.visits.PassiveReceiver" android:exported="false" />
        <receiver android:name="com.normalreviews.visits.BootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
        <service android:name="com.normalreviews.visits.FixService" android:exported="false" android:foregroundServiceType="location" />
    </application>`;
if (!m.includes('com.normalreviews.visits.ActivityReceiver')) m = m.replace('</application>', parts);
fs.writeFileSync(man, m);

// the detector's code
const src = path.join(__dirname, '..', 'native', 'visits');
const dst = path.join(main, 'java', 'com', 'normalreviews', 'visits');
fs.mkdirSync(dst, { recursive: true });
for (const f of fs.readdirSync(src)) fs.copyFileSync(path.join(src, f), path.join(dst, f));

// register it with the app (Capacitor: local plugins are registered before super.onCreate)
function find(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { const r = find(p); if (r) return r; }
    else if (e.name === 'MainActivity.java') return p;
  }
  return null;
}
const act = find(path.join(main, 'java'));
if (!act) throw new Error('MainActivity.java not found');
let a = fs.readFileSync(act, 'utf8');
if (!a.includes('VisitDetectorPlugin')) {
  a = a.replace(/public class MainActivity extends BridgeActivity\s*\{\s*\}/,
    'public class MainActivity extends BridgeActivity {\n' +
    '    @Override\n' +
    '    public void onCreate(android.os.Bundle savedInstanceState) {\n' +
    '        registerPlugin(com.normalreviews.visits.VisitDetectorPlugin.class);\n' +
    '        super.onCreate(savedInstanceState);\n' +
    '    }\n' +
    '}');
  if (!a.includes('VisitDetectorPlugin')) throw new Error('Could not register VisitDetectorPlugin in ' + act + ':\n' + a);
  fs.writeFileSync(act, a);
}

// Google's on-phone location services (motion sensor, geofences, passive locations)
const gradle = path.join(root, 'build.gradle');
let g = fs.readFileSync(gradle, 'utf8');
if (!g.includes('play-services-location')) {
  g = g.replace(/dependencies\s*\{/, 'dependencies {\n    implementation "com.google.android.gms:play-services-location:21.3.0"');
}
const code = parseInt(process.env.VERSION_CODE || '1', 10);
g = g.replace(/versionCode\s+\d+/, `versionCode ${code}`).replace(/versionName\s+"[^"]*"/, `versionName "0.2.${code}"`);
fs.writeFileSync(gradle, g);
console.log('patched manifest, visit detector, MainActivity (' + act + '), gradle, version', code);
