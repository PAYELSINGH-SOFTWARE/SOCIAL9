# Mobile acceptance — website shell

## Implementation and scope

The app displays the deployed Social9 website, not the local source checkout or
an offline bundle. This eliminates separate mobile feature implementations and
CSS drift. Native integrations live in `lib/app/`, `assets/mobile_bridge.js` and
Android `MainActivity.kt`. Website access control remains authoritative.

All signed-in and public routes are first-party pages, including admin tools
for authorized administrators. Future networks remain unavailable exactly as
on the website. No production database, account, post, payment or provider
permission is modified by automated tests.

## Automated coverage

- Shipping entry point loads the canonical website, not the old Flutter login.
- Only the configured HTTPS origin and legitimate production alias are trusted.
- Lookalike domains, local file/data/script navigations, and external redirects
  through crafted app links are rejected.
- Bridge messages need the matching per-document secret and top-level origin.
- Ordinary links are unaffected; blob exports stream exact binary bytes,
  acknowledged ordered chunks and sanitized filenames to temporary disk storage.
  There is no fixed file-size cap; available device storage still applies.
  Up to four transfers may be active concurrently. Normal page navigation waits
  for disk handoff so destroying the JavaScript page cannot truncate the file.
- Provider polling uses the website token and selected brand only in page-side
  fetches. Tokens are never sent to the native message channel or another host.
- The website's signed-order/payment-verification workflow is retained. Native
  callbacks reach the original success/error/dismiss callbacks once only.
- Page errors offer recovery. Thumbnail/subresource failures do not blank the app.
- Back respects open dialog cancellation, menu and fullscreen content.

## Required Android device acceptance

These are **not** checked merely because compilation or a mock test passed.
No connected Android device was available during implementation.

## Verification completed on 2026-10-23

- `flutter analyze`: no issues.
- `flutter test`: 44 passed (17 preserved legacy regression tests,
  15 original policy/export tests, 7 shipping-shell tests and 5 parity refinements).
- `node --test test/mobile_bridge_test.mjs`: 15 passed.
- Android debug APK, optimized APK and browser release build compiled.
- Website `/service/health` and the required Render `/health`: HTTP 200.
- User signed into the real website for a 390 × 844 browser check. Dashboard,
  ten-section mobile menu, composer/live caption preview, templates, account
  setup, analytics/Growth Assistant, agency/report access and calendar loaded.
  Checked composer/templates/analytics/agency/calendar document widths did not
  exceed the viewport. The temporary test caption was cleared without saving.
- Instagram, Facebook and LinkedIn showed live-configured connection buttons;
  no provider consent was submitted. The current free account's premium/report
  restrictions were preserved, not bypassed or represented as working paid flows.
- HTTPS association URL currently returns 404, so automatic verified Android
  links require the release setup described below.

Browser checks verify the shared website UI, not native Android file selection,
codec support, payment, printing or social-consent completion on a device.

### Version 1.1.1 refinements

- Removed covering app loading UI, persistent authorization banner, forced
  60-second loading cutoff and root double-back prompt. Keep network recovery.
- Follow/cache the website theme for native background and system bars.
- Preserve browser-launcher hash fragments, not only the path/query.
- Pass website checkout theme options through and preserve gateway errors.
- Stream exports to private files with acknowledgements; remove the old 50 MB
  in-memory exporter from the shipping path. The earlier `BridgeDownload` helper
  remains exercised by historical tests but is no longer the shipping exporter.
- Print the live WebView document rather than a capped HTML copy.
- Retain the provider/payment SDK safeguards. OS-owned dialogs, separate browser
  storage, signing/domain association and real-device validation are not eliminated
  by sharing the website UI. Do not claim this is a certified zero-difference build.

### Device checks still required

- [ ] Install the new APK and confirm website branding, keyboard behaviour,
      rotation, safe areas and scrolling on narrow and wide screens.
- [ ] Sign in with a website account; restart with "Keep me signed in" enabled.
      Sign out and verify the protected screens require authentication again.
- [ ] Switch/add brands intentionally; confirm the expected brand data appears.
- [ ] Connect Instagram, LinkedIn and Facebook with approved accounts. Verify
      cancellation, returning from the browser, reconnect and disconnect.
- [ ] Pick several photos and an MP4. Exercise crops, filters, text, collage
      undo, carousel/video previews and a video trim with audio. WebCodecs/audio
      export capability depends on the installed WebView and input codec.
- [ ] Explicitly save a disposable draft, edit it and test a scheduled post in a
      controlled account. Confirm provider delivery, not just local success UI.
- [ ] Exercise personalized templates and the paid AI strategy/results tools
      with an entitled account; verify free-plan restrictions separately.
- [ ] Export analytics/competitor/report CSV and video-cover JPG through Save.
      Confirm filenames and bytes. Cancel the Save dialog and retry.
- [ ] Open report Print / Save as PDF and inspect pagination/styles in preview.
- [ ] Use an explicitly authorized Razorpay test transaction; verify paid access
      only after backend verification. Cancel checkout and test a failed payment.
      Do not make a real charge without the account owner's explicit approval.
- [ ] Open verification/reset links and social callback links. Custom schemes
      work when launched; automatic HTTPS links additionally need association.
- [ ] Go offline and retry after reconnecting; verify session/draft preservation
      where the website supports it, no duplicate publishing/payment requests.
- [ ] Test system back in a dialog, mobile menu, fullscreen video and root page.
- [ ] Verify authorized admin screens with an admin account; verify ordinary
      users cannot gain admin access.

## Distribution and HTTPS link association

The current package remains `com.example.flutter_application_1` to preserve
compatibility with the earlier test APK. Release builds still use the existing
development signing configuration. Choose a final application ID and private
release key before store distribution; do not silently rotate a deployed key.

For the final package/certificate, publish this structure at the HTTPS hosts in
the manifest, using the real release fingerprint (or Play App Signing fingerprint
when distributing through Play):

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "YOUR_FINAL_APPLICATION_ID",
      "sha256_cert_fingerprints": ["YOUR_RELEASE_CERTIFICATE_SHA256"]
    }
  }
]
```

This file is intentionally not deployed with a development fingerprint. Domain
verification requires website deployment and final release-signing identity.
Provider/backend approval requirements are unchanged by using the website UI.
