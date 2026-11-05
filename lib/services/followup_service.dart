import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/notification_service.dart';

class FollowupService extends ChangeNotifier {
  static final FollowupService _instance = FollowupService._internal();
  static FollowupService get instance => _instance;
  FollowupService._internal();

  static const String _storageKey = 'callnow_saved_followups_v1';

  final List<FollowupModel> _followups = [];
  final Set<String> _promptedIdsInSession = {};

  // Cached derived lists — invalidated on any mutation
  List<FollowupModel>? _cachedSorted;
  List<FollowupModel>? _cachedPending;
  List<FollowupModel>? _cachedOverdue;
  List<FollowupModel>? _cachedToday;
  List<FollowupModel>? _cachedUpcoming;
  List<FollowupModel>? _cachedCompleted;
  bool _cacheDirty = true;

  /// Maximum completed follow-ups retained in memory before auto-purge.
  static const int _maxCompletedRetained = 500;

  List<FollowupModel> get followups {
    if (_cacheDirty) _rebuildCaches();
    return _cachedSorted!;
  }

  List<FollowupModel> getPending() {
    if (_cacheDirty) _rebuildCaches();
    return _cachedPending!;
  }

  List<FollowupModel> getOverdue() {
    if (_cacheDirty) _rebuildCaches();
    return _cachedOverdue!;
  }

  List<FollowupModel> getToday() {
    if (_cacheDirty) _rebuildCaches();
    return _cachedToday!;
  }

  List<FollowupModel> getUpcoming() {
    if (_cacheDirty) _rebuildCaches();
    return _cachedUpcoming!;
  }

  List<FollowupModel> getCompleted() {
    if (_cacheDirty) _rebuildCaches();
    return _cachedCompleted!;
  }

  void _rebuildCaches() {
    _cachedSorted = List<FollowupModel>.from(_followups)
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    _cachedPending = _followups
        .where((f) => f.status == 'pending' || f.status == 'snoozed')
        .toList();
    _cachedOverdue = _followups.where((f) => f.isOverdue).toList();
    final now = DateTime.now();
    _cachedToday = _followups
        .where((f) =>
            (f.status == 'pending' || f.status == 'snoozed') && f.isToday)
        .toList();
    _cachedUpcoming = _followups
        .where((f) =>
            (f.status == 'pending' || f.status == 'snoozed') &&
            f.scheduledTime.isAfter(now) &&
            !f.isToday)
        .toList();
    _cachedCompleted = _followups.where((f) => f.status == 'completed').toList();
    _cacheDirty = false;

    // Prune prompted session set against live follow-up IDs to prevent leak
    _promptedIdsInSession.retainWhere(
        (id) => _followups.any((f) => f.id == id));
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
      _cacheDirty = true;
      _rebuildCaches();
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

  /// Sync open follow-ups from CRM backend
  Future<void> syncWithServer() async {
    try {
      final res = await ApiService.fetchServerFollowups(status: 'OPEN', limit: 100);
      final dynamic rawList = res['data'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final serverModel = FollowupModel.fromJson(item);
            final index = _followups.indexWhere((f) =>
                (serverModel.serverId != null && f.serverId == serverModel.serverId) ||
                (serverModel.clientContactId != null &&
                    f.clientContactId == serverModel.clientContactId &&
                    f.status == 'pending'));
            if (index >= 0) {
              _followups[index] = _followups[index].copyWith(
                serverId: serverModel.serverId,
                customerName: serverModel.customerName,
                phoneNumber: serverModel.phoneNumber,
                company: serverModel.company,
                scheduledTime: serverModel.scheduledTime,
                notes: serverModel.notes.isNotEmpty ? serverModel.notes : _followups[index].notes,
                status: serverModel.status,
                leadId: serverModel.leadId ?? _followups[index].leadId,
                clientContactId: serverModel.clientContactId ?? _followups[index].clientContactId,
                source: serverModel.source ?? _followups[index].source,
              );
            } else {
              _followups.add(serverModel);
              if (serverModel.scheduledTime.isAfter(DateTime.now())) {
                await NotificationService.scheduleFollowupNotification(serverModel);
              }
            }
          }
        }
        _cacheDirty = true;
        _rebuildCaches();
        await _saveToPrefs();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error syncing followups with server: $e');
    }
  }

