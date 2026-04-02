# Guest Welcome Attendance App

A modern Flutter mobile and web application for managing guest attendance, member tracking, programs, and reports with real-time synchronization via Supabase.

## 📱 Platform Support

- Android (native)
- iOS (native)
- Web (Chrome, Safari, etc.)
- macOS
- Windows
- Linux

## 🏗️ Project Structure

```
Guest-Welcome-attendance-app/
├── flutter_app/              # Main Flutter application
│   ├── lib/                  # Dart source code
│   │   ├── app.dart          # App configuration
│   │   ├── main.dart         # Entry point
│   │   ├── router.dart       # Navigation routes
│   │   ├── app_theme/        # UI theme
│   │   ├── core/             # Core utilities (logging, config, date utils)
│   │   ├── features/         # Feature modules (auth, home, sessions, etc.)
│   │   ├── models/           # Data models and enums
│   │   ├── providers/        # Riverpod state management
│   │   ├── services/         # Business logic (API, database)
│   │   └── widgets/          # Reusable UI components
│   └── pubspec.yaml          # Dependencies
├── supabase/                 # Backend & database
│   ├── config.toml
│   └── migrations/           # SQL migrations
├── scripts/                  # Utility scripts
├── docs/                     # Documentation
├── reports/                  # Report outputs
├── nextjs-backup.zip         # Legacy Next.js backup (archived)
└── README.md

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.16+ ([Download](https://flutter.dev/docs/get-started/install))
- Dart SDK (included with Flutter)
- Supabase project setup

### Setup Environment

1. **Clone the repository:**
   ```bash
   git clone <repo-url>
   cd Guest-Welcome-attendance-app
   ```

2. **Install Flutter dependencies:**
   ```bash
   cd flutter_app
   flutter pub get
   ```

3. **Configure Supabase credentials:**
   ```bash
   cd flutter_app && flutter run \
     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```

### Running the App

**Android/iOS:**
```bash
cd flutter_app
flutter run
```

**Web:**
```bash
cd flutter_app
flutter run -d chrome
```

**Desktop (macOS/Windows/Linux):**
```bash
cd flutter_app
flutter run -d macos  # or windows, linux
```

## 📚 Features

- **Member Management** — Register, search, and manage members
- **Attendance Tracking** — QR-based check-ins with real-time sync
- **Programs** — Create and manage Sunday/Wednesday programs
- **Sessions** — Manage service sessions with automatic generation
- **Reports** — View attendance statistics, attendance trends, member reports
- **Offline Support** — Works offline with SQLite, syncs when online
- **Multi-team Support** — Team A, Team B, Team C with role-based access
- **Real-time Updates** — Powered by Supabase RealtimeDatabase

## 🏭 Building for Production

### Android:
```bash
cd flutter_app
flutter build apk --release
# or for App Bundle:
flutter build appbundle --release
```

### iOS:
```bash
cd flutter_app
flutter build ios --release
```

### Web:
```bash
cd flutter_app
flutter build web --release
```

## 🔒 Security

- **Row-Level Security (RLS)** — Database queries protected by Supabase RLS policies
- **Public Anon Key** — Safely used with RLS (credentials not sensitive)
- **Test Mode** — Available in Settings for local testing without timing gates
- **Offline-First** — Local SQLite cache before syncing to server

## 📊 Database

Managed via [Supabase](https://supabase.com):
- Migrations located in `supabase/migrations/`
- RLS policies protect all tables
- Real-time subscriptions for live updates

Apply migrations:
```bash
cd supabase
supabase db push
```

## 🧪 Testing

Unit tests available in `flutter_app/test/`

```bash
flutter test
```

## 📋 Scripts

Located in `scripts/`:
- `run_flutter_analyze.py` — Dart analysis
- `push_migration.sh` — Deploy Supabase migrations
- `run_analyze.sh` — Code analysis
- `write_tests.py` — Test utilities

## ⚙️ Configuration

Environment variables (use `--dart-define`):
- `SUPABASE_URL` — Your Supabase project URL
- `SUPABASE_ANON_KEY` — Public anon key from Supabase

## 📝 Notes

- **Next.js legacy:** The original Next.js implementation has been archived (see `nextjs-backup.zip`)
- **Production ready:** Debug features are disabled by default
- **Test mode:** Toggle in Settings → Test Mode for development/testing

## 📞 Support

For issues or feature requests, please refer to the documentation in `docs/` or contact the development team.
