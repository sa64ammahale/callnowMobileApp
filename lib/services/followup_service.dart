import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/notification_service.dart';

class FollowupService extends ChangeNotifier {
  static final FollowupService _instance = FollowupService._internal();
  static FollowupService get instance => _instance;
  FollowupService._internal();

  static const String _storageKey = 'callnow_saved_followups_v1';

  final List<FollowupModel> _followups = [];
  final Set<String> _promptedIdsInSession = {};

  List<FollowupModel> get followups {
    final list = List<FollowupModel>.from(_followups);
    list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return list;
  }

  static Future<void> init() async {
    await _instance._loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      _followups.clear();
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _followups.add(FollowupModel.fromJson(item));
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading followups: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded =
          jsonEncode(_followups.map((f) => f.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving followups: $e');
    }
  }

  List<FollowupModel> getPending() {
    return followups
        .where((f) => f.status == 'pending' || f.status == 'snoozed')
        .toList();
  }

  List<FollowupModel> getOverdue() {
    return followups.where((f) => f.isOverdue).toList();
  }

  List<FollowupModel> getToday() {
    return followups
        .where((f) => (f.status == 'pending' || f.status == 'snoozed') && f.isToday)
        .toList();
  }

  List<FollowupModel> getUpcoming() {
    final now = DateTime.now();
    return followups
        .where((f) =>
            (f.status == 'pending' || f.status == 'snoozed') &&
            f.scheduledTime.isAfter(now) &&
            !f.isToday)
        .toList();
  }

  List<FollowupModel> getCompleted() {
    return followups.where((f) => f.status == 'completed').toList();
  }

  Future<FollowupModel> addFollowup({
    required String customerName,
    required String phoneNumber,
    String? company,
    required DateTime scheduledTime,
    String notes = '',
    int? leadId,
    String? source,
  }) async {
    final id = 'f_${DateTime.now().millisecondsSinceEpoch}_${phoneNumber.replaceAll(RegExp(r'\D'), '')}';
    final model = FollowupModel(
      id: id,
      leadId: leadId,
      customerName: customerName.trim(),
      phoneNumber: phoneNumber.trim(),
      company: company?.trim(),
      scheduledTime: scheduledTime,
      createdAt: DateTime.now(),
      notes: notes.trim(),
      status: 'pending',
      source: source,
    );

    _followups.add(model);
    await _saveToPrefs();

    // Schedule exact notification
    await NotificationService.scheduleFollowupNotification(model);

    notifyListeners();
    return model;
  }

  Future<void> snoozeFollowup(
    String id, {
    Duration duration = const Duration(minutes: 15),
  }) async {
    final index = _followups.indexWhere((f) => f.id == id);
    if (index == -1) return;

    final existing = _followups[index];
    final newScheduledTime = DateTime.now().add(duration);
    final updated = existing.copyWith(
      scheduledTime: newScheduledTime,
      status: 'snoozed',
    );

    _followups[index] = updated;
    await _saveToPrefs();

    await NotificationService.cancelFollowupNotification(id);
    await NotificationService.scheduleFollowupNotification(updated);

    // Unmark from session prompt so it will ring again
    _promptedIdsInSession.remove(id);

    notifyListeners();
  }

  Future<void> rescheduleFollowup(
    String id,
    DateTime newTime, {
    String? notes,
  }) async {
    final index = _followups.indexWhere((f) => f.id == id);
    if (index == -1) return;

    final existing = _followups[index];
    final updated = existing.copyWith(
      scheduledTime: newTime,
      notes: notes ?? existing.notes,
      status: 'pending',
    );

    _followups[index] = updated;
    await _saveToPrefs();

    await NotificationService.cancelFollowupNotification(id);
    await NotificationService.scheduleFollowupNotification(updated);

    _promptedIdsInSession.remove(id);

    notifyListeners();
  }

  Future<void> markCompleted(String id) async {
    final index = _followups.indexWhere((f) => f.id == id);
    if (index == -1) return;

    final existing = _followups[index];
    final updated = existing.copyWith(
      status: 'completed',
      completedAt: DateTime.now(),
    );

    _followups[index] = updated;
    await _saveToPrefs();

    await NotificationService.cancelFollowupNotification(id);
    _promptedIdsInSession.add(id);

    notifyListeners();
  }

  Future<void> deleteFollowup(String id) async {
    _followups.removeWhere((f) => f.id == id);
    await _saveToPrefs();
    await NotificationService.cancelFollowupNotification(id);
    _promptedIdsInSession.remove(id);
    notifyListeners();
  }

  /// Returns pending follow-ups that are currently due now and have not
  /// been prompted yet to the user in this app session.
  List<FollowupModel> getDueNowUnprompted() {
    final due = getPending().where((f) {
      if (_promptedIdsInSession.contains(f.id)) return false;
      return f.isDueNow || f.isOverdue;
    }).toList();
    return due;
  }

  void markPromptedInSession(String id) {
    _promptedIdsInSession.add(id);
  }
}

