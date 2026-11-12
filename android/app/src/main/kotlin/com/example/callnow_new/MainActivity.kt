package com.example.callnow_new

import android.Manifest
import android.content.pm.PackageManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.CallLog
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.callnow/call_verifier"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLatestCallLog" -> {
                    val rawNumber = call.argument<String>("phoneNumber") ?: ""
                    val afterTimestamp = (call.argument<Number>("afterTimestamp"))?.toLong() ?: 0L
                    val callData = queryCallLog(rawNumber, afterTimestamp)
                    result.success(callData)
                }
                "checkCallLogPermission" -> {
                    val hasPerm = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_CALL_LOG
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPerm)
                }
                "openWhatsApp" -> {
                    val phoneNumber = call.argument<String>("phoneNumber").orEmpty()
                    val message = call.argument<String>("message").orEmpty()
                    result.success(openWhatsApp(phoneNumber, message))
                }
                "getRecentCallLogs" -> {
                    val limit = (call.argument<Number>("limit"))?.toInt() ?: 15
                    val afterTimestamp = (call.argument<Number>("afterTimestamp"))?.toLong() ?: 0L
                    val callLogs = queryRecentCallLogs(limit, afterTimestamp)
                    result.success(callLogs)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openWhatsApp(phoneNumber: String, message: String): Boolean {
        val cleanNumber = phoneNumber.replace(Regex("[^0-9]"), "")
        if (cleanNumber.isEmpty()) return false

        val chatUri = Uri.Builder()
            .scheme("https")
            .authority("wa.me")
            .appendPath(cleanNumber)
            .apply {
                if (message.isNotEmpty()) appendQueryParameter("text", message)
            }
            .build()

        for (packageName in listOf("com.whatsapp.w4b", "com.whatsapp")) {
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, chatUri)
                        .setPackage(packageName)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next installed WhatsApp app.
            }
        }
        return false
    }

    private fun queryCallLog(targetNumber: String, afterTimestamp: Long): Map<String, Any?> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) 
            != PackageManager.PERMISSION_GRANTED) {
            return mapOf(
                "isDialed" to false,
                "hasPermission" to false,
                "number" to targetNumber,
                "duration" to 0L,
                "timestamp" to 0L,
                "type" to 0,
                "error" to "PERMISSION_DENIED"
            )
        }

        val cleanTarget = targetNumber.replace(Regex("[^0-9]"), "")
        val last10Target = if (cleanTarget.length >= 10) cleanTarget.takeLast(10) else cleanTarget

        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )

        // Query outgoing calls ordered by DATE DESC
        val selection = "${CallLog.Calls.TYPE} = ?"
        val selectionArgs = arrayOf(CallLog.Calls.OUTGOING_TYPE.toString())
        val sortOrder = "${CallLog.Calls.DATE} DESC"

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            if (cursor != null && cursor.moveToFirst()) {
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)

                var checkedCount = 0
                do {
                    val num = if (numIdx != -1) cursor.getString(numIdx) ?: "" else ""
                    val callDate = if (dateIdx != -1) cursor.getLong(dateIdx) else 0L
                    val duration = if (durIdx != -1) cursor.getLong(durIdx) else 0L
                    val callType = if (typeIdx != -1) cursor.getInt(typeIdx) else 0

                    val cleanNum = num.replace(Regex("[^0-9]"), "")
                    val last10Num = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum

                    val isMatch = (last10Target.isNotEmpty() && (last10Num == last10Target || cleanNum.endsWith(last10Target) || last10Target.endsWith(cleanNum)))
                    val timestampValid = (afterTimestamp <= 0L) || (callDate >= (afterTimestamp - (2 * 3600 * 1000L)))

                    if (isMatch && timestampValid) {
                        android.util.Log.d("CallVerifier", "MATCH FOUND: num=$num, duration=${duration}s, date=$callDate")
                        return mapOf(
                            "isDialed" to true,
                            "hasPermission" to true,
                            "number" to num,
                            "duration" to duration,
                            "timestamp" to callDate,
                            "type" to callType
                        )
                    }
                    checkedCount++
                    if (checkedCount >= 50) break
                } while (cursor.moveToNext())
            }
        } catch (e: Exception) {
            android.util.Log.e("CallVerifier", "Query error: ${e.message}")
            return mapOf(
                "isDialed" to false,
                "hasPermission" to true,
                "number" to targetNumber,
                "duration" to 0L,
                "timestamp" to 0L,
                "type" to 0,
                "error" to (e.message ?: "QUERY_FAILED")
            )
        } finally {
            cursor?.close()
        }

        android.util.Log.d("CallVerifier", "NO MATCH for target=$targetNumber (clean=$cleanTarget, last10=$last10Target)")
        return mapOf(
            "isDialed" to false,
            "hasPermission" to true,
            "number" to targetNumber,
            "duration" to 0L,
            "timestamp" to 0L,
            "type" to 0
        )
    }

    private fun queryRecentCallLogs(limit: Int, afterTimestamp: Long): List<Map<String, Any?>> {
        val resultList = mutableListOf<Map<String, Any?>>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) 
            != PackageManager.PERMISSION_GRANTED) {
            return resultList
        }

        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.CACHED_NAME
        )

        val selection = if (afterTimestamp > 0) "${CallLog.Calls.DATE} >= ?" else null
        val selectionArgs = if (afterTimestamp > 0) arrayOf(afterTimestamp.toString()) else null
        val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $limit"

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            if (cursor != null && cursor.moveToFirst()) {
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)

                do {
                    val rawNum = if (numIdx != -1) cursor.getString(numIdx) ?: "" else ""
                    val callType = if (typeIdx != -1) cursor.getInt(typeIdx) else 0
                    val callDate = if (dateIdx != -1) cursor.getLong(dateIdx) else 0L
                    val duration = if (durIdx != -1) cursor.getLong(durIdx) else 0L
                    val cachedName = if (nameIdx != -1) cursor.getString(nameIdx) ?: "" else ""

                    val cleanNum = rawNum.replace(Regex("[^0-9]"), "")
                    val last10 = if (cleanNum.length >= 10) cleanNum.takeLast(10) else cleanNum

                    val typeStr = when (callType) {
                        CallLog.Calls.INCOMING_TYPE -> "INCOMING"
                        CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                        CallLog.Calls.MISSED_TYPE -> "MISSED"
                        CallLog.Calls.REJECTED_TYPE -> "REJECTED"
                        else -> "OTHER"
                    }

                    resultList.add(
                        mapOf(
                            "number" to rawNum,
                            "cleanNumber" to last10,
                            "type" to callType,
                            "typeName" to typeStr,
                            "isIncoming" to (callType == CallLog.Calls.INCOMING_TYPE),
                            "duration" to duration,
                            "timestamp" to callDate,
                            "cachedName" to cachedName
                        )
                    )
                } while (cursor.moveToNext() && resultList.size < limit)
            }
        } catch (e: Exception) {
            android.util.Log.e("CallVerifier", "queryRecentCallLogs error: ${e.message}")
        } finally {
            cursor?.close()
        }

        return resultList
    }
}
