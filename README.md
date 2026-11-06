# UnivaPayment App

Merchant Android app for UnivaPayment (Flutter UI, with the SMS and sync code in Kotlin).

The merchant pairs the phone with a code from the dashboard. After that, the app sends bKash and Nagad SMS to the UnivaPayment API on its own, with the app closed, and keeps them queued while offline. It reads no other SMS. The API writes to Supabase; the phone holds only a revocable device token, encrypted with Android Keystore.

It can also produce a masked report of SMS formats, which stays on the phone unless copied.

## Build

- Emulator against a local server: `flutter run` (defaults to `http://10.0.2.2:3000`)
- Real phone: `flutter build apk --release --dart-define=API_URL=https://your-domain`. Release builds allow https only, and need a real signing key before going to merchants.

`flutter test` runs the masking and analysis tests.

## APK builds

Every push to `main` runs `.github/workflows/build-apk.yml`. It runs the tests, builds an arm64 APK, publishes it as a GitHub prerelease, and comments the download link on the commit.

- The `API_URL` repository variable sets the server address built into the APK.
- `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` hold the signing key. Keep `android/upload-keystore.jks` and `android/key.properties` backed up: they are not in git, and without that key an installed app cannot be updated.
