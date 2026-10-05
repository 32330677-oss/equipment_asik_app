# Equipment Flow (ASIK) — Flutter app

One app, two experiences:

- **Admin / Accountant** (desktop or web): Live board, Attendance review, Paper sheets, Payroll, Fuel & adjustments, Machines (rate cards + "Test this price"), Vendors, Operators, Sites, Users, Settings, Audit log.
- **Supervisor** (phone): my sites today → day board (check in, pause, check out, whole-day status, submit) and rejected rows. Supervisors only record times; the accountant uploads the signed monthly sheets.

Supervisors never see prices.

## First run

The repository has no platform folders. Generate them once:

```bash
cd equipment_asik_app
flutter create --org com.asik --project-name equipment_asik_app --platforms android,ios,web,windows .
flutter pub get
flutter analyze
```

`flutter create .` keeps the existing `lib/`, `test/`, and `pubspec.yaml`.

## Run against the local backend

Start the backend first (`npm run dev` in `equipment_asik_backend`, port 5055). Then run one of:

```bash
# Web (Chrome)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5055/api

# Windows desktop
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:5055/api

# Android emulator (10.0.2.2 = your PC from inside the emulator)
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5055/api

# Real phone on the same Wi-Fi (use your PC's LAN IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5055/api
```

## Platform settings after `flutter create`

**Android** — `android/app/src/main/AndroidManifest.xml`:

- Add `<uses-permission android:name="android.permission.INTERNET"/>` above `<application>`.
- Add `android:usesCleartextTraffic="true"` to `<application>`. This is needed only while the server is plain `http://`; remove it once you use HTTPS.

**macOS / Windows / Web** need nothing extra. The backend allows all origins by default (`CORS_ORIGINS=*`).

## Structure

```
lib/core        api (dio + token), auth, theme, formatting, json readers, file save
lib/widgets     UI kit (ui.dart), pickers & form helpers (lookups.dart), PDF / file viewer
lib/shell       admin/accountant navigation
lib/screens     admin/  equipment/  supervisor/
```
