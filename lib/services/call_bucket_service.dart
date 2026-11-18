import 'package:shared_preferences/shared_preferences.dart';

/// A small, disposable mirror of the server-owned calling bucket.
///
/// It deliberately stores no credentials and is never used to extend a lease.
class CallBucketService {
  static const _idKey = 'active_call_bucket_id';
  static const _expiresAtKey = 'active_call_bucket_expires_at';

  static Future<({String id, DateTime expiresAt})?> readActive() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    final expiresAt = DateTime.tryParse(prefs.getString(_expiresAtKey) ?? '');
    if (id == null || id.isEmpty || expiresAt == null) return null;
    return (id: id, expiresAt: expiresAt);
  }

  static Future<void> save({
    required String id,
    required DateTime expiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, id);
    await prefs.setString(_expiresAtKey, expiresAt.toIso8601String());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_expiresAtKey);
  }
}
