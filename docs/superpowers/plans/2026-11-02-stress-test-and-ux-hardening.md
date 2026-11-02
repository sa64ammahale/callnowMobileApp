# Large Database Stress Test & UX Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute comprehensive Large Database Stress Testing and UX Hardening across CallNow Mobile App, validating performance with large datasets (5,000+ leads, 10,000+ call logs, 1,000+ followups) and hardening layouts against extreme text scale factors (1.5x, 2.0x), narrow screens (320px width), long strings, and server failure modes.

**Architecture:** Automated Flutter Test Suites (`test/stress_test.dart` and `test/ux_hardening_test.dart`) utilizing Flutter's testing framework, `WidgetTester`, mock HTTP clients, and memory/timing benchmarks, followed by targeted code hardening in screens and services where vulnerabilities are found.

**Tech Stack:** Flutter 3.47+ / Dart 3.13+, `flutter_test`, `shared_preferences`, `http`.

**Spec:** Requirement: "do the Large Database Stress Test & UX Hardening test in current project."

---

## Global Constraints

1. **Zero Regression**: All existing 24 unit and widget tests must continue to pass with 0 failures.
2. **Analysis Cleanliness**: `flutter analyze` must report 0 errors and 0 warnings.
3. **Performance Floor**:
   - Deserialization and in-memory filtering of 5,000 CRM leads must complete in < 250ms.
   - Aggregating and computing metrics for 10,000 call log entries must complete in < 100ms.
   - Serializing and categorizing 1,000 followups in `FollowupService` must complete in < 150ms.
4. **Layout Robustness**: No `RenderFlex` overflow errors on any primary screen (`CallingDeskScreen`, `LeadsScreen`, `FollowUpScreen`, `ProfileScreen`, `CallReportsScreen`, `LoginScreen`) at:
   - 320×568 (compact phone / iPhone SE)
   - 390×844 (standard modern phone)
   - Text scale factors: 1.0x, 1.5x, and 2.0x (accessibility mode).

---

## Review Focus

1. **Zero Division in Analytics Tiers**: In `CallReportsScreen`, if total calls are 0 or tier distributions are empty, ensure no NaN, infinite flex, or division by zero crashes occur.
2. **Extremely Long Text Strings**: Customer names with 200+ characters, notes with 1,000+ characters, or multi-line remarks must not cause layout overflow or clip unreadably.
3. **Corrupted / Empty JSON Data**: `CrmLead`, `FollowupModel`, and `UserProfile` must handle null, empty, unexpected string types without unhandled runtime exceptions.
4. **FollowupService Copy-on-Sort Optimization**: `FollowupService.followups` allocates and sorts a new list on every call. If called multiple times per build, optimize to sort once or memoize to prevent frame drops under 1,000 items.
5. **Double Tap Race Conditions**: Rapidly tapping save/call buttons must not trigger duplicate calls or unmounted state updates.

---

## Task Decomposition

### Task 1: Create Large Database Stress Test Suite (`test/stress_test.dart`)

**Files:**
- Create: `test/stress_test.dart`

**Interfaces:**
- Tests: `CrmLead.fromJson`, `FollowupService`, `CallReportsScreen` analytics calculations, `UserProfile.fromJson`.
- Benchmarks: Measures execution elapsed time and asserts completion within performance budgets.

- [ ] **Step 1: Write stress test for 5,000 CRM Leads parsing and multi-field filtering**
  - Generate 5,000 synthetic JSON lead objects with varying statuses, loan amounts, and search keywords.
  - Benchmark parsing time (`Stopwatch`).
  - Benchmark search & stage filtering over all 5,000 items.
  - Assert parsing and filtering time < 250ms.

- [ ] **Step 2: Write stress test for 10,000 Call Log entries & analytics calculations**
  - Generate 10,000 call log entries with extreme durations (0s to 86,400s) and status types.
  - Verify total call duration formatting, tier percentage calculations, and 0-call edge cases.
  - Assert processing time < 100ms.

- [ ] **Step 3: Write stress test for 1,000 Followup items in `FollowupService`**
  - Populate 1,000 followups across past, present, and future dates.
  - Test serialization to `SharedPreferences` JSON and subsequent reload.
  - Verify `getOverdue()`, `getToday()`, `getUpcoming()`, and `getCompleted()` accuracy.
  - Assert processing time < 150ms.

- [ ] **Step 4: Write malformed & extreme data resilience stress test**
  - Test `CrmLead.fromJson` with nulls, inverted types, Unicode, and negative package amounts.
  - Test `UserProfile.fromJson` with missing nested structures.
  - Test `FollowupModel.fromJson` with invalid date formats.

- [ ] **Step 5: Run stress tests and verify performance output**
  - Execute: `flutter test test/stress_test.dart`
  - Expected: PASS with recorded timing metrics.

---

### Task 2: Create UX Hardening Test Suite (`test/ux_hardening_test.dart`)

**Files:**
- Create: `test/ux_hardening_test.dart`

**Interfaces:**
- Tests: Layout constraints, text scale resilience, narrow screen widths, long string wrapping across `ProfileScreen`, `LeadsScreen`, `FollowUpScreen`, `CallingDeskScreen`, `CallReportsScreen`.

- [ ] **Step 1: Write text scale resilience tests (1.0x, 1.5x, 2.0x)**
  - Test rendering screens under `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(1.5)))` and `2.0`.
  - Assert zero `FlutterError` or `RenderFlex` overflows.

- [ ] **Step 2: Write compact viewport resilience tests (320px width)**
  - Test rendering on 320×568 viewport.
  - Assert all cards, headers, and action buttons fit without horizontal clipping.

- [ ] **Step 3: Write extreme string length and Unicode tests**
  - Test with 250-character customer names, 1,000-character notes, and emoji-laden text.
  - Assert proper text ellipsis and expansion.

- [ ] **Step 4: Write network error & offline state resilience tests**
  - Inject 500 Internal Server Error, 502 Bad Gateway, and Network Timeout mocks.
  - Assert screens show user-friendly error messages with retry actions instead of crashing.

- [ ] **Step 5: Run UX hardening tests**
  - Execute: `flutter test test/ux_hardening_test.dart`
  - Expected: PASS or identify layout areas needing hardening.

---

### Task 3: Apply Code Hardening Fixes (If Identified)

**Files:**
- Modify: Screens and models where stress/UX test reveals edge cases.

- [ ] **Step 1: Harden any overflowing UI components**
  - Apply `Flexible`, `Expanded`, or `SingleChildScrollView` to components that overflow at 2.0x text scaling.
- [ ] **Step 2: Optimize `FollowupService` memoization / sorting if needed**
- [ ] **Step 3: Harden `CallReportsScreen` flex calculation against 0 or huge tier counts**
- [ ] **Step 4: Re-verify full test suite**
  - Run `flutter analyze`
  - Run `flutter test`

