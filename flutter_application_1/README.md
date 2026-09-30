# Social9 Flutter client

This repository contains the Flutter app. It uses the separate, unchanged
Vivekkmr13/social9-backend API. Do not copy backend code or credentials here.

## Run

```powershell
flutter pub get
flutter run
```

The default API is https://social9-backend-ghqu.onrender.com, as documented in
the supplied backend ZIP. To choose another deployment, use an origin without
a trailing slash:

```powershell
flutter run --dart-define=SOCIAL9_API_URL=https://your-api.example.com
flutter build web --dart-define=SOCIAL9_API_URL=https://your-api.example.com
```

The configuration is in lib/screen/api_config.dart. Flutter does not load .env.
Never include database passwords, OAuth secrets, or token-encryption keys in
Flutter builds. The backend stays in its own repository and deployment.

## Integration behavior

- Email login/signup use /auth/login and /auth/signup. Signup returns a user,
  not a login token, so the app returns to sign-in after registration.
- Saved tokens are scoped to the API URL; old-backend sessions are ignored.
  Accounts and posts are not migrated between backend databases.
- Social sign-in is unavailable in this backend. Sign in using email, then
  connect Instagram or LinkedIn in Connected Accounts.
- Connections use /social-accounts and /social-accounts/provider-status;
  authorization uses POST /social-accounts/{provider}/connect. The existing
  backend redirects OAuth completion to its website. Return to Flutter and
  refresh Connected Accounts to see the result.
- Posts use /posts. Publish Now first creates a draft and then calls
  /posts/{id}/publish. HTTP success alone is not treated as published: the
  returned post status must also be published. If publishing fails, inspect
  Your Posts and retry the existing draft to avoid creating duplicates.
- MP4/MOV uploads select the backend video type; mixed image/video uploads
  remain subject to backend validation.
- Dashboard and publishing analytics use /analytics/summary. The old
  LinkedIn engagement endpoint does not exist in this backend, so the screen
  shows publishing counts, including separate provider and preview counts.
- Requests use the backend's default brand. This update does not add a brand
  switcher or change the existing local subscription screens.

## Deployment checks

Run flutter analyze and flutter test. Test real login, account connection,
draft creation, scheduling and publishing with a test account before release.
The production service URL comes from the supplied source; deployment health
and authenticated provider flows must be verified in your environment.
Flutter web requires its origin to be allowed by the backend's existing CORS
configuration. This change does not modify that configuration or backend repo.
It does not disconnect, delete, or redeploy any existing Render service.
