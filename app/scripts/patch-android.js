// Adds location permissions and the version number to the generated Android project.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'android', 'app');
const man = path.join(root, 'src', 'main', 'AndroidManifest.xml');
let m = fs.readFileSync(man, 'utf8');
const perms = [
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_LOCATION',
  'android.permission.POST_NOTIFICATIONS'
].filter(p => !m.includes(`"${p}"`)).map(p => `    <uses-permission android:name="${p}" />`).join('\n');
m = m.replace('</manifest>', `${perms}\n    <uses-feature android:name="android.hardware.location.gps" android:required="false" />\n</manifest>`);
fs.writeFileSync(man, m);
const gradle = path.join(root, 'build.gradle');
let g = fs.readFileSync(gradle, 'utf8');
const code = parseInt(process.env.VERSION_CODE || '1', 10);
g = g.replace(/versionCode\s+\d+/, `versionCode ${code}`).replace(/versionName\s+"[^"]*"/, `versionName "0.1.${code}"`);
fs.writeFileSync(gradle, g);
console.log('patched manifest and version', code);
