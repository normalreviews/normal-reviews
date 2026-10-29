#!/usr/bin/env bash
# Builds a signed APK. Run from app/ (the GitHub workflow does this).
set -euo pipefail
npm install --no-audit --no-fund --legacy-peer-deps
node scripts/configure.js
rm -rf android
npx cap add android
node scripts/patch-android.js
command -v convert >/dev/null || sudo apt-get install -y -qq imagemagick
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  n=${d%%:*}; px=${d##*:}
  for f in ic_launcher ic_launcher_round; do convert ../site/icon-512.png -resize ${px}x${px} android/app/src/main/res/mipmap-$n/$f.png; done
done
rm -rf android/app/src/main/res/mipmap-anydpi-v26
npx cap sync android
cd android && chmod +x gradlew
./gradlew --no-daemon -q assembleRelease \
  -Pandroid.injected.signing.store.file="$PWD/../keystore/normal-reviews-beta.p12" \
  -Pandroid.injected.signing.store.password="$KEY_PW" \
  -Pandroid.injected.signing.key.alias=normalreviews \
  -Pandroid.injected.signing.key.password="$KEY_PW"
mkdir -p ../out
cp app/build/outputs/apk/release/app-release.apk "../out/$APK"
ls -la ../out
