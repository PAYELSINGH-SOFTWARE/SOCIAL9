# SOCIAL9

The Flutter client is in [flutter_application_1](flutter_application_1).
It connects to the independently deployed
[Social9 backend](https://github.com/Vivekkmr13/social9-backend).

The duplicate `social9-backend` directory has been removed from this repository.
Backend code, database migrations, secrets and backend hosting belong to the
separate repository. This change does not modify or redeploy that repository.

## Run the client

```powershell
cd flutter_application_1
flutter pub get
flutter run
```

The configured API is `https://social9-backend-ghqu.onrender.com`.
See the [client README](flutter_application_1/README.md) for API overrides,
OAuth behavior, supported features and deployment checks.

## Build for the web

```powershell
cd flutter_application_1
flutter build web --release
```

Deploy the contents of `flutter_application_1/build/web` to your frontend host.
The frontend's origin must be allowed by the existing backend CORS settings.
Do not point the backend service at this frontend-only repository.
