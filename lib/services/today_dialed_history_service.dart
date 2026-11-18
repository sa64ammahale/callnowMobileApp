import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_bucket_service.dart';

int? _tryParseInt(dynamic val) {
  if (val == null) return null;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val);
  return null;
}

/// Abstract backend interface to support both native SQLite and in-memory mock testing
abstract class TodayDialedHistoryBackend {
  Future<void> init();
  Future<void> insertOrUpdate(Map<String, dynamic> call);
  Future<Map<String, dynamic>?> findByLast10(String last10);
  Future<List<Map<String, dynamic>>> getAll();
  Future<int> getCount();
  Future<int> getTotalDuration();
  Future<void> clear();
  Future<void> close();

  // 15-Minute Batch Queue Local Operations
  Future<void> saveBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  });
  Future<void> appendBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  });
  Future<List<Map<String, dynamic>>> getActiveBatchLeads();
  Future<void> updateBatchLeadStatus(
    String last10, {
    required String status,
    int? duration,
    String? callStatus,
  });
  Future<Map<String, dynamic>?> getBatchLeadByLast10(String last10);
  Future<int> getUncalledBatchLeadsCount();
  Future<DateTime?> getBatchExpiryTime();
  Future<void> clearBatchLeads();
}

/// In-Memory Backend for Unit Testing and Non-Android Platforms
class MemoryTodayDialedHistoryBackend implements TodayDialedHistoryBackend {
  final List<Map<String, dynamic>> _records = [];
  final List<Map<String, dynamic>> _batchRecords = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> insertOrUpdate(Map<String, dynamic> call) async {
    final last10 = call['last10']?.toString() ?? '';
    _records.removeWhere((r) => r['last10']?.toString() == last10);
    _records.insert(0, Map<String, dynamic>.from(call));
  }

  @override
  Future<Map<String, dynamic>?> findByLast10(String last10) async {
    if (last10.isEmpty) return null;
    try {
      return _records.firstWhere((r) => r['last10']?.toString() == last10);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAll() async {
    return List.unmodifiable(_records);
  }

  @override
  Future<int> getCount() async => _records.length;

  @override
  Future<int> getTotalDuration() async {
    return _records.fold<int>(0, (sum, item) {
      final dur = (item['duration'] as num?)?.toInt() ?? 0;
      return sum + dur;
    });
  }

  @override
  Future<void> clear() async => _records.clear();

  @override
  Future<void> close() async {
    _records.clear();
    _batchRecords.clear();
  }

  // --- Batch Operations (Memory) ---

  @override
  Future<void> saveBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    _batchRecords.removeWhere((r) => r['status'] == 'PENDING');
    for (int i = 0; i < leads.length; i++) {
      final lead = leads[i];
      final phone =
          (lead['mobile'] ?? lead['phone_number'] ?? lead['phone'] ?? '')
              .toString();
      final last10 = TodayDialedHistoryService.normalizeLast10(phone);
      if (last10.isEmpty) continue;
      _batchRecords.add({
        'lead_id': _tryParseInt(lead['lead_id']) ?? _tryParseInt(lead['id']),
        'record_id':
            _tryParseInt(lead['record_id']) ?? _tryParseInt(lead['id']),
        'name': lead['name']?.toString() ?? '',
        'phone_number': phone,
        'last10': last10,
        'company': lead['company']?.toString() ?? '',
        'source': lead['source']?.toString() ?? 'BATCH',
        'batch_fetched_at': DateTime.now().toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': 'PENDING',
        'call_duration': 0,
        'call_status': null,
        'raw_json': jsonEncode(lead),
        'sort_order': i,
      });
    }
  }

  @override
  Future<void> appendBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    for (final r in _batchRecords) {
      if (r['status'] == 'PENDING' || r['status'] == 'DIALED') {
        r['expires_at'] = expiresAt.toIso8601String();
      }
    }
    int baseSort = _batchRecords.isEmpty
        ? 0
        : (_batchRecords.last['sort_order'] as int? ?? 0) + 1;
    for (int i = 0; i < leads.length; i++) {
      final lead = leads[i];
      final phone =
          (lead['mobile'] ?? lead['phone_number'] ?? lead['phone'] ?? '')
              .toString();
      final last10 = TodayDialedHistoryService.normalizeLast10(phone);
      if (last10.isEmpty) continue;
      _batchRecords.add({
        'lead_id': _tryParseInt(lead['lead_id']) ?? _tryParseInt(lead['id']),
        'record_id':
            _tryParseInt(lead['record_id']) ?? _tryParseInt(lead['id']),
        'name': lead['name']?.toString() ?? '',
        'phone_number': phone,
        'last10': last10,
        'company': lead['company']?.toString() ?? '',
        'source': lead['source']?.toString() ?? 'BATCH',
        'batch_fetched_at': DateTime.now().toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': 'PENDING',
        'call_duration': 0,
        'call_status': null,
        'raw_json': jsonEncode(lead),
        'sort_order': baseSort + i,
      });
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveBatchLeads() async {
    final active = _batchRecords
        .where((r) => r['status'] == 'PENDING' || r['status'] == 'DIALED')
        .toList();
    active.sort(
      (a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int),
    );
    final list = <Map<String, dynamic>>[];
    for (final row in active) {
      Map<String, dynamic> lead;
      final raw = row['raw_json']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          lead = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          lead = Map<String, dynamic>.from(row);
        }
      } else {
        lead = Map<String, dynamic>.from(row);
      }
      lead['local_batch_status'] = row['status'];
      lead['local_call_duration'] = row['call_duration'];
      lead['local_call_status'] = row['call_status'];
      list.add(lead);
    }
    return list;
  }

