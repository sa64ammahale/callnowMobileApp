package me.sodipto.phone_state_background

import androidx.annotation.NonNull
import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** PhoneStateBackgroundPlugin */
class PhoneStateBackgroundPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  companion object {
    const val PLUGIN_NAME = "me.sodipto.phone_state_background"
    const val CALLBACK_SHAREDPREFERENCES_KEY = "phoneStateBackgroundPluginCallbackHandler"
    const val CALLBACK_USER_SHAREDPREFERENCES_KEY = "phoneStateBackgroundCallbackHandlerUser"
  }

  private var channel: MethodChannel? = null
  private var currentActivity: Activity? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, PLUGIN_NAME)
    channel!!.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val arguments = call.arguments as ArrayList<*>?
    if (call.method == "initialize" && arguments?.size == 2) {
      if (!doCheckPermission()) {
        result.error("MISSING_PERMISSION", null, null)
        return
      }
      val sharedPref = currentActivity!!.getSharedPreferences(PLUGIN_NAME, Context.MODE_PRIVATE)
      val editor = sharedPref.edit()
      val arg0 = arguments[0]
      val arg1 = arguments[1]
      val arg0Long: Long = if (arg0 is Long) arg0 else (arg0 as Int).toLong()
      val arg1Long: Long = if (arg1 is Long) arg1 else (arg1 as Int).toLong()
      editor.putLong(CALLBACK_SHAREDPREFERENCES_KEY, arg0Long)
      editor.putLong(CALLBACK_USER_SHAREDPREFERENCES_KEY, arg1Long)
      editor.commit()

      val context = currentActivity!!.applicationContext
      val receiver = ComponentName(context, PhoneStateBackgroundServiceReceiver::class.java)
      context.packageManager.setComponentEnabledSetting(
        receiver,
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
        PackageManager.DONT_KILL_APP
      )
      Log.d(PLUGIN_NAME, "Service initialized...")
      result.success(true)

    } else if (call.method == "stopcallstate") {
      val sharedPref = currentActivity!!.getSharedPreferences(PLUGIN_NAME, Context.MODE_PRIVATE)
      val editor = sharedPref.edit()
      editor.remove(CALLBACK_SHAREDPREFERENCES_KEY)
      editor.remove(CALLBACK_USER_SHAREDPREFERENCES_KEY)
      val context: Context = currentActivity!!.applicationContext
      val receiver = ComponentName(context, PhoneStateBackgroundServiceReceiver::class.java)
      context.packageManager.setComponentEnabledSetting(
        receiver,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        PackageManager.DONT_KILL_APP
      )
      editor.commit()
      result.success(true)

    } else if (call.method == "requestPermissions") {
      Log.d(PLUGIN_NAME, "Requesting permissions via standard Android dialog...")
      requestPermissions(result)

    } else if (call.method == "checkPermissions") {
      val check = doCheckPermission()
      Log.d(PLUGIN_NAME, "Permission checked: $check")
      result.success(check)

    } else if (call.method == "checkPermissionDetails") {
      val details = HashMap<String, Boolean>()
      if (currentActivity != null) {
        val grantedCode = PackageManager.PERMISSION_GRANTED
        details["phone_state"] = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.READ_PHONE_STATE) == grantedCode
        details["call_log"] = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.READ_CALL_LOG) == grantedCode
        details["call_phone"] = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.CALL_PHONE) == grantedCode
      } else {
        details["phone_state"] = false
        details["call_log"] = false
        details["call_phone"] = false
      }
      result.success(details)

    } else if (call.method == "openAppSettings") {
      if (currentActivity != null) {
        try {
          val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", currentActivity!!.packageName, null)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
          }
          currentActivity!!.startActivity(intent)
          result.success(true)
        } catch (e: Exception) {
          Log.e(PLUGIN_NAME, "Error opening app settings: ${e.message}")
          result.success(false)
        }
      } else {
        result.success(false)
      }

    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    channel!!.setMethodCallHandler(null)
  }

  private fun doCheckPermission(): Boolean {
    if (currentActivity != null && currentActivity!!.applicationContext != null) {
      val permPhoneState = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.READ_PHONE_STATE)
      val permReadCallLog = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.READ_CALL_LOG)
      val permCallPhone = ContextCompat.checkSelfPermission(currentActivity!!, Manifest.permission.CALL_PHONE)
      val grantedCode = PackageManager.PERMISSION_GRANTED
      return permPhoneState == grantedCode && permReadCallLog == grantedCode && permCallPhone == grantedCode
    }
    return false
  }

  private fun requestPermissions(result: Result? = null) {
    if (currentActivity == null) {
      result?.success(false)
      return
    }

    val grantedCode = PackageManager.PERMISSION_GRANTED
    val permissions = arrayOf(
      Manifest.permission.READ_PHONE_STATE,
      Manifest.permission.READ_CALL_LOG,
      Manifest.permission.CALL_PHONE
    )
    val permissionsToAsk = arrayListOf<String>()

    for (permission in permissions) {
      val permState = ContextCompat.checkSelfPermission(currentActivity!!, permission)
      if (permState != grantedCode) {
        permissionsToAsk.add(permission)
      }
    }

    if (permissionsToAsk.isNotEmpty()) {
      ActivityCompat.requestPermissions(currentActivity!!, permissionsToAsk.toTypedArray(), 999)
    }
    result?.success(permissionsToAsk.isEmpty())
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    currentActivity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    currentActivity = null
  }

  override fun onDetachedFromActivity() {
    currentActivity = null
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
    return when (requestCode) {
      999 -> grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
      else -> false
    }
  }
}
