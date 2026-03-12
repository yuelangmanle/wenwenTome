package com.wenwentome.wenwen_tome

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.view.KeyEvent
import com.tekartik.sqflite.SqflitePlugin
import dev.fluttercommunity.plus.share.SharePlusPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugins.pathprovider.PathProviderPlugin
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val COMPANION_CHANNEL = "wenwen_tome/android_companion"
        private const val READER_VOLUME_CONTROL_CHANNEL = "wenwen_tome/reader_volume_control"
        private const val READER_VOLUME_EVENT_CHANNEL = "wenwen_tome/reader_volume_events"
        private const val COMPANION_PACKAGE = "com.wenwentome.tts_companion"
        private const val COMPANION_ACTION = "com.wenwentome.tts_companion.START"
        private const val TAG = "MainActivity"
    }

    private var volumePagingEnabled: Boolean = false
    private var volumeEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureCorePlugins(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMPANION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchCompanion" -> result.success(launchCompanion())
                    "isCompanionInstalled" -> result.success(isCompanionInstalled())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_VOLUME_CONTROL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumePagingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    volumePagingEnabled = enabled
                    result.success(true)
                }
                "isVolumePagingEnabled" -> result.success(volumePagingEnabled)
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            READER_VOLUME_EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    volumeEventSink = null
                }
            },
        )
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!volumePagingEnabled) {
            return super.onKeyDown(keyCode, event)
        }
        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN,
            -> true
            else -> super.onKeyDown(keyCode, event)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumePagingEnabled) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP,
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                        volumeEventSink?.success(
                            if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                                "volume_up"
                            } else {
                                "volume_down"
                            },
                        )
                    }
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun ensureCorePlugins(flutterEngine: FlutterEngine) {
        ensurePlugin(flutterEngine, "PathProviderPlugin") {
            PathProviderPlugin()
        }
        ensurePlugin(flutterEngine, "SharedPreferencesPlugin") {
            SharedPreferencesPlugin()
        }
        ensurePlugin(flutterEngine, "SqflitePlugin") {
            SqflitePlugin()
        }
        ensurePlugin(flutterEngine, "SharePlusPlugin") {
            SharePlusPlugin()
        }
    }

    private fun ensurePlugin(
        flutterEngine: FlutterEngine,
        name: String,
        builder: () -> FlutterPlugin,
    ) {
        try {
            flutterEngine.plugins.add(builder())
        } catch (error: Throwable) {
            Log.w(TAG, "Plugin registration skipped for $name", error)
        }
    }

    private fun isCompanionInstalled(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    COMPANION_PACKAGE,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(COMPANION_PACKAGE, 0)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun launchCompanion(): Boolean {
        val launchIntent = packageManager.getLaunchIntentForPackage(COMPANION_PACKAGE)
        if (launchIntent != null) {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            return true
        }

        val actionIntent = Intent(COMPANION_ACTION).apply {
            `package` = COMPANION_PACKAGE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val resolved = actionIntent.resolveActivity(packageManager)
        if (resolved != null) {
            startActivity(actionIntent)
            return true
        }

        return false
    }
}
