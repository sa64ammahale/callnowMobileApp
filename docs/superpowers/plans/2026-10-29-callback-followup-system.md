# Client Callback Notifications & Follow-Up Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an automated callback reminder notification system ("model notification" / local heads-up push alert and in-app modal) that alerts telecallers at the exact scheduled callback time, coupled with a complete client Follow-Up Management Pipeline across the mobile application.

**Architecture:** A local reactive `FollowupService` persists callbacks in `SharedPreferences` and synchronizes with CRM `next_followup` logs. A `NotificationService` leverages `flutter_local_notifications` and exact Android alarms for heads-up reminders with direct "Call Now" actions. A foreground watchdog triggers the rich `CallbackAlertDialog` modal in-app. The `CallingDeskScreen` is enhanced with one-tap quick-scheduling chips, and a new `FollowUpScreen` provides a dedicated dashboard categorized into Overdue, Today, Upcoming, and Completed callbacks.

**Tech Stack:** Flutter (Dart 3.10+), `flutter_local_notifications: ^18.0.1`, `timezone: ^0.9.4`, `shared_preferences`, `url_launcher`.

**Spec:** User request: "IF SOME CUSTOMER SAYS ILL CALL YOU BACK/CALL ME AFTER SOMETIME/ CALL BACK ETC SO WE AHVE CREATE A PROPER PLAN WHICH SEND PROPER MODEL NOTIFICATION TO APP USER AND TELL HIMS TO CALL ON SPECIFIC TIME. Also we need to create proper follow up plan for all clients in the app /plan"

---

## Global Constraints

- Android API target: Minimum Android 21+, verified on Android 14/15/17 (API 34-37, Google Pixel 9).
- Android 13+ runtime permission `android.permission.POST_NOTIFICATIONS` must be explicitly requested before scheduling notifications.
- Android 12+ / 14+ exact alarms (`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`) must be declared in `AndroidManifest.xml` to guarantee timely delivery.
- All callback data must persist across app kills and phone reboots via `SharedPreferences` JSON storage.
- Zero regression on existing call tracking (`CallTrackingService`), CRM API submission (`submitCallResult`), and Reports pages.

---

## Review Focus

1. **Missed / App-Killed Callbacks:** Telecaller had their phone locked or app killed when the callback time arrived -> Local high-priority Android notification must sound and vibrate; tapping it must launch the app straight into the Callback Alert Modal with one-tap "Call Now".
2. **Foreground Call Collision:** Telecaller is actively in another call on Calling Desk when a callback is due -> Display a non-intrusive in-app banner or toast without losing current call disposition unsaved data.
3. **Invalid or Unformatted Phone Numbers:** Callback scheduled for a raw number with spaces, hyphens, or country codes -> Clean to standard 10-digit format for direct dialing and WhatsApp deep-linking.
4. **Time Zone & Daylight Savings Jitter:** Ensure `tz.TZDateTime` correctly tracks local device time zone without UTC offset shifts.
5. **Double Execution / Duplicate Prompts:** Foreground polling checker must not re-prompt an alert modal if the user has already snoozed or dismissed it within the last 5 minutes.

---

## Task Decomposition

