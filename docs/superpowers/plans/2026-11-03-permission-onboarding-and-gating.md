# Permission Onboarding & Active Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the premature redirect to Android settings, and implement a gentle, full-screen Permission Onboarding and Gating screen requiring all 4 core telecalling permissions (`READ_PHONE_STATE`, `READ_CALL_LOG`, `POST_NOTIFICATIONS`, `CALL_PHONE`) before allowing access to the application.

**Architecture:** 
1. Fix Android plugin `PhoneStateBackgroundPlugin.kt` permission request logic to invoke `ActivityCompat.requestPermissions` instead of immediately launching `ACTION_APPLICATION_DETAILS_SETTINGS`.
2. Implement unified `PermissionService` (or enhance `CallTrackingService` & `NotificationService`) to verify and request the Quad Permissions.
3. Build `PermissionScreen` with interactive permission tiles, live status indicators, auto-lifecycle resume detection, and an 'Open Device Settings' fallback.
4. Update `SplashScreen` and `HomeScreen` routing so the app gates access until all permissions are granted.

**Tech Stack:** Flutter / Dart, Kotlin, Android SDK (`ActivityCompat`, `ContextCompat`, `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`).

---

## Global Constraints

1. **Zero Premature Settings Redirect**: Opening the app must never abruptly open the device settings page without first presenting the gentle permission onboarding screen and requesting standard Android runtime dialogs.
2. **Mandatory Quad Permissions**:
   - `READ_PHONE_STATE`
   - `READ_CALL_LOG`
   - `POST_NOTIFICATIONS`
   - `CALL_PHONE`
3. **App Locked Until All Granted**: The app must not route to `LoginScreen` or `HomeScreen` until all 4 permissions are granted.
4. **Auto-Resume Detection**: When returning to CallNow from Android Settings, the app must automatically re-check and unlock seamlessly without requiring an app restart.
5. **Zero Regression**: All existing 34 tests must continue to pass, with `flutter analyze` reporting 0 issues.

---

## Review Focus

1. **Android First-Launch Bug in `PhoneStateBackgroundPlugin`**: `shouldShowRequestPermissionRationale` returning `false` on first launch must NOT be treated as "permanently denied".
2. **Android 13+ Notification Permissions**: On Android 12 and below, `POST_NOTIFICATIONS` does not exist and is granted by default; ensure checks don't fail on older Android versions.
3. **Lifecycle Observer Cleanup**: `PermissionScreen` and `HomeScreen` must properly add and remove `WidgetsBindingObserver` to prevent memory leaks.
4. **Direct Dialing (`CALL_PHONE`) vs Dialer Launch**: Verify `CALL_PHONE` permission is properly requested alongside `READ_PHONE_STATE` and `READ_CALL_LOG`.
5. **Back Button Trapping**: On Android, tapping the back button on `PermissionScreen` must not bypass the gate or leave the app in an invalid partial state.

---

## Task Decomposition

### Task 1: Fix Native Android Permission Request Logic in `phone_state_background`

**Files:**
- Modify: `packages/phone_state_background/android/src/main/kotlin/me/sodipto/phone_state_background/PhoneStateBackgroundPlugin.kt`
- Modify: `packages/phone_state_background/lib/phone_state_background.dart`

**Changes:**
- Fix `requestPermissions()` in `PhoneStateBackgroundPlugin.kt`:
  - Include `Manifest.permission.CALL_PHONE` alongside `READ_PHONE_STATE` and `READ_CALL_LOG`.
  - Always call `ActivityCompat.requestPermissions(currentActivity!!, permissionsToAsk, 999)` when permissions are ungranted, rather than jumping to `ACTION_APPLICATION_DETAILS_SETTINGS`.
  - Add explicit method `openAppSettings` so Flutter UI can open settings intentionally when the user taps the button.
  - Expose `checkPermissionDetails()` returning a map `{phone_state: bool, call_log: bool, call_phone: bool}`.

---

### Task 2: Unified Permission Service (`PermissionService`)

**Files:**
- Create: `lib/services/permission_service.dart`
- Create: `test/permission_service_test.dart`

**Interfaces:**
- Produces: `class PermissionService` with:
  - `static Future<PermissionStatusMap> checkAllPermissions()`
  - `static Future<bool> hasAllPermissions()`
  - `static Future<void> requestAllPermissions()`
  - `static Future<void> openSettings()`
- Manages: Phone State, Call Log, Call Phone, and Notification permissions with Android SDK level awareness.

---

### Task 3: Build Dedicated Permission Onboarding & Gating Screen (`PermissionScreen`)

**Files:**
- Create: `lib/screens/permission_screen.dart`
- Modify: `lib/main.dart` (Add `/permissions` route)

**UI & Behavior:**
- Hero icon and friendly onboarding header: "CallNow Needs Access to Connect Calls & Reminders".
- 4 interactive permission cards:
  1. **Phone Call Detection** (`READ_PHONE_STATE`)
  2. **Call Log & Talk-Time** (`READ_CALL_LOG`)
  3. **Direct Calling** (`CALL_PHONE`)
  4. **Callback Reminders** (`POST_NOTIFICATIONS`)
- Dynamic status badges: "Granted" (green check) or "Permission Required" (amber warning).
- Primary Action button:
  - "Grant Permissions" (triggers system dialogs).
  - Changes to "Open Device Settings" with guidance card if permissions are permanently suppressed.
- `WidgetsBindingObserver` listens to app resume and automatically unlocks when all permissions are granted.

---

### Task 4: Connect App Startup Flow & Active Guard

**Files:**
- Modify: `lib/widgets/splash_screen.dart`
- Modify: `lib/screens/home_screen.dart`

**Changes:**
- `SplashScreen`: Checks `PermissionService.hasAllPermissions()`. If false -> `Navigator.pushReplacementNamed(context, '/permissions')`. If true -> route to `/home` (if logged in) or `/login`.
- `HomeScreen`: On lifecycle resume, verifies `PermissionService.hasAllPermissions()`. If revoked -> routes to `/permissions`.

---

### Task 5: Testing, Build Verification & Static Analysis

**Files:**
- Create: `test/permission_screen_test.dart`
- Verify: Full test suite (`flutter test`), static analysis (`flutter analyze`), and APK build (`flutter build apk --debug -t lib/main.dart`).

