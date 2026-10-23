# Social9 mobile — shared website UI

The shipping app loads **https://www.social9.io/login** in the device's system
WebView. The website is the single UI implementation: the app uses the real
responsive screens, not separate Flutter copies. Website updates become
available after they are deployed and the page reloads.

The website's same-origin `/service` proxy continues to use
**https://social9-backend-ghqu.onrender.com**. No backend credentials, provider
secrets, copied API implementation, or proxy CORS workaround are added to the
app. The website remains responsible for authentication, brand scope, roles,
plan entitlements, publishing and payment verification.

## What is shared

All website routes are available, including the dashboard/search/onboarding,
accounts, full composer/media editor/previews, personalized templates,
calendar/trend sources, content library, analytics/Growth Assistant,
agency/team/report tools, billing/coupons, recovery/verification, public pages,
and authorized admin screens. The same website permissions and coming-soon
restrictions apply. The app does not unlock admin or paid functionality.

## Native integrations

- Instagram, LinkedIn and Facebook authorization opens in the system browser.
  Return to Social9 after approval; the website session polls the same backend
  for changes. Authorization uses browser-owned Custom Tabs, not an embedded
  provider login, and no app-only banner covers the website.
- The Android document picker supports the website's multi-image/video inputs.
- CSV, edited-media and cover-image blob exports use the device's Save dialog.
  Acknowledged chunks stream into private temporary files without retaining the
  whole file in memory or imposing the previous 50 MB file-size cap. Normal
  navigation waits for the disk handoff; saving then belongs to Android and does
  not depend on the original page staying alive. Four transfers may be active
  at once; temporary files are removed after save/cancel or activity shutdown.
- Report **Print / Save as PDF** opens Android's print dialog using the actual
  live WebView document, preserving its print CSS, charts and fonts. There is
  no separate HTML snapshot or app-specific 10 MB snapshot cap.
- Razorpay uses native checkout on Android. The existing website creates the
  server-priced order and verifies the returned signature with Render; checkout
  success alone does not grant paid access. The website's theme options and
  gateway error descriptions are preserved. Cancellation clears the web busy state.
- Back closes an open web dialog/menu/video first, then navigates history. At
  the first page, back exits normally without an extra double-back prompt.
- The website owns its loading and normal error pages; there is no covering
  app spinner/banner or fixed 60-second document-loading cutoff. Network failures
  still provide recovery without clearing the session, and a late successful
  page load dismisses recovery automatically. Native system bars/background
  follow the website theme, cached locally to avoid a wrong-theme startup flash.
- `social9://verify-email?token=…`, `social9://reset-password?token=…` and
  `social9://accounts?connected=…` route into the appropriate website page.
  HTTPS association additionally requires deployment/signing setup below.

Only trusted HTTPS website origins are displayed inside the privileged viewer.
Other supported links open externally; insecure and local-file links are blocked.
The JavaScript/native channel validates its version, origin and a random
per-document secret so third-party payment frames cannot invoke device actions.
WebView debugging is disabled in release builds; Android backups are disabled.

## Run and build

Android 7.0 / API 24 or newer is required. Keep Android System WebView/Chrome
updated, especially for media codecs. No iOS build/signing target is delivered.

```powershell
flutter pub get
flutter run -d <android-device-id>
flutter build apk --release
```

The existing release signing configuration still uses the development key.
This APK is suitable for installation/testing, **not a store-signed release**.
Set up the final application ID and a private release keystore before distribution.

Browser builds preserve path, query and hash fragments when redirecting directly
to the website instead of framing it (the
website correctly forbids framing with CSP). Windows/Linux show an Open Social9
button; their embedded WebViews are not configured by this Android project.

```powershell
flutter run -d chrome --web-hostname localhost --web-port 3000
flutter build web --release
```

For a first-party HTTPS staging deployment with the same `/service` proxy:

```powershell
flutter run --dart-define=SOCIAL9_WEB_URL=https://your-staging.example
```

This is a **hosted** website shell, not an offline-bundled website. An internet
connection and a working website/backend are required. The first launch needs
a new sign-in: the old Flutter preferences are not copied into website storage.
"Keep me signed in" and sign-out now have exactly the website's behaviour.

An exact copy of website screens does not make OS-owned UI identical: Android's
file picker, print UI, browser authorization and payment SDK remain device UI.
Browser and WebView sessions are intentionally isolated; no browser credentials
are scraped/imported. Native Razorpay checkout is retained for supported mobile
payment methods rather than swapping in a less capable raw WebView checkout.

## HTTPS App Links / production prerequisites

The manifest handles website account callbacks and email verification/reset
links, but automatic Android routing is not complete until both production
hosts serve `.well-known/assetlinks.json` associating the final Android package
with the **release** signing certificate's SHA-256 fingerprint. Do not publish
development-key fingerprints as a production trust association.

The existing Render OAuth callback URLs are unchanged. OAuth works without
verified App Links by returning manually from the system browser and refreshing
Accounts. No provider approval, real payment, or live post is performed by tests.
See [device acceptance checklist](docs/MOBILE_ACCEPTANCE.md) before shipping.

## Checks

```powershell
flutter analyze
flutter test
node --test test/mobile_bridge_test.mjs
flutter build apk --release
flutter build web --release
```

The new shell/widget tests cover actual entry-point selection, startup, bridge
authentication, main-page versus subresource errors, recovery and navigation.
Policy/export tests cover host boundaries, deep links, redirect safety and binary
chunk assembly. JavaScript tests cover export interception, OAuth session scope,
native checkout callbacks and overlay/back behaviour. They are not substitutes
for provider/device end-to-end acceptance.

The previous Flutter implementation is preserved in `lib/legacy_app.dart` and
`lib/screen/` for reference. Its regression tests still run; those tests do not
prove functionality of the website shell. To inspect it deliberately:

```powershell
flutter run --dart-define=SOCIAL9_LEGACY_NATIVE=true
```