  @override
  Future<void> updateBatchLeadStatus(
    String last10, {
    required String status,
    int? duration,
    String? callStatus,
  }) async {
    for (final r in _batchRecords) {
      if (r['last10'] == last10) {
        r['status'] = status;
        if (duration != null) r['call_duration'] = duration;
        if (callStatus != null) r['call_status'] = callStatus;
        break;
      }
    }
  }

  @override
  Future<Map<String, dynamic>?> getBatchLeadByLast10(String last10) async {
    for (final row in _batchRecords.reversed) {
      if (row['last10'] == last10) {
        Map<String, dynamic> lead;
        final raw = row['raw_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          try {
            lead = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          } catch (_) {
            lead = Map<String, dynamic>.from(row);
          }
        } else {
          lead = Map<String, dynamic>.from(row);
        }
        lead['local_batch_status'] = row['status'];
        lead['local_call_duration'] = row['call_duration'];
        lead['local_call_status'] = row['call_status'];
        return lead;
      }
    }
    return null;
  }

  @override
  Future<int> getUncalledBatchLeadsCount() async {
    return _batchRecords
        .where((r) => r['status'] == 'PENDING' || r['status'] == 'DIALED')
        .length;
  }

  @override
  Future<DateTime?> getBatchExpiryTime() async {
    for (final r in _batchRecords.reversed) {
      if ((r['status'] == 'PENDING' || r['status'] == 'DIALED') &&
          r['expires_at'] != null) {
        return DateTime.tryParse(r['expires_at'].toString());
      }
    }
    return null;
  }

  @override
  Future<void> clearBatchLeads() async {
    _batchRecords.clear();
  }
}

/// SQLite Database Backend for Real Device Persistence
class SqfliteTodayDialedHistoryBackend implements TodayDialedHistoryBackend {
  Database? _db;

  static const String tableName = 'today_dialed_calls';
  static const String batchTableName = 'current_batch_leads';

  @override
  Future<void> init() async {
    if (_db != null && _db!.isOpen) return;

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'today_dialed_call_history.db');

      _db = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $tableName (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              server_call_id INTEGER,
              record_id INTEGER,
              lead_id INTEGER,
              name TEXT,
              phone_number TEXT,
              last10 TEXT NOT NULL,
              company TEXT,
              source TEXT,
              status TEXT,
              duration INTEGER DEFAULT 0,
              timing_tier TEXT,
              dialed_at TEXT,
              xp_awarded INTEGER DEFAULT 0,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_today_last10 ON $tableName (last10)',
          );

