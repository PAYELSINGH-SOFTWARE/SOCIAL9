# vCueSocial9

vCueSocial9 is a Flutter client with a FastAPI backend for creating, scheduling, and managing Instagram and LinkedIn content.

## Backend

1. Copy `.env.example` to `.env` and replace every secret. The backend loads
   this file automatically; `.env` is ignored by Git.
2. Register the callback URLs in the Meta and LinkedIn developer portals.
3. Install and run:

```powershell
python -m pip install -r backened/requirements.txt
python -m uvicorn backened.main:app --reload
```

API documentation is available at `"https://social9-1.onrender.com/auth/login"social9-1.onrender.com/docs`.
## Instagram setup

The Instagram button uses Meta's **Instagram API with Instagram Login**. It
requires an Instagram professional account (Business or Creator).

1. In [Meta for Developers](https://developers.facebook.com/apps/), create or
   open a Business app and add the **Instagram** product.
2. In **Instagram > API setup with Instagram login**, copy the Instagram App
   ID and Instagram App Secret into your local `.env`:

   ```dotenv
   INSTAGRAM_CLIENT_ID=your-instagram-app-id
   INSTAGRAM_CLIENT_SECRET=your-instagram-app-secret
   INSTAGRAM_REDIRECT_URI="https://social9-1.onrender.com/auth/login"social9-1.onrender.com/accounts/instagram/callback
   ```

3. Add this exact value to **Valid OAuth Redirect URIs** in the Meta dashboard:
   `"https://social9-1.onrender.com/auth/login"social9-1.onrender.com/accounts/instagram/callback`. The host, port, scheme,
   path, and trailing slash must match exactly.
4. Enable `instagram_business_basic` and
   `instagram_business_content_publish`. While the Meta app is in Development
   mode, add the Instagram account under **App roles** and accept the invitation
   in Instagram. Switch the app Live only after the required permissions have
   passed App Review.
5. Restart the backend after changing `.env`, then click **Continue with
   Instagram**.

Do not paste the Instagram App Secret into Flutter/Dart code or commit `.env`.
For a deployed app, replace the loopback callback with an HTTPS backend URL and
register that exact production URL with Meta.

## Flutter client

```powershell
flutter pub get
flutter run
```

The development client uses `"https://social9-1.onrender.com/auth/login"social9-1.onrender.com`. Android emulators should use `http://10.0.2.2:8000` in the service files.

## OAuth security

OAuth state expires after ten minutes. Provider access and refresh tokens are encrypted before database storage. Use separate production values for `SOCIAL9_SECRET_KEY` and `SOCIAL9_TOKEN_ENCRYPTION_KEY` and never commit real credentials.