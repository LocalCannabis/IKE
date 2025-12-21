# IKE - Flutter Dev App

Flutter development app for rapid UI prototyping and workflow validation.
Part of the LocalCannabis ecosystem.

**Note:** This is a DEV/PREVIEW app only. Production will use Kotlin + Jetpack Compose.

## Running

```bash
# Ensure backend is running first
cd ../backend && source .venv/bin/activate && python run.py

# Run Flutter in Chrome
cd tablet_app
flutter run -d chrome --web-port=8080
```

## Purpose

- Rapid prototyping and iteration
- Chrome preview = instant feedback
- Proves out UX patterns before Kotlin port
- NOT for production deployment
