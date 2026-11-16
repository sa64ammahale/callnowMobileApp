class TelecallerEngagement {
  final int xpEarned;
  final int callXp;
  final int targetBonusXp;
  final int totalXp;
  final int level;
  final String levelTitle;
  final String badgeTheme;
  final int streakDays;
  final int connectedToday;
  final int targetToday;
  final bool targetMet;

  TelecallerEngagement({
    this.xpEarned = 0,
    this.callXp = 0,
    this.targetBonusXp = 0,
    this.totalXp = 0,
    this.level = 1,
    this.levelTitle = 'Bronze Caller 🥉',
    this.badgeTheme = 'dark',
    this.streakDays = 0,
    this.connectedToday = 0,
    this.targetToday = 250,
    this.targetMet = false,
  });

  factory TelecallerEngagement.fromJson(Map<String, dynamic> json, {int? fallbackTarget}) {
    int parseInt(dynamic val, int fallback) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val != null) return int.tryParse(val.toString()) ?? fallback;
      return fallback;
    }

    bool parseBool(dynamic val, bool fallback) {
      if (val is bool) return val;
      if (val == 1 || val == '1' || val == 'true') return true;
      if (val == 0 || val == '0' || val == 'false') return false;
      return fallback;
    }

    final rawTarget = parseInt(json['target_today'] ?? json['daily_target'] ?? json['daily_calling_limit'], 0);
    final target = rawTarget > 0 ? rawTarget : (fallbackTarget ?? 250);

    return TelecallerEngagement(
      xpEarned: parseInt(json['xp_earned'], 0),
      callXp: parseInt(json['call_xp'], 0),
      targetBonusXp: parseInt(json['target_bonus_xp'], 0),
      totalXp: parseInt(json['total_xp'], 0),
      level: parseInt(json['level'], 1),
      levelTitle: json['level_title']?.toString() ?? 'Bronze Caller 🥉',
      badgeTheme: json['badge_theme']?.toString() ?? 'dark',
      streakDays: parseInt(json['streak_days'], 0),
      connectedToday: parseInt(json['connected_today'], 0),
      targetToday: target,
      targetMet: parseBool(json['target_met'], false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'xp_earned': xpEarned,
      'call_xp': callXp,
      'target_bonus_xp': targetBonusXp,
      'total_xp': totalXp,
      'level': level,
      'level_title': levelTitle,
      'badge_theme': badgeTheme,
      'streak_days': streakDays,
      'connected_today': connectedToday,
      'target_today': targetToday,
      'target_met': targetMet,
    };
  }

  double get targetProgress {
    if (targetToday <= 0) return 0.0;
    return (connectedToday / targetToday).clamp(0.0, 1.0);
  }
}
