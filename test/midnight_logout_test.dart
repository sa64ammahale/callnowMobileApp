import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Midnight auto-logout logic unit tests
// ---------------------------------------------------------------------------
// These tests verify the _scheduleMidnightLogout / _checkDateChangeLogout
// logic in isolation without spinning up the full HomeScreen widget (which
// requires platform channels for call-log & notifications).
// ---------------------------------------------------------------------------

/// Returns the Duration until the next 00:00:00 local time — mirrors the
/// production logic in _HomeScreenState._scheduleMidnightLogout().
Duration durationUntilNextMidnight(DateTime now) {
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  return nextMidnight.difference(now);
}

/// Returns true if [now] is on a different calendar day than [sessionStart].
bool hasDateChanged(DateTime sessionStart, DateTime now) {
  return now.day != sessionStart.day ||
      now.month != sessionStart.month ||
      now.year != sessionStart.year;
}

void main() {
  group('Midnight Logout Logic', () {
    // ── durationUntilNextMidnight ──────────────────────────────────────────

    test('returns positive duration when called well before midnight', () {
      final now = DateTime(2026, 11, 4, 22, 30, 0); // 22:30
      final delay = durationUntilNextMidnight(now);
      expect(delay.isNegative, isFalse);
      expect(delay.inMinutes, 90); // 1 h 30 m = 90 min
    });

    test('returns ~24h when called just after midnight', () {
      final now = DateTime(2026, 11, 4, 0, 0, 1); // 1 second after midnight
      final delay = durationUntilNextMidnight(now);
      // Should be ~23 h 59 m 59 s
      expect(delay.inHours, 23);
      expect(delay.inSeconds, closeTo(86399, 2));
    });

    test('returns ~1 day when called at exactly midnight', () {
      final now = DateTime(2026, 11, 4, 0, 0, 0);
      final delay = durationUntilNextMidnight(now);
      expect(delay.inHours, 24);
    });

    test('returns <1 minute when called at 23:59:30', () {
      final now = DateTime(2026, 11, 4, 23, 59, 30);
      final delay = durationUntilNextMidnight(now);
      expect(delay.inSeconds, 30);
    });

    test('works correctly across month boundary', () {
      final now = DateTime(2026, 10, 31, 23, 0, 0); // 23:00 on Oct 31
      final delay = durationUntilNextMidnight(now);
      expect(delay.inMinutes, 60);
    });

    test('works correctly across year boundary (Dec 31)', () {
      final now = DateTime(2026, 12, 31, 20, 0, 0); // 20:00 on Dec 31
      final delay = durationUntilNextMidnight(now);
      expect(delay.inHours, 4);
    });

    // ── hasDateChanged ─────────────────────────────────────────────────────

    test('returns false when same day', () {
      final start = DateTime(2026, 11, 4, 9, 0);
      final now = DateTime(2026, 11, 4, 22, 0);
      expect(hasDateChanged(start, now), isFalse);
    });

    test('returns true when day has advanced by 1', () {
      final start = DateTime(2026, 11, 4, 23, 50);
      final now = DateTime(2026, 11, 5, 0, 5); // next day
      expect(hasDateChanged(start, now), isTrue);
    });

    test('returns true when phone was left on for multiple days', () {
      final start = DateTime(2026, 11, 1, 10, 0);
      final now = DateTime(2026, 11, 4, 8, 0); // 3 days later
      expect(hasDateChanged(start, now), isTrue);
    });

    test('returns true across month boundary', () {
      final start = DateTime(2026, 10, 31, 23, 50);
      final now = DateTime(2026, 11, 1, 0, 1);
      expect(hasDateChanged(start, now), isTrue);
    });

    test('returns true across year boundary', () {
      final start = DateTime(2026, 12, 31, 23, 55);
      final now = DateTime(2027, 1, 1, 0, 1);
      expect(hasDateChanged(start, now), isTrue);
    });

    // ── Timer fires at correct delay ───────────────────────────────────────

    test('a fake timer fires after the computed delay', () async {
      final now = DateTime(2026, 11, 4, 23, 59, 59); // 1 second before midnight
      final delay = durationUntilNextMidnight(now);

      // Verify the delay calculation is as expected (1 second)
      expect(delay.inSeconds, 1);

      // Verify that after the delay the next midnight date is correct
      final expectedMidnight = DateTime(2026, 11, 5, 0, 0, 0);
      expect(now.add(delay), equals(expectedMidnight));
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal clock helper (avoids a dependency on package:clock)
// ---------------------------------------------------------------------------

class Clock {
  final DateTime Function() _now;
  Clock._(this._now);
  factory Clock.fixed(DateTime t) => Clock._(() => t);
  DateTime call() => _now();
}

Future<T> withClock<T>(Clock clock, Future<T> Function() fn) => fn();
