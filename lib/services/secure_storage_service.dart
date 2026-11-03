import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key-value storage backed by platform secure storage:
/// Android Keystore, iOS Keychain, macOS Keychain.
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  static SecureStorageService get instance => _instance;
  SecureStorageService._internal();

  static const _tokenKey = 'callnow_auth_token';
  static const _userEmailKey = 'callnow_user_email';
  static const _userPhoneKey = 'callnow_user_phone';
  static const _userNameKey = 'callnow_user_name';
  static const _userIdKey = 'callnow_user_id';

  /// Backend for secure storage. Swappable for testing.
  static _SecureStorageBackend _backend = _FlutterSecureStorageBackend(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accountName: 'callnow_new',
      ),
    ),
  );

  /// Override the backend for testing (e.g. with an in-memory mock).
  static void setBackendForTesting(_SecureStorageBackend backend) {
    _backend = backend;
  }

  /// Reset the backend to the production implementation.
  static void resetBackend() {
    _backend = _FlutterSecureStorageBackend(
      const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
        ),
        iOptions: IOSOptions(
          accountName: 'callnow_new',
        ),
      ),
    );
  }

  /// Store the auth token in encrypted secure storage.
  Future<void> writeToken(String token) async {
    await _backend.write(key: _tokenKey, value: token);
  }

  /// Read the auth token from encrypted secure storage.
  Future<String?> readToken() async {
    return await _backend.read(key: _tokenKey);
  }

  /// Delete the auth token from secure storage.
  Future<void> deleteToken() async {
    await _backend.delete(key: _tokenKey);
  }

  /// Store a sensitive user field in encrypted secure storage.
  Future<void> writeUserField(String key, String value) async {
    await _backend.write(key: key, value: value);
  }

  /// Read a sensitive user field from encrypted secure storage.
  Future<String?> readUserField(String key) async {
    return await _backend.read(key: key);
  }

  /// Delete a sensitive user field from secure storage.
  Future<void> deleteUserField(String key) async {
    await _backend.delete(key: key);
  }

  /// Clear all secure storage keys used by this app.
  Future<void> clearAll() async {
    await _backend.deleteAll();
  }

  // Convenience keys for commonly stored PII
  Future<void> writeEmail(String email) => writeUserField(_userEmailKey, email);
  Future<String?> readEmail() => readUserField(_userEmailKey);
  Future<void> deleteEmail() => deleteUserField(_userEmailKey);

  Future<void> writePhone(String phone) => writeUserField(_userPhoneKey, phone);
  Future<String?> readPhone() => readUserField(_userPhoneKey);
  Future<void> deletePhone() => deleteUserField(_userPhoneKey);

  Future<void> writeName(String name) => writeUserField(_userNameKey, name);
  Future<String?> readName() => readUserField(_userNameKey);
  Future<void> deleteName() => deleteUserField(_userNameKey);

  Future<void> writeUserId(String id) => writeUserField(_userIdKey, id);
  Future<String?> readUserId() => readUserField(_userIdKey);
  Future<void> deleteUserId() => deleteUserField(_userIdKey);
}

/// Backend interface for secure storage operations.
abstract class _SecureStorageBackend {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

/// Production backend wrapping FlutterSecureStorage.
class _FlutterSecureStorageBackend implements _SecureStorageBackend {
  final FlutterSecureStorage _storage;
  _FlutterSecureStorageBackend(this._storage);

  @override
  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}

/// In-memory mock backend for unit tests.
class MemorySecureStorageBackend implements _SecureStorageBackend {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}
