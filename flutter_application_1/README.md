# Social9 Flutter app

The Flutter client uses the same live Render API as the Social9 website:
`https://social9-backend-ghqu.onrender.com`. Its deployed OpenAPI contract is
the source of truth; the local `../../social9-backend` checkout may be older.

## Included workspace features

- Email signup, login, session restore, logout, and password-reset requests
- Responsive overview with real publishing metrics and recommendations
- Instagram, LinkedIn, and Facebook connection, reconnection, and disconnection
- Browser authorization windows with account-status polling; native apps open
  the provider in the device browser and detect completion when returning
- Brand creation and switching with `X-Brand-ID` scope on workspace requests
- Composer with images/video, AI caption actions, drafts, scheduling, and
  immediate publishing
- The website's 26 templates, ranked by brand context and connected channels
- Searchable content library, post editing, month calendar, daily content ideas,
  AI plans, and action center
- Photo cropping, rotation, upload previews, and photo collages
- Instagram/Facebook insights, charts, CSV export, and growth scenarios
- Agency competitors, teams, approvals, revision history, and publishing reports
- Live plan pricing, coupons, browser/Android checkout, and server-verified access
- Live profile data and email verification/password recovery

Sign in with the same email and password used on Social9 web. Provider OAuth
connects a channel to this signed-in account from **Accounts**. The existing
Render callback URLs stay unchanged. After provider approval the backend saves
the connection; return to the app and it will refresh automatically. Browser
pop-ups must be allowed for this step.

## Run locally

```powershell
flutter pub get
flutter run -d chrome
```

Browser development uses `http://localhost:3000`, configured in
`web_dev_config.yaml`. The deployed API accepts this origin; Flutter's random
ports are rejected during the browser's CORS preflight. After changing this
configuration, stop the running Flutter app and start it again (hot reload
does not change the server port). For an explicit port selection, run:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 3000
```

The default API is `https://social9-backend-ghqu.onrender.com`. Point a build
at a local or alternate backend with a compile-time value:

```powershell
flutter run --dart-define=SOCIAL9_API_URL=http://127.0.0.1:8000
```

For an Android emulator, use `http://10.0.2.2:8000` instead of loopback.

## Verify

```powershell
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

`test/app_flows_test.dart` covers login-to-workspace navigation, brand scope,
expired sessions, provider connection contracts, publishing, and phone layouts.

Provider OAuth credentials, access tokens, and secrets belong in the backend;
never add them to Dart source or commit local `.env` files.