          await db.execute('''
            CREATE TABLE $batchTableName (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              lead_id INTEGER,
              record_id INTEGER,
              name TEXT,
              phone_number TEXT,
              last10 TEXT NOT NULL,
              company TEXT,
              source TEXT,
              batch_fetched_at TEXT,
              expires_at TEXT,
              status TEXT DEFAULT 'PENDING',
              call_duration INTEGER DEFAULT 0,
              call_status TEXT,
              raw_json TEXT,
              sort_order INTEGER,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_batch_last10 ON $batchTableName (last10)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_batch_status ON $batchTableName (status)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $batchTableName (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                lead_id INTEGER,
                record_id INTEGER,
                name TEXT,
                phone_number TEXT,
                last10 TEXT NOT NULL,
                company TEXT,
                source TEXT,
                batch_fetched_at TEXT,
                expires_at TEXT,
                status TEXT DEFAULT 'PENDING',
                call_duration INTEGER DEFAULT 0,
                call_status TEXT,
                raw_json TEXT,
                sort_order INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_batch_last10 ON $batchTableName (last10)',
            );
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_batch_status ON $batchTableName (status)',
            );
          }
        },
      );

      // Ensure batch table exists defensively
      await _db?.execute('''
        CREATE TABLE IF NOT EXISTS $batchTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          lead_id INTEGER,
          record_id INTEGER,
          name TEXT,
          phone_number TEXT,
          last10 TEXT NOT NULL,
          company TEXT,
          source TEXT,
          batch_fetched_at TEXT,
          expires_at TEXT,
          status TEXT DEFAULT 'PENDING',
          call_duration INTEGER DEFAULT 0,
          call_status TEXT,
          raw_json TEXT,
          sort_order INTEGER,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    } catch (e) {
      debugPrint(
        '[TodayDialedHistory] SQLite init notice (test or fallback): $e',
      );
    }
  }

  @override
  Future<void> insertOrUpdate(Map<String, dynamic> call) async {
    await init();
    final db = _db;
    if (db == null) return;

    final last10 = call['last10']?.toString() ?? '';
    if (last10.isEmpty) return;

    // Delete older occurrence for same 10-digit number to maintain fresh status
    await db.delete(tableName, where: 'last10 = ?', whereArgs: [last10]);
    await db.insert(
      tableName,
      call,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, dynamic>?> findByLast10(String last10) async {
    await init();
    final db = _db;
    if (db == null || last10.isEmpty) return null;

    final results = await db.query(
      tableName,
      where: 'last10 = ?',
      whereArgs: [last10],
      orderBy: 'id DESC',
      limit: 1,
    );
    return results.isNotEmpty ? Map<String, dynamic>.from(results.first) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll() async {
    await init();
    final db = _db;
    if (db == null) return [];

    final results = await db.query(tableName, orderBy: 'id DESC');
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  @override
  Future<int> getCount() async {
    await init();
    final db = _db;
    if (db == null) return 0;

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableName'),
    );
    return count ?? 0;
  }

  @override
  Future<int> getTotalDuration() async {
    await init();
    final db = _db;
    if (db == null) return 0;

    final res = await db.rawQuery(
      'SELECT SUM(duration) as total FROM $tableName',
    );
    if (res.isNotEmpty && res.first['total'] != null) {
      return (res.first['total'] as num).toInt();
    }
    return 0;
  }

  @override
  Future<void> clear() async {
    await init();
    final db = _db;
    if (db != null && db.isOpen) {
      await db.delete(tableName);
    }
  }

  @override
  Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
      _db = null;
    }
  }

  // --- Batch Operations (SQLite) ---

  @override
  Future<void> saveBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;

    // Delete existing pending/uncalled batch leads
    await db.delete(batchTableName, where: "status = 'PENDING'");

    final batch = db.batch();
    for (int i = 0; i < leads.length; i++) {
      final lead = leads[i];
      final phone =
          (lead['mobile'] ?? lead['phone_number'] ?? lead['phone'] ?? '')
              .toString();
      final last10 = TodayDialedHistoryService.normalizeLast10(phone);
      if (last10.isEmpty) continue;

      batch.insert(batchTableName, {
        'lead_id': _tryParseInt(lead['lead_id']) ?? _tryParseInt(lead['id']),
        'record_id':
            _tryParseInt(lead['record_id']) ?? _tryParseInt(lead['id']),
        'name': lead['name']?.toString() ?? '',
        'phone_number': phone,
        'last10': last10,
        'company': lead['company']?.toString() ?? '',
        'source': lead['source']?.toString() ?? 'BATCH',
        'batch_fetched_at': DateTime.now().toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': 'PENDING',
        'call_duration': 0,
        'call_status': null,
        'raw_json': jsonEncode(lead),
        'sort_order': i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    debugPrint(
      '[TodayDialedHistory] Saved ${leads.length} batch leads to SQLite.',
    );
  }

  @override
  Future<void> appendBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    await init();
    final db = _db;
    if (db == null) return;

    // Reset expiry for active leads in queue
    await db.update(batchTableName, {
      'expires_at': expiresAt.toIso8601String(),
    }, where: "status IN ('PENDING', 'DIALED')");

    final maxRes = await db.rawQuery(
      'SELECT MAX(sort_order) as max_sort FROM $batchTableName',
    );
    int baseSort = 0;
    if (maxRes.isNotEmpty && maxRes.first['max_sort'] != null) {
      baseSort = (maxRes.first['max_sort'] as num).toInt() + 1;
    }

    final batch = db.batch();
    for (int i = 0; i < leads.length; i++) {
      final lead = leads[i];
      final phone =
          (lead['mobile'] ?? lead['phone_number'] ?? lead['phone'] ?? '')
              .toString();
      final last10 = TodayDialedHistoryService.normalizeLast10(phone);
      if (last10.isEmpty) continue;

      batch.insert(batchTableName, {
        'lead_id': _tryParseInt(lead['lead_id']) ?? _tryParseInt(lead['id']),
        'record_id':
            _tryParseInt(lead['record_id']) ?? _tryParseInt(lead['id']),
        'name': lead['name']?.toString() ?? '',
        'phone_number': phone,
        'last10': last10,
        'company': lead['company']?.toString() ?? '',
        'source': lead['source']?.toString() ?? 'BATCH',
        'batch_fetched_at': DateTime.now().toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': 'PENDING',
        'call_duration': 0,
        'call_status': null,
        'raw_json': jsonEncode(lead),
        'sort_order': baseSort + i,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    debugPrint(
      '[TodayDialedHistory] Appended ${leads.length} batch leads to SQLite.',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveBatchLeads() async {
    await init();
    final db = _db;
    if (db == null) return [];

    final rows = await db.query(
      batchTableName,
      where: "status IN ('PENDING', 'DIALED')",
      orderBy: 'sort_order ASC, id ASC',
    );

    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      Map<String, dynamic> lead;
      final raw = row['raw_json']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          lead = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          lead = Map<String, dynamic>.from(row);
        }
      } else {
        lead = Map<String, dynamic>.from(row);
      }
      lead['local_batch_status'] = row['status'];
      lead['local_call_duration'] = row['call_duration'];
      lead['local_call_status'] = row['call_status'];
      list.add(lead);
    }
    return list;
  }

  @override
  Future<void> updateBatchLeadStatus(
    String last10, {
    required String status,
    int? duration,
    String? callStatus,
  }) async {
    await init();
    final db = _db;
    if (db == null || last10.isEmpty) return;

    final values = <String, dynamic>{'status': status};
    if (duration != null) {
      values['call_duration'] = duration;
    }
    if (callStatus != null) {
      values['call_status'] = callStatus;
    }

    await db.update(
      batchTableName,
      values,
      where: 'last10 = ?',
      whereArgs: [last10],
    );
  }

  @override
  Future<Map<String, dynamic>?> getBatchLeadByLast10(String last10) async {
    await init();
    final db = _db;
    if (db == null || last10.isEmpty) return null;

    final rows = await db.query(
      batchTableName,
      where: 'last10 = ?',
      whereArgs: [last10],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    Map<String, dynamic> lead;
    final raw = row['raw_json']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        lead = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        lead = Map<String, dynamic>.from(row);
      }
    } else {
      lead = Map<String, dynamic>.from(row);
    }
    lead['local_batch_status'] = row['status'];
    lead['local_call_duration'] = row['call_duration'];
    lead['local_call_status'] = row['call_status'];
    return lead;
  }

  @override
  Future<int> getUncalledBatchLeadsCount() async {
    await init();
    final db = _db;
    if (db == null) return 0;

    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM $batchTableName WHERE status IN ('PENDING', 'DIALED')",
      ),
    );
    return count ?? 0;
  }

  @override
  Future<DateTime?> getBatchExpiryTime() async {
    await init();
    final db = _db;
    if (db == null) return null;

    final rows = await db.query(
      batchTableName,
      columns: ['expires_at'],
      where: "status IN ('PENDING', 'DIALED') AND expires_at IS NOT NULL",
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['expires_at'] != null) {
      return DateTime.tryParse(rows.first['expires_at'].toString());
    }
    return null;
  }

  @override
  Future<void> clearBatchLeads() async {
    await init();
    final db = _db;
    if (db != null && db.isOpen) {
      await db.delete(batchTableName);
    }
  }
}

