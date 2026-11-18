# CallNow 5.0

A cross-platform Flutter application for managing client call data and loan/financial product enquiries. Built for field agents and sales teams to track call history, manage client records, and maintain enquiry pipelines efficiently.

## Features

- **Splash Screen** - branded loading experience
- **User Authentication** - login and password reset
- **Client Data Management** - track client name, mobile, company, package, status, call by, call time, and upload date
- **Call History** - view and manage call activity records
- **Enquiry Management** - create, update, and delete financial product enquiries
- **Company Search** - search and filter company lists
- **Fresh Data Sync** - fetch latest data from Google Sheets via API
- **Settings** - user preferences and app configuration

## Tech Stack

- **Framework**: Flutter (>=3.1.3 <4.0.0)
- **Language**: Dart
- **State Management**: Stateless/Stateful widgets (scaffold)
- **Typography**: Google Fonts (Aclonica)
- **Icons**: Cupertino Icons, Material Icons
- **Platforms**: Android, iOS, Web, Windows, Linux, macOS

## Project Structure

```
lib/
  main.dart                 # App entry point and home scaffold
  model/
    client_data_model.dart  # Client data JSON model
    enquiry_model.dart      # Enquiry JSON model
  services/
    web_url.dart            # API endpoint constants
  widgets/
    SplashScreen.dart       # Splash screen widget
assets/
  iclauncher.png            # App launcher icon
  images/
    whatsapp.png            # WhatsApp integration icon
android/                    # Android platform code
ios/                        # iOS platform code
web/                        # Web platform code
windows/                    # Windows platform code
linux/                      # Linux platform code
macos/                      # macOS platform code
test/
  widget_test.dart          # Widget tests
```

## Multi-Tenant Authentication & Dynamic Routing

CallNow 5.0 supports multi-tenant database routing via company codes:

### 1. Login with Company Code
The login screen accepts a **Company Code** (e.g. `incredit` or `acme`), which is sent in the login payload:
```http
POST /api/v1/auth/login
Content-Type: application/json
X-Company-Code: incredit

{
  "company_code": "incredit",
  "email": "telecaller@company.com",
  "password": "Password123"
}
```

### 2. Encrypted Local Storage
- Backed by platform secure storage: **Android Keystore (EncryptedSharedPreferences)** and **iOS Keychain**.
- The `company_code` is remembered locally so users do not need to re-type it upon subsequent logins.

### 3. Automatic Request Routing (`X-Company-Code`)
All subsequent authenticated requests made via `ApiService` automatically attach the header:
```http
Authorization: Bearer <token>
X-Company-Code: <stored_company_code>
```
The server routes requests directly to that company's isolated database.

---

## API Endpoints

Backend API base URL: `https://starsinfotech.in/callnow/FLUTTER_API.php?apicall=`

| Endpoint | Purpose |
|----------|---------|
| `LOGIN` | User authentication |
| `RESET_PASSWORD` | Change user password |
| `COMPANY_LIST` | Fetch/search company list |
| `SPLASH_SCREEN` | Splash screen config |
| `DIAL_DATA_ACTIVITY` | Call activity data |
| `NEW_DATA_REQUEST` | Request new data |
| `USER_DATA_UPDATE` | Update user/client data |
| `MY_ENQUIRIES` | Fetch user enquiries |
| `UPDATE_ENQUIRY` | Update an enquiry |
| `DELETE_ENQUIRY` | Delete an enquiry |
| `ADD_ENQUIRY` | Create a new enquiry |
| `GET_GOOGLE_SHEET_DATA` | Sync fresh data from Google Sheets |

## Getting Started

### Prerequisites

- Flutter SDK (>=3.1.3)
- Dart SDK (>=3.1.3)
- Android Studio / Xcode (for mobile builds)
- VS Code or IntelliJ IDEA

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd callnow_new
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

### Build

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release
```

## Documentation

- [Native Calling Engine Architecture](docs/NATIVE_CALLING_ENGINE.md) — Comprehensive technical guide detailing the Android telephony state machine, CallLog ContentProvider verification, OOM crash recovery, and privacy guard mechanisms.

## Configuration

- Update API base URL in `lib/services/web_url.dart` if needed.
- Replace app launcher icon in `assets/iclauncher.png`.
- Configure app label and bundle ID in platform-specific folders (`android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`).

## Version

- Current version: **1.0.0+1**
- Display title: **CallNow 5.0**

## License

Private / Proprietary - Not published to pub.dev.