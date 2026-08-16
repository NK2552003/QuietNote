package com.example.quietnote

import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import kotlin.math.abs

/**
 * High-End Floating System Overlay for QuietNote.
 * Displays a live edge pill / dynamic island over other apps when focus timer is active.
 */
class FloatingBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var islandView: IslandCustomView? = null
    private var params: WindowManager.LayoutParams? = null

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    private val handler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var collapseRunnable: Runnable? = null

    private var endsAtMillis: Long = 0
    private var totalSeconds: Int = 25 * 60
    private var phase: String = "work"
    private var presetLabel: String = "Focus"

    // 0 = Docked Left, 1 = Docked Right, 2 = Expanded Island
    private var viewMode = 0
    private var isAppForeground = false

    companion object {
        private const val TAG = "FloatingBubbleService"
        const val ACTION_SHOW = "com.quietnote.ACTION_SHOW_BUBBLE"
        const val ACTION_UPDATE = "com.quietnote.ACTION_UPDATE_BUBBLE"
        const val ACTION_HIDE = "com.quietnote.ACTION_HIDE_BUBBLE"
        const val ACTION_APP_FOREGROUND = "com.quietnote.ACTION_APP_FOREGROUND"
        const val ACTION_APP_BACKGROUND = "com.quietnote.ACTION_APP_BACKGROUND"

        const val EXTRA_ENDS_AT = "ends_at"
        const val EXTRA_TOTAL_SECONDS = "total_seconds"
        const val EXTRA_PHASE = "phase"
        const val EXTRA_LABEL = "label"

        var isRunning = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        when (intent.action) {
            ACTION_SHOW -> {
                endsAtMillis = intent.getLongExtra(EXTRA_ENDS_AT, System.currentTimeMillis() + 25 * 60 * 1000)
                totalSeconds = intent.getIntExtra(EXTRA_TOTAL_SECONDS, 25 * 60)
                phase = intent.getStringExtra(EXTRA_PHASE) ?: "work"
                presetLabel = intent.getStringExtra(EXTRA_LABEL) ?: "Focus"

                ensureViewCreated()
                updateViewVisibility()
                startPeriodicTicker()
            }
            ACTION_UPDATE -> {
                endsAtMillis = intent.getLongExtra(EXTRA_ENDS_AT, endsAtMillis)
                totalSeconds = intent.getIntExtra(EXTRA_TOTAL_SECONDS, totalSeconds)
                phase = intent.getStringExtra(EXTRA_PHASE) ?: phase
                presetLabel = intent.getStringExtra(EXTRA_LABEL) ?: presetLabel

                ensureViewCreated()
                islandView?.updateData(endsAtMillis, totalSeconds, phase, presetLabel)
                updateViewVisibility()
                startPeriodicTicker()
            }
            ACTION_APP_FOREGROUND -> {
                isAppForeground = true
                cancelCollapse()
                islandView?.visibility = View.GONE
            }
            ACTION_APP_BACKGROUND -> {
                isAppForeground = false
                if (endsAtMillis > System.currentTimeMillis()) {
                    ensureViewCreated()
                    islandView?.visibility = View.VISIBLE
                    islandView?.postInvalidate()
                    snapToEdge(animate = false)
                    startPeriodicTicker()
                }
            }
            ACTION_HIDE -> {
                hideIsland()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun updateViewVisibility() {
        if (islandView == null) return
        if (isAppForeground) {
            islandView?.visibility = View.GONE
        } else {
            if (endsAtMillis > System.currentTimeMillis()) {
                islandView?.visibility = View.VISIBLE
                islandView?.postInvalidate()
            } else {
                islandView?.visibility = View.GONE
            }
        }
    }

    private fun ensureViewCreated() {
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Cannot draw overlays: Permission not granted")
            return
        }

        val density = resources.displayMetrics.density
        val dockedW = (72 * density).toInt()
        val dockedH = (36 * density).toInt()

        if (islandView == null) {
            islandView = IslandCustomView(this).apply {
                updateData(endsAtMillis, totalSeconds, phase, presetLabel)
            }

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            params = WindowManager.LayoutParams(
                dockedW,
                dockedH,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = (8 * density).toInt()
                y = (160 * density).toInt()
            }

            setupTouchListener()
            try {
                windowManager?.addView(islandView, params)
                snapToEdge(animate = false)
            } catch (e: Exception) {
                Log.e(TAG, "Error adding overlay view to window manager", e)
            }
        } else {
            islandView?.updateData(endsAtMillis, totalSeconds, phase, presetLabel)
        }
    }

    private fun setupTouchListener() {
        islandView?.setOnTouchListener { _, event ->
            val p = params ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    cancelCollapse()
                    initialX = p.x
                    initialY = p.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    islandView?.setPressedState(true)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()
                    if (abs(dx) > 5 || abs(dy) > 5) {
                        isDragging = true
                        p.x = initialX + dx
                        p.y = initialY + dy
                        try {
                            windowManager?.updateViewLayout(islandView, p)
                        } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    islandView?.setPressedState(false)
                    if (!isDragging) {
                        if (viewMode == 2) {
                            openQuietNote()
                        } else {
                            expandToIsland()
                        }
                    } else {
                        snapToEdge(animate = true)
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun openQuietNote() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
    }

    private fun expandToIsland() {
        val p = params ?: return
        val density = resources.displayMetrics.density
        val screenWidth = resources.displayMetrics.widthPixels

        val islandW = (156 * density).toInt()
        val islandH = (46 * density).toInt()

        viewMode = 2
        islandView?.setViewMode(2)

        p.width = islandW
        p.height = islandH

        if (p.x + islandW > screenWidth - (12 * density).toInt()) {
            p.x = screenWidth - islandW - (12 * density).toInt()
        } else if (p.x < (12 * density).toInt()) {
            p.x = (12 * density).toInt()
        }

        try {
            windowManager?.updateViewLayout(islandView, p)
        } catch (_: Exception) {}

        scheduleCollapse()
    }

    private fun snapToEdge(animate: Boolean = true) {
        val p = params ?: return
        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val density = displayMetrics.density

        val dockedW = (72 * density).toInt()
        val dockedH = (36 * density).toInt()

        val centerX = p.x + p.width / 2
        val targetMode = if (centerX < screenWidth / 2) 0 else 1

        val margin = (8 * density).toInt()
        val targetX = if (targetMode == 0) margin else (screenWidth - dockedW - margin)

        p.width = dockedW
        p.height = dockedH

        if (animate) {
            val anim = ValueAnimator.ofInt(p.x, targetX).apply {
                duration = 220
                interpolator = DecelerateInterpolator()
                addUpdateListener { va ->
                    p.x = va.animatedValue as Int
                    try {
                        windowManager?.updateViewLayout(islandView, p)
                    } catch (_: Exception) {}
                }
            }
            anim.start()
            viewMode = targetMode
            islandView?.setViewMode(targetMode)
        } else {
            p.x = targetX
            viewMode = targetMode
            islandView?.setViewMode(targetMode)
            try {
                windowManager?.updateViewLayout(islandView, p)
            } catch (_: Exception) {}
        }
    }

    private fun scheduleCollapse() {
        cancelCollapse()
        collapseRunnable = Runnable {
            if (viewMode == 2 && !isDragging && !isAppForeground) {
                snapToEdge(animate = true)
            }
        }
        handler.postDelayed(collapseRunnable!!, 3500)
    }

    private fun cancelCollapse() {
        collapseRunnable?.let { handler.removeCallbacks(it) }
    }

    private fun startPeriodicTicker() {
        timerRunnable?.let { handler.removeCallbacks(it) }
        timerRunnable = object : Runnable {
            override fun run() {
                val now = System.currentTimeMillis()
                if (endsAtMillis <= now) {
                    hideIsland()
                    stopSelf()
                    return
                }
                // Force continuous live redraw of timer and circular progress
                islandView?.postInvalidate()
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(timerRunnable!!)
    }

    private fun hideIsland() {
        cancelCollapse()
        timerRunnable?.let { handler.removeCallbacks(it) }
        if (islandView != null && windowManager != null) {
            try {
                windowManager?.removeView(islandView)
            } catch (_: Exception) {}
            islandView = null
        }
    }

    override fun onDestroy() {
        isRunning = false
        hideIsland()
        super.onDestroy()
    }

    inner class IslandCustomView(context: Context) : View(context) {
        private var endsAtMs: Long = 0
        private var totalSec: Int = 25 * 60
        private var currentPhase: String = "work"
        private var label: String = "Focus"
        private var currentMode: Int = 0 // 0 = Docked Left, 1 = Docked Right, 2 = Expanded
        private var isPressedState: Boolean = false

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }
        private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }
        private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }
        private val timePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val vectorIconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val vectorFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        private val cardRect = RectF()
        private val arcRect = RectF()
        private val tempRect = RectF()

        fun updateData(endsAt: Long, total: Int, ph: String, lbl: String) {
            endsAtMs = endsAt
            totalSec = if (total > 0) total else 25 * 60
            currentPhase = ph
            label = lbl
            postInvalidate()
        }

        fun setViewMode(mode: Int) {
            currentMode = mode
            postInvalidate()
        }

        fun setPressedState(pressed: Boolean) {
            isPressedState = pressed
            postInvalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val density = resources.displayMetrics.density
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0 || h <= 0) return

            val isBreak = currentPhase == "break"
            val accentColor = if (isBreak) Color.parseColor("#F59E0B") else Color.parseColor("#6366F1")
            val ringColor = if (isBreak) Color.parseColor("#FBBF24") else Color.parseColor("#818CF8")
            val bgColor = if (isBreak) Color.parseColor("#FA1B1713") else Color.parseColor("#FA12131F")

            // Real-time calculation based on exact current system clock
            val now = System.currentTimeMillis()
            val remainingSec = ((endsAtMs - now) / 1000).coerceAtLeast(0).toInt()
            val total = if (totalSec > 0) totalSec else 25 * 60
            val elapsedSec = (total - remainingSec).coerceAtLeast(0)
            val progress = (elapsedSec.toFloat() / total.toFloat()).coerceIn(0f, 1f)

            val min = remainingSec / 60
            val sec = remainingSec % 60
            val timeStr = String.format("%02d:%02d", min, sec)

            // 1. Sleek Floating Island Pill Background
            val cornerRadius = h / 2f
            cardRect.set(1f * density, 1f * density, w - 1f * density, h - 1f * density)

            bgPaint.color = bgColor
            canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, bgPaint)

            // 2. High-Precision Glow Border
            borderPaint.color = ringColor
            borderPaint.strokeWidth = if (isPressedState) 1.8f * density else 1.2f * density
            borderPaint.alpha = if (isPressedState) 240 else (if (currentMode == 2) 180 else 110)
            canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, borderPaint)

            if (currentMode == 2) {
                // -------------------------------------------------------------
                // EXPANDED DYNAMIC ISLAND CARD
                // -------------------------------------------------------------
                val gaugeSize = 28f * density
                val gaugeX = 20f * density
                val gaugeY = h / 2f

                val strokeW = 2.6f * density
                trackPaint.strokeWidth = strokeW
                trackPaint.color = accentColor
                trackPaint.alpha = 50

                progressPaint.strokeWidth = strokeW
                progressPaint.color = ringColor
                progressPaint.alpha = 255

                val gR = gaugeSize / 2f
                arcRect.set(gaugeX - gR, gaugeY - gR, gaugeX + gR, gaugeY + gR)
                canvas.drawArc(arcRect, -90f, 360f, false, trackPaint)
                canvas.drawArc(arcRect, -90f, progress * 360f, false, progressPaint)

                drawVectorIcon(canvas, gaugeX, gaugeY, isBreak, density, scale = 0.9f)

                titlePaint.color = ringColor
                titlePaint.textSize = 10.5f * density
                titlePaint.textAlign = Paint.Align.LEFT
                canvas.drawText(if (isBreak) "Break Time" else label, gaugeX + gR + 10f * density, gaugeY - 2f * density, titlePaint)

                timePaint.color = Color.WHITE
                timePaint.textSize = 13f * density
                timePaint.textAlign = Paint.Align.LEFT
                canvas.drawText(timeStr, gaugeX + gR + 10f * density, gaugeY + 12f * density, timePaint)

                val chevronX = w - 16f * density
                vectorIconPaint.color = ringColor
                vectorIconPaint.strokeWidth = 1.8f * density
                vectorIconPaint.alpha = 200
                canvas.drawLine(chevronX - 3f * density, gaugeY - 4f * density, chevronX + 1f * density, gaugeY, vectorIconPaint)
                canvas.drawLine(chevronX + 1f * density, gaugeY, chevronX - 3f * density, gaugeY + 4f * density, vectorIconPaint)

            } else {
                // -------------------------------------------------------------
                // DOCKED EDGE PILL (Compact & Balanced)
                // -------------------------------------------------------------
                val ringSize = 18f * density
                val ringX = 15f * density
                val ringY = h / 2f

                val strokeW = 2.2f * density
                trackPaint.strokeWidth = strokeW
                trackPaint.color = accentColor
                trackPaint.alpha = 50

                progressPaint.strokeWidth = strokeW
                progressPaint.color = ringColor
                progressPaint.alpha = 255

                val r = ringSize / 2f
                arcRect.set(ringX - r, ringY - r, ringX + r, ringY + r)
                canvas.drawArc(arcRect, -90f, 360f, false, trackPaint)
                canvas.drawArc(arcRect, -90f, progress * 360f, false, progressPaint)

                vectorFillPaint.color = ringColor
                canvas.drawCircle(ringX, ringY, 2.4f * density, vectorFillPaint)

                timePaint.color = Color.WHITE
                timePaint.textSize = 11.5f * density
                timePaint.textAlign = Paint.Align.LEFT
                canvas.drawText(timeStr, ringX + r + 6f * density, ringY + 4f * density, timePaint)
            }
        }

        private fun drawVectorIcon(canvas: Canvas, x: Float, y: Float, isBreak: Boolean, density: Float, scale: Float = 1.0f) {
            vectorIconPaint.color = if (isBreak) Color.parseColor("#FBBF24") else Color.parseColor("#818CF8")
            vectorFillPaint.color = vectorIconPaint.color

            if (isBreak) {
                vectorIconPaint.strokeWidth = 1.4f * density * scale
                val s = density * scale

                tempRect.set(x - 4.5f * s, y - 2.5f * s, x + 3.5f * s, y + 5f * s)
                canvas.drawRoundRect(tempRect, 1.4f * s, 1.4f * s, vectorIconPaint)

                tempRect.set(x + 3.5f * s, y - 0.8f * s, x + 6.8f * s, y + 3.2f * s)
                canvas.drawArc(tempRect, -90f, 180f, false, vectorIconPaint)

                canvas.drawLine(x - 2.2f * s, y - 4f * s, x - 2.2f * s, y - 6.5f * s, vectorIconPaint)
                canvas.drawLine(x + 1.2f * s, y - 4f * s, x + 1.2f * s, y - 6.5f * s, vectorIconPaint)

            } else {
                vectorIconPaint.strokeWidth = 1.4f * density * scale
                val s = density * scale

                canvas.drawCircle(x, y, 5f * s, vectorIconPaint)
                canvas.drawCircle(x, y, 2f * s, vectorFillPaint)

                val tickLen = 1.4f * s
                canvas.drawLine(x, y - 6.5f * s, x, y - 6.5f * s + tickLen, vectorIconPaint)
                canvas.drawLine(x, y + 6.5f * s, x, y + 6.5f * s - tickLen, vectorIconPaint)
                canvas.drawLine(x - 6.5f * s, y, x - 6.5f * s + tickLen, y, vectorIconPaint)
                canvas.drawLine(x + 6.5f * s, y, x + 6.5f * s - tickLen, y, vectorIconPaint)
            }
        }
    }
}