  Future<FollowupModel> addFollowup({
    required String customerName,
    required String phoneNumber,
    String? company,
    required DateTime scheduledTime,
    String notes = '',
    int? leadId,
    int? clientContactId,
    int? serverId,
    String? source,
  }) async {
    final id = 'f_${DateTime.now().millisecondsSinceEpoch}_${phoneNumber.replaceAll(RegExp(r'\D'), '')}';
    int? finalServerId = serverId;

    if (finalServerId == null) {
      try {
        final res = await ApiService.createServerFollowup(
          clientContactId: clientContactId,
          leadId: leadId,
          followupAt: scheduledTime.toIso8601String(),
          note: notes,
          contactSource: source ?? (clientContactId != null ? 'MAIN' : 'LEAD'),
        );
        if (res['followup_id'] != null) {
          finalServerId = int.tryParse(res['followup_id'].toString());
        }
      } catch (e) {
        debugPrint('Failed to sync new followup to server: $e');
      }
    }

    final model = FollowupModel(
      id: id,
      serverId: finalServerId,
      leadId: leadId,
      clientContactId: clientContactId,
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
    _cacheDirty = true;
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
    _cacheDirty = true;
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
    _cacheDirty = true;
    await _saveToPrefs();

    if (existing.serverId != null) {
      try {
        await ApiService.rescheduleServerFollowup(
          existing.serverId!,
          newTime,
          notes,
        );
      } catch (e) {
        debugPrint('Error rescheduling on server: $e');
      }
    }

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
    _cacheDirty = true;
    await _saveToPrefs();

    if (existing.serverId != null) {
      try {
        await ApiService.completeServerFollowup(existing.serverId!);
      } catch (e) {
        debugPrint('Error completing on server: $e');
      }
    }

    await NotificationService.cancelFollowupNotification(id);
    _promptedIdsInSession.remove(id);

    _purgeCompletedIfNeeded();

    notifyListeners();
  }

  Future<void> deleteFollowup(String id) async {
    _followups.removeWhere((f) => f.id == id);
    _cacheDirty = true;
    await _saveToPrefs();
    await NotificationService.cancelFollowupNotification(id);
    _promptedIdsInSession.remove(id);
    notifyListeners();
  }

  /// Removes completed follow-ups older than [olderThan] to bound memory growth.
  Future<void> purgeCompletedOlderThan(Duration olderThan) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final toRemove = <String>[];
    for (final f in _followups) {
      if (f.status == 'completed' &&
          f.completedAt != null &&
          f.completedAt!.isBefore(cutoff)) {
        toRemove.add(f.id);
      }
    }
    for (final id in toRemove) {
      await deleteFollowup(id);
    }
  }

  /// Keeps completed follow-ups bounded so the singleton does not grow forever.
  Future<void> _purgeCompletedIfNeeded() async {
    final completedCount = _followups.where((f) => f.status == 'completed').length;
    if (completedCount <= _maxCompletedRetained) return;
    // Remove oldest completed entries first.
    final completed = _followups
        .where((f) => f.status == 'completed')
        .toList()
      ..sort((a, b) =>
            (a.completedAt ?? a.createdAt)
                .compareTo(b.completedAt ?? b.createdAt));
    final toRemove = completed.take(completedCount - _maxCompletedRetained);
    for (final f in toRemove) {
      await deleteFollowup(f.id);
    }
  }

  /// Returns pending follow-ups that are currently due now and have not
  /// been prompted yet to the user in this app session.
  List<FollowupModel> getDueNowUnprompted() {
    if (_cacheDirty) _rebuildCaches();
    final due = _cachedPending!.where((f) {
      if (_promptedIdsInSession.contains(f.id)) return false;
      return f.isDueNow || f.isOverdue;
    }).toList();
    return due;
  }

  void markPromptedInSession(String id) {
    _promptedIdsInSession.add(id);
  }
}
