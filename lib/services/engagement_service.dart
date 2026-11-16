import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:callnow_new/services/config_service.dart';
import '../model/telecaller_engagement.dart';

class EngagementService extends ChangeNotifier {
  static final EngagementService instance = EngagementService._();
  EngagementService._();

  TelecallerEngagement _state = TelecallerEngagement();
  TelecallerEngagement get state => _state;

  static const _prefKey = 'callnow_telecaller_engagement';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKey);
    if (cached != null) {
      try {
        final decoded = json.decode(cached);
        final fallbackLimit = ConfigService.dailyCallingLimit;
        if (decoded is Map<String, dynamic>) {
          _state = TelecallerEngagement.fromJson(decoded, fallbackTarget: fallbackLimit);
        } else if (decoded is Map) {
          _state = TelecallerEngagement.fromJson(Map<String, dynamic>.from(decoded), fallbackTarget: fallbackLimit);
        }
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> updateFromApiResponse(Map<String, dynamic>? data) async {
    if (data == null) return;
    _state = TelecallerEngagement.fromJson(data, fallbackTarget: ConfigService.dailyCallingLimit);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, json.encode({
      'total_xp': _state.totalXp,
      'level': _state.level,
      'level_title': _state.levelTitle,
      'streak_days': _state.streakDays,
      'connected_today': _state.connectedToday,
      'target_today': _state.targetToday,
      'target_met': _state.targetMet,
    }));
  }

  @visibleForTesting
  void setStateForTesting(TelecallerEngagement newState) {
    _state = newState;
    notifyListeners();
  }
}
