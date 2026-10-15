# SHEGUARD — Flutter + FastAPI starter

Built for the Technophilia 7.0 Code2App Agent brief, SHESAFE@SCHOOL.

## Included
- Flutter welcome screen, concern categories, text entry and immediate-danger toggle
- Fictional demo scenario button
- Assessment result and trusted-support page
- FastAPI `/health` and `/assess` endpoints
- No database or intentional conversation persistence

## Important safety and privacy limits
This is a starter demo, not a production safeguarding service. The assessment is transparent keyword/rule logic, not a trained AI model. It can miss danger or flag messages incorrectly. Do not use it for disciplinary or safeguarding decisions and do not enter real student data.

The app sends message content to the configured backend for processing. This starter does not intentionally save messages, but server hosts, reverse proxies, or logs may retain request data depending on configuration. Disable sensitive request-body logging and verify privacy/security settings before any deployment. Involve school safeguarding and privacy professionals before real-world use.

## Start the backend
Python 3.10+ recommended.
uvicorn main:app --reload --host 0.0.0.0 --port 8000
flutter run -d chrome --dart-define=SHEGUARD_API_URL=http://127.0.0.1:8000
```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Health check: `http://127.0.0.1:8000/health`
Interactive API docs: `http://127.0.0.1:8000/docs`

## Run Flutter
Install Flutter and Android Studio / Android SDK.

```bash
cd flutter_app
flutter pub get
flutter run --dart-define=SHEGUARD_API_URL=http://10.0.2.2:8000
```

`10.0.2.2` reaches the host computer from an Android emulator. For a physical phone, use your computer's LAN IP and keep both devices on the same network. HTTP is for local development only; use HTTPS for deployed services.

## Build APK
From `flutter_app/`:

```bash
flutter build apk --release --dart-define=SHEGUARD_API_URL=http://YOUR-LAN-IP:8000
```

Expected output: `build/app/outputs/flutter-apk/app-release.apk`. The backend must be reachable from the Android device. A release APK configured with localhost will not reach your computer.

## Suggested 2-minute demo
1. Welcome and privacy-first design (15 sec).
2. Load fictional bullying scenario (15 sec).
3. Submit and explain suggested next steps (35 sec).
4. Toggle immediate danger with fictional text and show escalation (25 sec).
5. Open trusted support page (20 sec).
6. Show `/docs` and `/health` (10 sec).