### Task 1: Dependencies & Android Permissions Setup

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: Flutter pub dependencies.
- Produces: `flutter_local_notifications`, `timezone`, core library desugaring, and Android permissions (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`).

- [ ] **Step 1: Update `pubspec.yaml`**
  Add `flutter_local_notifications: ^18.0.1` and `timezone: ^0.9.4` under `dependencies:`.
- [ ] **Step 2: Run `flutter pub get`**
  Verify dependencies resolve cleanly without version conflicts.
- [ ] **Step 3: Update `android/app/build.gradle.kts`**
  Enable core library desugaring:
  ```kotlin
  compileOptions {
      isCoreLibraryDesugaringEnabled = true
      sourceCompatibility = JavaVersion.VERSION_17
      targetCompatibility = JavaVersion.VERSION_17
  }
  dependencies {
      coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
  }
  ```
- [ ] **Step 4: Update `android/app/src/main/AndroidManifest.xml`**
  Add required permissions:
  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
  <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
  <uses-permission android:name="android.permission.VIBRATE" />
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
  ```
- [ ] **Step 5: Verify build sanity**
  Run: `flutter analyze`
  Expected: 0 errors.

---

### Task 2: Follow-Up Data Model (`FollowupModel`)

**Files:**
- Create: `lib/model/followup_model.dart`
- Create: `test/followup_model_test.dart`

**Interfaces:**
- Produces: `FollowupModel` class with:
  - `String id`
  - `int? leadId`
  - `String customerName`
  - `String phoneNumber`
  - `String? company`
  - `DateTime scheduledTime`
  - `DateTime createdAt`
  - `String notes`
  - `String status` ('pending', 'snoozed', 'completed', 'cancelled')
  - `DateTime? completedAt`
  - Getters: `isOverdue`, `isDueNow`, `isToday`, `timeRemainingText`
  - Methods: `toJson()`, `fromJson(Map<String, dynamic>)`, `copyWith(...)`

- [ ] **Step 1: Write unit tests in `test/followup_model_test.dart`**
  Test JSON serialization, deserialization, `isOverdue`, `isDueNow`, `isToday`, and `copyWith`.
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/followup_model_test.dart`
  Expected: FAIL (class not found).
- [ ] **Step 3: Implement `FollowupModel` in `lib/model/followup_model.dart`**
  Implement model with full serialization and relative time helpers.
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/followup_model_test.dart`
  Expected: PASS.

---

### Task 3: Local Notification Service (`NotificationService`)

**Files:**
- Create: `lib/services/notification_service.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `FollowupModel`, `flutter_local_notifications`, `timezone`.
- Produces: `NotificationService` singleton:
  - `static Future<void> init()`
  - `static Future<bool> requestPermissions()`
  - `static Future<void> scheduleFollowupNotification(FollowupModel followup)`
  - `static Future<void> cancelFollowupNotification(String followupId)`
  - `static Future<void> showInstantAlert({required String title, required String body, String? payload})`
  - Global `notificationTapStream` / handler callback for navigating or opening the callback dialog.

- [ ] **Step 1: Implement `NotificationService` in `lib/services/notification_service.dart`**
  - Initialize `FlutterLocalNotificationsPlugin`.
  - Initialize `tz.initializeTimeZones()` and get local device location.
  - Create high-importance Android notification channel (`callnow_callbacks_channel`, "Callback Reminders", importance: `Importance.max`, priority: `Priority.high`, enableLights: true, enableVibration: true).
  - Set up background and foreground notification response handlers.
  - Convert `followupId` string to deterministic 32-bit notification ID integer via hash.
- [ ] **Step 2: Integrate `NotificationService.init()` into `lib/main.dart`**
  Call `await NotificationService.init()` inside `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
- [ ] **Step 3: Verify analyzer**
  Run: `flutter analyze`
  Expected: 0 errors.

---

### Task 4: Persistent Follow-Up Storage & Business Logic (`FollowupService`)

**Files:**
- Create: `lib/services/followup_service.dart`
- Create: `test/followup_service_test.dart`

**Interfaces:**
- Consumes: `FollowupModel`, `NotificationService`, `SharedPreferences`.
- Produces: `FollowupService` ChangeNotifier:
  - `static Future<void> init()`
  - `List<FollowupModel> get followups`
  - `List<FollowupModel> getPending()`
  - `List<FollowupModel> getOverdue()`
  - `List<FollowupModel> getToday()`
  - `List<FollowupModel> getUpcoming()`
  - `List<FollowupModel> getCompleted()`
  - `Future<FollowupModel> addFollowup(...)`
  - `Future<void> snoozeFollowup(String id, {Duration duration = const Duration(minutes: 15)})`
  - `Future<void> rescheduleFollowup(String id, DateTime newTime, {String? notes})`
  - `Future<void> markCompleted(String id)`
  - `Future<void> deleteFollowup(String id)`
  - `List<FollowupModel> getDueNowUnprompted()` (finds pending callbacks that are due now and haven't triggered modal prompt yet)

- [ ] **Step 1: Write unit tests in `test/followup_service_test.dart`**
  Test add, snooze, reschedule, markCompleted, filter categorizations using mock `SharedPreferences`.
- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/followup_service_test.dart`
  Expected: FAIL.
- [ ] **Step 3: Implement `FollowupService` in `lib/services/followup_service.dart`**
  Implement persistent storage using `SharedPreferences` key `callnow_saved_followups_v1`, sort by `scheduledTime` ascending, and trigger `NotificationService.scheduleFollowupNotification`.
- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/followup_service_test.dart`
  Expected: PASS.

---

### Task 5: In-App "Model Notification" Dialog (`CallbackAlertDialog`)

**Files:**
- Create: `lib/widgets/callback_alert_dialog.dart`

**Interfaces:**
- Consumes: `FollowupModel`, `FollowupService`, `CallTrackingService`, `url_launcher`.
- Produces: `CallbackAlertDialog.show(BuildContext context, FollowupModel followup)` static helper and widget dialog.
  - UI Header: Glowing phone icon + "📞 Callback Due Now!"
  - Client Box: Name, Mobile, Company, Scheduled Time, Relative urgency badge ("🔴 5m Overdue" or "🟢 Due Right Now").
  - Note Box: Customer context (e.g. "Customer said call back after 30 mins").
  - Action 1 (Primary): **[📞 Call Now]** -> directly dials via phone app and initiates tracking.
  - Action 2: **[💬 WhatsApp]** -> opens WhatsApp with message.
  - Action 3: **[⏰ Snooze 15 Mins]** -> reschedules +15m and cancels current dialog.
  - Action 4: **[📅 Reschedule]** -> opens custom date/time picker.
  - Action 5: **[✅ Mark Completed]** -> closes dialog and marks follow-up done.

- [ ] **Step 1: Implement `CallbackAlertDialog` in `lib/widgets/callback_alert_dialog.dart`**
  Build Material 3 dialog with high-contrast callback reminder styling, sound alert/vibration trigger if in foreground, and direct one-tap call launcher.
- [ ] **Step 2: Verify analyzer**
  Run: `flutter analyze`
  Expected: 0 errors.

---

### Task 6: Calling Desk Callback Scheduler Integration

**Files:**
- Modify: `lib/screens/calling_desk_screen.dart`

**Interfaces:**
- Consumes: `FollowupService`, `NotificationService`, `ApiService`.
- Produces:
  - Quick-scheduling chips accessible during call logging:
    - Preset chips: `+15 Mins`, `+30 Mins`, `+1 Hour`, `+2 Hours`, `Tomorrow 10 AM`, `Tomorrow 3 PM`, `Custom Picker`.
    - Preset reason chips: `Customer asked to call back later`, `Busy in meeting`, `Discussing with family`, `Send proposal first`.
  - Automatic local callback creation: When call disposition is logged with a callback date/time, automatically calls `FollowupService.addFollowup()` which schedules the local alarm, sets `next_followup` on CRM backend, and displays a confirmation banner.

- [ ] **Step 1: Add quick callback chip row in `calling_desk_screen.dart`**
  Make follow-up scheduling prominent when selecting "Follow-up Needed" or any busy/disconnected call where telecaller needs to call back.
- [ ] **Step 2: Connect submission to `FollowupService.addFollowup`**
  When submitting call result with a follow-up time, save to `FollowupService` with customer details from current lead.
- [ ] **Step 3: Run `flutter analyze`**
  Verify clean compilation.

---

### Task 7: Dedicated Follow-Up Pipeline Screen (`FollowUpScreen`)

**Files:**
- Create: `lib/screens/followup_screen.dart`

**Interfaces:**
- Consumes: `FollowupService`, `FollowupModel`, `CallbackAlertDialog`.
- Produces: `FollowUpScreen` widget:
  - KPI Top Bar:
    - 🔴 Overdue Callbacks
    - 🟡 Today's Callbacks
    - 🔵 Upcoming Callbacks
    - 🟢 Completed Callbacks
  - Tab Bar: `All Pending`, `Overdue & Due`, `Today`, `Upcoming`, `Completed`.
  - Search bar: Filter by client name, mobile, or note.
  - Follow-up List Cards:
    - Name, Company, Phone.
    - Badges for urgency (e.g. "Overdue by 15 mins", "Today at 4:30 PM", "Tomorrow at 10:00 AM").
    - Direct card buttons: Call Now (green), WhatsApp (green), Snooze/Reschedule (orange), Complete (grey check).
  - Floating Action Button: `+ Add Callback` (allows adding a callback for ANY customer anytime).

- [ ] **Step 1: Implement `FollowUpScreen` in `lib/screens/followup_screen.dart`**
  Build comprehensive follow-up pipeline UI with reactive updates from `FollowupService`.
- [ ] **Step 2: Add Route `/followups` in `lib/main.dart`**
- [ ] **Step 3: Verify analyzer**
  Run: `flutter analyze`
  Expected: 0 errors.

---

### Task 8: Dashboard & Navigation Wiring + In-App Foreground Watchdog

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `FollowUpScreen`, `FollowupService`, `CallbackAlertDialog`.
- Produces:
  - Wire Dashboard "Follow-ups Pending" stat card to directly open `FollowUpScreen`.
  - Add "Follow-Up Pipeline" shortcut card in Dashboard Quick Actions.
  - Implement a 30-second foreground timer watchdog in `HomeScreen` that checks `FollowupService.getDueNowUnprompted()`. If a callback is due right now, automatically triggers `CallbackAlertDialog.show()`.
  - Handle notification tap payload on app startup or resume to immediately show the alert dialog.

- [ ] **Step 1: Wire Dashboard navigation in `home_screen.dart`**
  Update `_buildStatCard` for "Follow-ups Pending" and Quick Shortcuts to open `FollowUpScreen`.
- [ ] **Step 2: Add foreground reminder watchdog in `HomeScreenState`**
  Timer runs every 30s; if any callback is due now and hasn't been prompted, trigger `CallbackAlertDialog`.
- [ ] **Step 3: Update `test/widget_test.dart`**
  Add widget tests verifying Follow-up pipeline button and navigation render without error.
- [ ] **Step 4: Run full verification suite**
  Run: `flutter analyze`
  Run: `flutter test`
  Expected: All tests pass with 0 errors.
- [ ] **Step 5: Install and verify on Google Pixel 9**
  Build and run on connected device `4B211VDAQ0009G` to verify notification permissions and UI responsiveness.