/// Service managing Today's Dialed Call History.
/// Used to strictly verify incoming customer callbacks, insulate telecallers from
/// personal call intrusion (family/spouse), compute XP metrics, and cache reports.
class TodayDialedHistoryService {
  static TodayDialedHistoryService? _instance;
  static TodayDialedHistoryService get instance =>
      _instance ??= TodayDialedHistoryService._internal();

  TodayDialedHistoryService._internal() {
    _backend =
        (kIsWeb ||
            (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')))
        ? MemoryTodayDialedHistoryBackend()
        : SqfliteTodayDialedHistoryBackend();
  }

  late TodayDialedHistoryBackend _backend;

  /// Test backend injection override
  @visibleForTesting
  static void setBackendForTesting(TodayDialedHistoryBackend backend) {
    instance._backend = backend;
  }

  @visibleForTesting
  static void resetBackend() {
    instance._backend =
        (kIsWeb ||
            (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')))
        ? MemoryTodayDialedHistoryBackend()
        : SqfliteTodayDialedHistoryBackend();
  }

  /// Normalize any phone number to its last 10 numeric digits
  static String normalizeLast10(String? phoneNumber) {
    if (phoneNumber == null) return '';
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 10) {
      return clean.substring(clean.length - 10);
    }
    return clean;
  }

  /// Initialize the local SQLite database
  Future<void> init() async {
    await _backend.init();
  }

  /// Record a call dialed today into the local database
  Future<void> recordDialedCall({
    int? serverCallId,
    int? recordId,
    int? leadId,
    String? name,
    required String phoneNumber,
    String? company,
    String? source,
    String? status,
    int duration = 0,
    String? timingTier,
    String? dialedAt,
    int xpAwarded = 0,
  }) async {
    final last10 = normalizeLast10(phoneNumber);
    if (last10.isEmpty) return;

    final record = <String, dynamic>{
      'server_call_id': serverCallId,
      'record_id': recordId,
      'lead_id': leadId,
      'name': name ?? '',
      'phone_number': phoneNumber,
      'last10': last10,
      'company': company ?? '',
      'source': source ?? 'MAIN',
      'status': status ?? 'DIALED',
      'duration': duration,
      'timing_tier': timingTier ?? 'NOT_CONNECTED',
      'dialed_at': dialedAt ?? DateTime.now().toIso8601String(),
      'xp_awarded': xpAwarded,
    };

    await _backend.insertOrUpdate(record);
    debugPrint(
      '[TodayDialedHistory] Recorded call to $name ($last10, ${duration}s, status=$status)',
    );
  }

  /// Find a call record from today's dialed history by phone number.
  /// Returns null if this number was NOT dialed today by the telecaller.
  Future<Map<String, dynamic>?> findDialedCall(String phoneNumber) async {
    final last10 = normalizeLast10(phoneNumber);
    if (last10.isEmpty) return null;
    return await _backend.findByLast10(last10);
  }

  /// Fast boolean check to see if a phone number was dialed today
  Future<bool> wasDialedToday(String phoneNumber) async {
    final found = await findDialedCall(phoneNumber);
    return found != null;
  }

  /// Synchronize today's dialed calls from the server
  Future<int> syncWithServer() async {
    try {
      final res = await ApiService.getCallHistory(period: 'today', limit: 100);
      final rawCalls = res['data'] ?? res['calls'];
      if (rawCalls is! List) return 0;

      int syncedCount = 0;
      for (final item in rawCalls) {
        if (item is Map) {
          final phone = (item['phone_number'] ?? item['mobile'] ?? '')
              .toString();
          if (phone.isNotEmpty) {
            await recordDialedCall(
              serverCallId: _tryParseInt(item['id']),
              recordId: _tryParseInt(item['record_id']),
              leadId: _tryParseInt(item['lead_id']),
              name: item['name']?.toString(),
              phoneNumber: phone,
              company: item['company']?.toString(),
              source: item['source']?.toString(),
              status:
                  item['call_status']?.toString() ?? item['status']?.toString(),
              duration:
                  _tryParseInt(item['call_duration']) ??
                  _tryParseInt(item['duration']) ??
                  0,
              timingTier: item['timing_classification']?.toString(),
              dialedAt:
                  item['created_at']?.toString() ??
                  item['call_date']?.toString(),
            );
            syncedCount++;
          }
        }
      }
      debugPrint(
        '[TodayDialedHistory] Successfully synchronized $syncedCount calls from server.',
      );
      return syncedCount;
    } catch (e) {
      debugPrint('[TodayDialedHistory] Server sync warning: $e');
      return 0;
    }
  }

  /// Retrieve all calls dialed today
  Future<List<Map<String, dynamic>>> getTodayDialedCalls() async {
    return await _backend.getAll();
  }

  /// Total count of calls dialed today
  Future<int> getTodayCallsCount() async {
    return await _backend.getCount();
  }

  /// Total duration in seconds of calls dialed today
  Future<int> getTodayTotalDuration() async {
    return await _backend.getTotalDuration();
  }

  /// Wipe all today's dialed history (invoked on logout and midnight reset)
  Future<void> clearAll() async {
    await _backend.clear();
    await _backend.clearBatchLeads();
    await CallBucketService.clear();
    debugPrint(
      '[TodayDialedHistory] Cleared all local call history and batch leads.',
    );
  }

  // --- 15-Minute Batch Queue Operations ---

  /// Save freshly fetched 15 batch leads from server into SQLite table current_batch_leads
  Future<void> saveBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    await _backend.saveBatchLeads(leads, expiresAt: expiresAt);
  }

  /// Proactively append new leads to the current active batch and reset the lease expiration
  Future<void> appendBatchLeads(
    List<Map<String, dynamic>> leads, {
    required DateTime expiresAt,
  }) async {
    await _backend.appendBatchLeads(leads, expiresAt: expiresAt);
  }

  /// Retrieve all uncompleted leads in the current batch from SQLite
  Future<List<Map<String, dynamic>>> getActiveBatchLeads() async {
    return await _backend.getActiveBatchLeads();
  }

  /// Update the status and call outcome of a lead in the batch
  Future<void> updateBatchLeadStatus(
    String phoneNumber, {
    required String status,
    int? duration,
    String? callStatus,
  }) async {
    final last10 = normalizeLast10(phoneNumber);
    if (last10.isEmpty) return;
    await _backend.updateBatchLeadStatus(
      last10,
      status: status,
      duration: duration,
      callStatus: callStatus,
    );
  }

  /// Find a lead in the current batch by phone number
  Future<Map<String, dynamic>?> getBatchLead(String phoneNumber) async {
    final last10 = normalizeLast10(phoneNumber);
    if (last10.isEmpty) return null;
    return await _backend.getBatchLeadByLast10(last10);
  }

  /// Count remaining uncalled leads in the current batch
  Future<int> getUncalledBatchLeadsCount() async {
    return await _backend.getUncalledBatchLeadsCount();
  }

  /// Get the current batch expiry timestamp
  Future<DateTime?> getBatchExpiryTime() async {
    return await _backend.getBatchExpiryTime();
  }

  /// Clear the local batch leads table
  Future<void> clearBatchLeads() async {
    await _backend.clearBatchLeads();
    debugPrint('[TodayDialedHistory] Cleared local current batch leads.');
  }
}
