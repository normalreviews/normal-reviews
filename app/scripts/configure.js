// Writes capacitor.config.json for the dev or live build (set by the GitHub workflow).
const fs = require('fs');
const env = process.env;
const cfg = {
  appId: env.APP_ID || 'com.normalreviews.app',
  appName: env.APP_NAME || 'Normal Reviews',
  webDir: 'www',
  // The app opens the hosted site, so ordinary updates arrive without reinstalling.
  server: { url: env.APP_URL || 'https://normal-reviews.pages.dev', androidScheme: 'https', cleartext: false },
  // Lets the page keep running briefly in the background (visit detection itself runs natively: native/visits).
  android: { useLegacyBridge: true }
};
fs.writeFileSync(__dirname + '/../capacitor.config.json', JSON.stringify(cfg, null, 2));
console.log('capacitor.config.json:', cfg.appId, cfg.server.url);
