package ir.tihe.capture_guard

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.function.Consumer

/**
 * Android half of capture_guard.
 *
 * Blocking is FLAG_SECURE: screenshots and recordings of the window come out black, and the
 * window is blanked in Recents. Detection reports facts for the Dart policy (ADR-0011):
 * Android 15's screen-recording callback, Android 14's screenshot callback, and extra displays
 * (casting, mirroring apps).
 */
class CaptureGuardPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    private var blocking = false
    private var osRecording = false
    private var recordingCallback: Consumer<Int>? = null
    private var screenshotCallback: Activity.ScreenCaptureCallback? = null

    private val displayListener =
        object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) = pushFacts()

            override fun onDisplayRemoved(displayId: Int) = pushFacts()

            override fun onDisplayChanged(displayId: Int) = Unit
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "tihe/capture_guard")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "tihe/capture_guard/events")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "enableBlocking" -> {
                blocking = true
                applyFlag()
                val active = activity != null
                result.success(
                    mapOf(
                        "active" to active,
                        "mechanism" to if (active) "flag_secure" else "none",
                        "failed" to !active,
                    ),
                )
            }
            "disableBlocking" -> {
                blocking = false
                applyFlag()
                result.success(null)
            }
            "readFacts" -> result.success(facts())
            "runningProcesses" -> result.success(emptyList<String>())
            else -> result.notImplemented()
        }
    }

    private fun applyFlag() {
        val window = activity?.window ?: return
        main.post {
            if (blocking) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    /** Any display beyond the built-in one: casting, Miracast, or a mirroring app's virtual display. */
    private fun extraDisplays(): Boolean {
        val manager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return manager.displays.any { it.displayId != Display.DEFAULT_DISPLAY }
    }

    private fun facts(): Map<String, Any> =
        mapOf(
            "osRecording" to osRecording,
            "externalDisplay" to extraDisplays(),
            "remoteSession" to false,
        )

    private fun pushFacts() {
        main.post { sink?.success(facts()) }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        sink = events
        val manager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        manager.registerDisplayListener(displayListener, main)
        registerActivityCallbacks()
        pushFacts()
    }

    override fun onCancel(arguments: Any?) {
        val manager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        manager.unregisterDisplayListener(displayListener)
        unregisterActivityCallbacks()
        sink = null
    }

    private fun registerActivityCallbacks() {
        val activity = activity ?: return
        if (sink == null) return
        if (Build.VERSION.SDK_INT >= 35 && recordingCallback == null) {
            val callback =
                Consumer<Int> { state ->
                    osRecording = state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
                    pushFacts()
                }
            val initial = activity.windowManager.addScreenRecordingCallback(activity.mainExecutor, callback)
            osRecording = initial == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            recordingCallback = callback
        }
        if (Build.VERSION.SDK_INT >= 34 && screenshotCallback == null) {
            val callback = Activity.ScreenCaptureCallback { main.post { sink?.success(mapOf("event" to "screenshot")) } }
            activity.registerScreenCaptureCallback(activity.mainExecutor, callback)
            screenshotCallback = callback
        }
    }

    private fun unregisterActivityCallbacks() {
        val activity = activity
        if (activity != null) {
            if (Build.VERSION.SDK_INT >= 35) {
                recordingCallback?.let { activity.windowManager.removeScreenRecordingCallback(it) }
            }
            if (Build.VERSION.SDK_INT >= 34) {
                screenshotCallback?.let { activity.unregisterScreenCaptureCallback(it) }
            }
        }
        recordingCallback = null
        screenshotCallback = null
        osRecording = false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        applyFlag()
        registerActivityCallbacks()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterActivityCallbacks()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        unregisterActivityCallbacks()
        activity = null
    }
}
