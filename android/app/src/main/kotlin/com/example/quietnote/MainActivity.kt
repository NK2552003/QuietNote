package com.example.quietnote

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.quietnote/floating_bubble"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showBubble" -> {
                    val endsAt = (call.argument<Number>("endsAt")?.toLong()) ?: (System.currentTimeMillis() + 25 * 60 * 1000)
                    val totalSeconds = (call.argument<Number>("totalSeconds")?.toInt()) ?: (25 * 60)
                    val phase = call.argument<String>("phase") ?: "work"
                    val label = call.argument<String>("label") ?: "Focus"

                    if (!Settings.canDrawOverlays(this)) {
                        try {
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(permIntent)
                        } catch (_: Exception) {}
                    }

                    val intent = Intent(this, FloatingBubbleService::class.java).apply {
                        action = FloatingBubbleService.ACTION_SHOW
                        putExtra(FloatingBubbleService.EXTRA_ENDS_AT, endsAt)
                        putExtra(FloatingBubbleService.EXTRA_TOTAL_SECONDS, totalSeconds)
                        putExtra(FloatingBubbleService.EXTRA_PHASE, phase)
                        putExtra(FloatingBubbleService.EXTRA_LABEL, label)
                    }
                    startService(intent)
                    result.success(true)
                }
                "updateBubble" -> {
                    val endsAt = (call.argument<Number>("endsAt")?.toLong()) ?: System.currentTimeMillis()
                    val totalSeconds = (call.argument<Number>("totalSeconds")?.toInt()) ?: (25 * 60)
                    val phase = call.argument<String>("phase") ?: "work"
                    val label = call.argument<String>("label") ?: "Focus"

                    val intent = Intent(this, FloatingBubbleService::class.java).apply {
                        action = FloatingBubbleService.ACTION_UPDATE
                        putExtra(FloatingBubbleService.EXTRA_ENDS_AT, endsAt)
                        putExtra(FloatingBubbleService.EXTRA_TOTAL_SECONDS, totalSeconds)
                        putExtra(FloatingBubbleService.EXTRA_PHASE, phase)
                        putExtra(FloatingBubbleService.EXTRA_LABEL, label)
                    }
                    startService(intent)
                    result.success(true)
                }
                "hideBubble" -> {
                    val intent = Intent(this, FloatingBubbleService::class.java).apply {
                        action = FloatingBubbleService.ACTION_HIDE
                    }
                    startService(intent)
                    result.success(true)
                }
                "notifyAppForeground" -> {
                    if (FloatingBubbleService.isRunning) {
                        val intent = Intent(this, FloatingBubbleService::class.java).apply {
                            action = FloatingBubbleService.ACTION_APP_FOREGROUND
                        }
                        startService(intent)
                    }
                    result.success(true)
                }
                "notifyAppBackground" -> {
                    if (FloatingBubbleService.isRunning) {
                        val intent = Intent(this, FloatingBubbleService::class.java).apply {
                            action = FloatingBubbleService.ACTION_APP_BACKGROUND
                        }
                        startService(intent)
                    }
                    result.success(true)
                }
                "checkPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestPermission" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (FloatingBubbleService.isRunning) {
            val intent = Intent(this, FloatingBubbleService::class.java).apply {
                action = FloatingBubbleService.ACTION_APP_FOREGROUND
            }
            startService(intent)
        }
    }

    override fun onPause() {
        super.onPause()
        if (FloatingBubbleService.isRunning) {
            val intent = Intent(this, FloatingBubbleService::class.java).apply {
                action = FloatingBubbleService.ACTION_APP_BACKGROUND
            }
            startService(intent)
        }
    }
}
