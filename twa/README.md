# Little Clan Diary — Android TWA

The Android app is a Trusted Web Activity (TWA) around the PWA. Bubblewrap generates the Android project and signed APK/AAB from the live Web Manifest.

## After GitHub Pages is live

1. Install Node.js 14.15+ and Bubblewrap:
   `npm i -g @bubblewrap/cli`
2. From this folder run:
   `bubblewrap init --manifest="https://YOUR-GITHUB-USERNAME.github.io/little-clan-diary/manifest.webmanifest" --directory=./android`
3. During init use package id `school.littleclan.diary`, app name `Little Clan Diary`, launcher name `Little Clan`.
4. Keep the generated keystore PRIVATE. Never commit `android-keystore/`.
5. Build:
   `cd android && bubblewrap build`
6. Bubblewrap produces a signed APK and App Bundle and can generate the Digital Asset Links data. Digital Asset Links are required for verified fullscreen TWA operation.
7. Put the final fingerprint into `.well-known/assetlinks.json` at the root of the GitHub Pages site.

For a Play Store release, keep the signing/upload keys safe and use the AAB rather than the debug APK.
