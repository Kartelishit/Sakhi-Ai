#Sakhi-AI — Flutter + FastAPI

Built for the Technophilia 7.0 Code2App Agent competition, under the SHESAFE@SCHOOL brief.

Sakhi Ai is an AI-assisted student support application designed to help students navigate bullying, online harassment, stress, discrimination and other difficult situations.

## Features

- Flutter-based Android application with concern categories and a conversational interface.
- Immediate-danger flag to help identify situations requiring urgent attention.
- AI-generated supportive responses using a pretrained language model.
- Prompt-based guidance focused on empathy, practical next steps and safety.
- Groq as the primary AI provider, with OpenRouter as a configurable fallback.
- Shareable message generation for contacting a parent or teacher.
- India-specific support resources and emergency information.
- FastAPI endpoints for health checks, assessments, chat and message summaries.
- No database persistence of conversations implemented in the backend code.

## Technology Stack

- Frontend: Flutter and Dart
- Backend: Python and FastAPI
- AI model: GPT-OSS-20B through Groq
- Additional AI provider: OpenRouter fallback
- Hosting: Render
- Platform: Android

The application uses a pretrained AI model and prompt engineering. The model was not trained from scratch by this project.

## API Endpoints

- `GET /health` — checks backend status and configured AI providers.
- `POST /assess` — generates a one-time support assessment.
- `POST /chat` — generates a conversational response using recent conversation history.
- `POST /summary` — generates a short message the student can send to a parent or teacher.
- `/docs` — interactive FastAPI API documentation.

## Safety and Privacy

Sakhi Ai is a school-project demonstration, not a production safeguarding service or a replacement for a trained counsellor, doctor, lawyer or emergency service.

AI responses may be inaccurate, incomplete or inappropriate. The urgency mechanism is not a validated emergency-detection system. The application must not be used as the sole basis for safeguarding or disciplinary decisions.

Use fictional demo scenarios during presentations. Do not enter real student-sensitive information.

The backend does not implement database persistence for conversations. However, messages are sent to the configured AI provider for processing. Hosting providers, AI services or infrastructure logs may process or retain request data according to their configurations and policies. Review these arrangements before real-world use.

The application does not automatically contact parents, teachers, police or emergency services.

## Environment Variables

Configure the required API keys in your local environment or your hosting provider's environment settings.

- `GROQ_API_KEY` — Groq API key.
- `OPENROUTER_API_KEY` — optional fallback provider key.
- `OPENROUTER_MODEL` — optional OpenRouter model override.

Never commit API keys or `.env` files to GitHub.

## Run the Backend Locally

Requirements: Python 3.10 or newer.

From the project root:

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Configure your Groq API key in the current terminal:

```bash
export GROQ_API_KEY="YOUR_GROQ_API_KEY"
```

Optionally configure OpenRouter:

```bash
export OPENROUTER_API_KEY="YOUR_OPENROUTER_API_KEY"
```

Start FastAPI:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Local URLs:

- Health check: `http://127.0.0.1:8000/health`
- API documentation: `http://127.0.0.1:8000/docs`

The AI endpoints require a valid configured provider key.

## Run Flutter Locally

Open a second terminal:

```bash
cd flutter_app
flutter pub get
```

To use a local backend from an Android emulator:

```bash
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

To run against the deployed Render backend:

```bash
flutter run --dart-define=API_URL=https://sheguard-ice5.onrender.com
```

The Android emulator uses `10.0.2.2` to access the host computer's local development server. A physical phone requires an address it can reach, or a deployed HTTPS backend.

## Build the Release APK

From the `flutter_app` directory:

```bash
flutter build apk --release --dart-define=API_URL=https://sheguard-ice5.onrender.com
```

Expected output:

`build/app/outputs/flutter-apk/app-release.apk`

The APK must be configured with a backend URL reachable from the device.

## Suggested Two-Minute Competition Demo

1. Introduce Solace and its privacy-first design.
2. Load a fictional bullying scenario.
3. Submit the scenario and explain the AI-generated guidance.
4. Demonstrate the immediate-danger flag using fictional data.
5. Show how the app creates a message for a trusted parent or teacher.
6. Demonstrate `/health` and `/docs`, and explain the Flutter-to-FastAPI-to-AI request flow.
