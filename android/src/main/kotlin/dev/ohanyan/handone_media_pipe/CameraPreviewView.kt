package dev.ohanyan.handone_media_pipe

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.util.AttributeSet
import android.util.Log
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.util.concurrent.ExecutionException
import kotlin.math.acos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

private typealias HandLandmarks = List<NormalizedLandmark>

class CameraPreviewView @JvmOverloads constructor(
    context: Context,
    private val lifecycleOwner: LifecycleOwner? = null,
    private val activity: Activity? = null,
    private val factory: CameraPlatformViewFactory? = null,
    private val exerciseType: ExerciseType = ExerciseType.OPENING_AND_CLOSING_THE_FIST,
    private val debug: Boolean = false,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1001
    }

    init {
        factory?.registerCameraView(this)
    }

    private var preview: Preview? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var handLandmarker: HandLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null
    private var handResult: HandLandmarkerResult? = null
    private var poseResult: PoseLandmarkerResult? = null
    private var lastHandResult: HandLandmarkerResult? = null
    private var lastPoseResult: PoseLandmarkerResult? = null

    /** Dimensions of the image passed to MediaPipe (rotated+mirrored to match preview). Used for overlay scale/offset. */
    @Volatile
    private var inferenceImageWidth: Int = 1

    @Volatile
    private var inferenceImageHeight: Int = 1

    // Angle state (mirror iOS)
    private var indexFingerTotalAngle: Int? = null
    private var indexFingerTotalMaxAngle: Int? = null
    private var indexFingerTotalMinAngle: Int? = null
    private var middleFingerTotalAngle: Int? = null
    private var middleFingerTotalMaxAngle: Int? = null
    private var middleFingerTotalMinAngle: Int? = null
    private var ringFingerTotalAngle: Int? = null
    private var ringFingerTotalMaxAngle: Int? = null
    private var ringFingerTotalMinAngle: Int? = null
    private var pinkyTotalAngle: Int? = null
    private var pinkyTotalMaxAngle: Int? = null
    private var pinkyTotalMinAngle: Int? = null
    private var flexionAngle: Int? = null
    private var flexionMaxAngle: Int? = null
    private var extensionAngle: Int? = null
    private var extensionMaxAngle: Int? = null
    private var supinationAngle: Int? = null
    private var supinationMaxAngle: Int? = null
    private var pronationAngle: Int? = null
    private var pronationMaxAngle: Int? = null

    private val previewView: PreviewView = PreviewView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        )
        isClickable = false
        isFocusable = false
        isFocusableInTouchMode = false
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }

    private val overlayView = LandmarkOverlayView(context)
    private val infoTextView: TextView = TextView(context).apply {
        setTextColor(Color.WHITE)
        textSize = 13f
        setTypeface(android.graphics.Typeface.MONOSPACE)
        setPadding(16, 8, 16, 8)
        setBackgroundColor(Color.argb(128, 0, 0, 0))
    }

    init {
        isClickable = false
        isFocusable = false
        isFocusableInTouchMode = false
        descendantFocusability = FOCUS_BLOCK_DESCENDANTS
        setOnTouchListener { _, _ -> false }
        addView(previewView)
        addView(overlayView, FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(infoTextView, FrameLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = 440
            marginStart = 16
            marginEnd = 16
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        })
        infoTextView.visibility = if (debug) VISIBLE else GONE
        Log.d("CameraPreviewView", "exerciseType: ${exerciseType.rawValue}, debug: $debug")
        if (isEmulator()) {
            showEmulatorMessage()
        } else {
            lifecycleOwner?.let {
                post { startCamera(it) }
            } ?: Log.w("CameraPreviewView", "LifecycleOwner not provided")
        }
    }

    override fun onInterceptTouchEvent(ev: android.view.MotionEvent?): Boolean = false
    override fun onTouchEvent(event: android.view.MotionEvent?): Boolean = false

    private fun isEmulator(): Boolean =
        Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("Emulator") || Build.MODEL.contains("Android SDK built for x86")

    private fun showEmulatorMessage() {
        val textView = TextView(context).apply {
            text = "Camera not available in Emulator"
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            textSize = 16f
        }
        setBackgroundColor(Color.BLACK)
        addView(textView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    private fun startCamera(lifecycleOwner: LifecycleOwner) {
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestCameraPermission()
            return
        }
        setupLandmarkers()
        initializeCamera(lifecycleOwner)
    }

    private fun setupLandmarkers() {
        try {
            val handModelPath = getModelPath("hand_landmarker.task")
            val poseModelPath = getModelPath("pose_landmarker_heavy.task")
            if (handModelPath != null) {
                val handBaseOptions = BaseOptions.builder().setModelAssetPath(handModelPath).build()
                val handOptions =
                    HandLandmarker.HandLandmarkerOptions.builder().setBaseOptions(handBaseOptions).setRunningMode(RunningMode.LIVE_STREAM).setNumHands(2)
                        .setMinHandDetectionConfidence(0.7f).setMinHandPresenceConfidence(0.7f).setMinTrackingConfidence(0.7f)
                        .setResultListener { result, image -> onHandResult(result, image) }
                        .setErrorListener { error: RuntimeException -> Log.e("CameraPreviewView", "Hand error", error) }.build()
                handLandmarker = HandLandmarker.createFromOptions(context, handOptions)
                Log.d("CameraPreviewView", "HandLandmarker initialized")
            } else Log.e("CameraPreviewView", "hand_landmarker.task not found")
            if (poseModelPath != null) {
                val poseBaseOptions = BaseOptions.builder().setModelAssetPath(poseModelPath).build()
                val poseOptions =
                    PoseLandmarker.PoseLandmarkerOptions.builder().setBaseOptions(poseBaseOptions).setRunningMode(RunningMode.LIVE_STREAM).setNumPoses(1)
                        .setMinPoseDetectionConfidence(0.6f).setMinPosePresenceConfidence(0.6f).setMinTrackingConfidence(0.6f)
                        .setResultListener { result, image -> onPoseResult(result, image) }
                        .setErrorListener { error: RuntimeException -> Log.e("CameraPreviewView", "Pose error", error) }.build()
                poseLandmarker = PoseLandmarker.createFromOptions(context, poseOptions)
                Log.d("CameraPreviewView", "PoseLandmarker initialized")
            } else Log.e("CameraPreviewView", "pose_landmarker_heavy.task not found")
        } catch (e: Exception) {
            Log.e("CameraPreviewView", "Failed to setup landmarkers", e)
        }
    }

    private fun getModelPath(assetName: String): String? {
        return try {
            context.assets.open(assetName).use { }
            assetName
        } catch (e: Exception) {
            Log.w("CameraPreviewView", "Model not found: $assetName", e)
            null
        }
    }

    private var timestamp = 0L
    private fun onHandResult(result: HandLandmarkerResult, image: MPImage) {
        handResult = result
        lastHandResult = result
        post { overlayView.invalidate() }
        if (result.landmarks().isNotEmpty() && result.landmarks()[0].size > 20) {
            processHandLandmarks(result)
        }
    }

    private fun onPoseResult(result: PoseLandmarkerResult, image: MPImage) {
        poseResult = result
        lastPoseResult = result
        post { overlayView.invalidate() }
    }

    private fun processHandLandmarks(result: HandLandmarkerResult) {
        val firstHand = result.landmarks()[0]
        val wrist = firstHand[0]

        when (exerciseType) {
            ExerciseType.OPENING_AND_CLOSING_THE_FIST -> processOpeningAndClosingTheFist(firstHand, wrist)
            ExerciseType.WRIST_EXTENSION_AND_FLEXION -> processWristExtensionAndFlexion(firstHand, result, wrist)
            ExerciseType.FOREARM_SUPINATION_AND_PRONATION -> processForearmSupinationAndPronation(firstHand, result)
        }
        post { updateInfoText() }
    }

    private fun processOpeningAndClosingTheFist(hand: HandLandmarks, wrist: NormalizedLandmark) {
        val indexAngle = calculateFingerTotalAngle(wrist, hand[5], hand[6], hand[7], hand[8], true).toInt()
        val middleAngle = calculateFingerTotalAngle(wrist, hand[9], hand[10], hand[11], hand[12], true).toInt()
        val ringAngle = calculateFingerTotalAngle(wrist, hand[13], hand[14], hand[15], hand[16], true).toInt()
        val pinkyAngle = calculateFingerTotalAngle(wrist, hand[17], hand[18], hand[19], hand[20], true).toInt()
        indexFingerTotalAngle = indexAngle
        middleFingerTotalAngle = middleAngle
        ringFingerTotalAngle = ringAngle
        pinkyTotalAngle = pinkyAngle
        val data = mutableMapOf<String, Any>()
        if (indexAngle < 420 && middleAngle < 420 && ringAngle < 420 && pinkyAngle < 420) {
            indexFingerTotalMinAngle = min(indexFingerTotalMinAngle ?: 1000, indexAngle)
            middleFingerTotalMinAngle = min(middleFingerTotalMinAngle ?: 1000, middleAngle)
            ringFingerTotalMinAngle = min(ringFingerTotalMinAngle ?: 1000, ringAngle)
            pinkyTotalMinAngle = min(pinkyTotalMinAngle ?: 1000, pinkyAngle)
            indexFingerTotalMaxAngle?.let { data["index_extension"] = it; indexFingerTotalMaxAngle = null }
            middleFingerTotalMaxAngle?.let { data["middle_extension"] = it; middleFingerTotalMaxAngle = null }
            ringFingerTotalMaxAngle?.let { data["ring_extension"] = it; ringFingerTotalMaxAngle = null }
            pinkyTotalMaxAngle?.let { data["pinky_extension"] = it; pinkyTotalMaxAngle = null }
        } else {
            indexFingerTotalMaxAngle = max(indexFingerTotalMaxAngle ?: 0, indexAngle)
            middleFingerTotalMaxAngle = max(middleFingerTotalMaxAngle ?: 0, middleAngle)
            ringFingerTotalMaxAngle = max(ringFingerTotalMaxAngle ?: 0, ringAngle)
            pinkyTotalMaxAngle = max(pinkyTotalMaxAngle ?: 0, pinkyAngle)
            indexFingerTotalMinAngle?.let { data["index_flexion"] = it; indexFingerTotalMinAngle = null }
            middleFingerTotalMinAngle?.let { data["middle_flexion"] = it; middleFingerTotalMinAngle = null }
            ringFingerTotalMinAngle?.let { data["ring_flexion"] = it; ringFingerTotalMinAngle = null }
            pinkyTotalMinAngle?.let { data["pinky_flexion"] = it; pinkyTotalMinAngle = null }
        }
        if (data.isNotEmpty()) sendData(data)
    }

    private fun processWristExtensionAndFlexion(hand: HandLandmarks, result: HandLandmarkerResult, wrist: NormalizedLandmark) {
        var elbow: NormalizedLandmark? = null
        var handedness = result.handednesses().getOrNull(0)?.getOrNull(0)?.categoryName() ?: "Right"
        val poseLandmarks = poseResult?.landmarks()?.getOrNull(0)
        if (!poseLandmarks.isNullOrEmpty() && poseLandmarks.size > 14) {
            val leftVis = poseLandmarks[13].visibility().orElse(0f)
            val rightVis = poseLandmarks[14].visibility().orElse(0f)
            if ((handedness == "Left" && leftVis < 0.2f) || (handedness == "Right" && rightVis < 0.2f)) handedness = "Right"
            else elbow = if (handedness == "Left") poseLandmarks[13] else poseLandmarks[14]
        }
        if (elbow != null) {
            val pinky = hand[17]
            val angle = kotlin.math.abs(180 - calculateXYAngle(pinky, wrist, elbow).toInt())
            val xApogee = wrist.x() - (wrist.y() - pinky.y()) * ((wrist.x() - elbow.x()) / (wrist.y() - elbow.y()).coerceAtLeast(1e-6f))
            if (angle <= 90) {
                val data = mutableMapOf<String, Any>()
                if (pinky.x() < xApogee && handedness == "Left" || pinky.x() > xApogee && handedness == "Right") {
                    flexionAngle = angle
                    flexionMaxAngle = max(flexionMaxAngle ?: 0, angle)
                    extensionAngle = null
                    extensionMaxAngle?.let { if (it > 9) data["extension"] = it; extensionMaxAngle = null }
                } else {
                    flexionAngle = null
                    flexionMaxAngle?.let { if (it > 9) data["flexion"] = it; flexionMaxAngle = null }
                    extensionAngle = angle
                    extensionMaxAngle = max(extensionMaxAngle ?: 0, angle)
                }
                if (data.isNotEmpty()) sendData(data)
            }
        }
    }

    private fun processForearmSupinationAndPronation(hand: HandLandmarks, result: HandLandmarkerResult) {
        val pinkyMcp = hand[17]
        val indexFingerMcp = hand[5]
        var angle = calculate3DAngle(pinkyMcp, indexFingerMcp, NormalizedLandmark.create(indexFingerMcp.x(), indexFingerMcp.y(), 0f)).toInt()
        val data = mutableMapOf<String, Any>()
        var handedness = result.handednesses().getOrNull(0)?.getOrNull(0)?.categoryName() ?: "Right"
        if (pinkyMcp.x() < indexFingerMcp.x() && handedness == "Left" || pinkyMcp.x() > indexFingerMcp.x() && handedness == "Right") {
            if (angle > 92 && (supinationMaxAngle ?: 0) < 88) {
                angle = 180 - angle
            }
            if (angle > 91) {
                return
            }
            supinationAngle = angle
            supinationMaxAngle = max(supinationMaxAngle ?: 0, angle)
            pronationAngle = null
            pronationMaxAngle?.let { if (it > 9) data["pronation"] = it; pronationMaxAngle = null }
        } else {
            if (angle > 92 && (pronationMaxAngle ?: 0) < 88) {
                angle = 180 - angle
            }
            if (angle > 91) {
                return
            }
            supinationAngle = null
            supinationMaxAngle?.let { if (it > 9) data["supination"] = it; supinationMaxAngle = null }
            pronationAngle = angle
            pronationMaxAngle = max(pronationMaxAngle ?: 0, angle)
        }
        if (data.isNotEmpty()) sendData(data)
    }

    private fun sendData(data: Map<String, Any>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                HandoneMediaPipePlugin.eventSink?.success(data)
            } catch (e: Exception) {
                Log.e("CameraPreviewView", "sendData error", e)
            }
        }
    }

    private fun updateInfoText() {
        val typeTitle = when (exerciseType) {
            ExerciseType.OPENING_AND_CLOSING_THE_FIST -> "Opening and closing the fist"
            ExerciseType.WRIST_EXTENSION_AND_FLEXION -> "Wrist extension and flexion"
            ExerciseType.FOREARM_SUPINATION_AND_PRONATION -> "Forearm supination and pronation"
        }
        val rows = when (exerciseType) {
            ExerciseType.OPENING_AND_CLOSING_THE_FIST -> listOf("Index: ${indexFingerTotalAngle?.let { "$it°" } ?: "-"}, min: ${indexFingerTotalMinAngle?.let { "$it°" } ?: "-"}, max: ${indexFingerTotalMaxAngle?.let { "$it°" } ?: "-"}",
                "Middle: ${middleFingerTotalAngle?.let { "$it°" } ?: "-"}, min: ${middleFingerTotalMinAngle?.let { "$it°" } ?: "-"}, max: ${middleFingerTotalMaxAngle?.let { "$it°" } ?: "-"}",
                "Ring: ${ringFingerTotalAngle?.let { "$it°" } ?: "-"}, min: ${ringFingerTotalMinAngle?.let { "$it°" } ?: "-"}, max: ${ringFingerTotalMaxAngle?.let { "$it°" } ?: "-"}",
                "Pinky: ${pinkyTotalAngle?.let { "$it°" } ?: "-"}, min: ${pinkyTotalMinAngle?.let { "$it°" } ?: "-"}, max: ${pinkyTotalMaxAngle?.let { "$it°" } ?: "-"}")

            ExerciseType.WRIST_EXTENSION_AND_FLEXION -> listOf("Flexion: ${flexionAngle?.let { "$it°" } ?: "-"}, max: ${flexionMaxAngle?.let { "$it°" } ?: "-"}",
                "Extension: ${extensionAngle?.let { "$it°" } ?: "-"}, max: ${extensionMaxAngle?.let { "$it°" } ?: "-"}")

            ExerciseType.FOREARM_SUPINATION_AND_PRONATION -> listOf("Supination: ${supinationAngle?.let { "$it°" } ?: "-"}, max: ${supinationMaxAngle?.let { "$it°" } ?: "-"}",
                "Pronation: ${pronationAngle?.let { "$it°" } ?: "-"}, max: ${pronationMaxAngle?.let { "$it°" } ?: "-"}")
        }
        infoTextView.text = "Type: $typeTitle\n${rows.joinToString("\n")}"
    }

    private fun calculateYZAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark): Double {
        val v1x = a.y() - b.y();
        val v1z = a.z() - b.z()
        val v2x = c.y() - b.y();
        val v2z = c.z() - b.z()
        val dot = v1x * v2x + v1z * v2z
        val m1 = sqrt((v1x * v1x + v1z * v1z).toDouble())
        val m2 = sqrt((v2x * v2x + v2z * v2z).toDouble())
        if (m1 == 0.0 || m2 == 0.0) return 0.0
        val cosT = (dot / (m1 * m2)).toDouble().coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosT))
    }

    private fun calculateXYAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark): Double {
        val v1x = a.x() - b.x();
        val v1y = a.y() - b.y()
        val v2x = c.x() - b.x();
        val v2y = c.y() - b.y()
        val dot = v1x * v2x + v1y * v2y
        val m1 = sqrt((v1x * v1x + v1y * v1y).toDouble())
        val m2 = sqrt((v2x * v2x + v2y * v2y).toDouble())
        if (m1 == 0.0 || m2 == 0.0) return 0.0
        val cosT = (dot / (m1 * m2)).toDouble().coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosT))
    }

    private fun calculate3DAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark): Double {
        val v1x = a.x() - b.x();
        val v1y = a.y() - b.y();
        val v1z = a.z() - b.z()
        val v2x = c.x() - b.x();
        val v2y = c.y() - b.y();
        val v2z = c.z() - b.z()
        val dot = v1x * v2x + v1y * v2y + v1z * v2z
        val m1 = sqrt((v1x * v1x + v1y * v1y + v1z * v1z).toDouble())
        val m2 = sqrt((v2x * v2x + v2y * v2y + v2z * v2z).toDouble())
        if (m1 == 0.0 || m2 == 0.0) return 0.0
        val cosT = (dot / (m1 * m2)).toDouble().coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosT))
    }

    private fun calculateFingerTotalAngle(
        wrist: NormalizedLandmark, mcp: NormalizedLandmark, pip: NormalizedLandmark, dip: NormalizedLandmark, tip: NormalizedLandmark, correct: Boolean = false
    ): Double {
        var mcpAngle = calculate3DAngle(wrist, mcp, pip)
        if (correct && mcpAngle > 90 && mcpAngle < 180) {
            mcpAngle = mcpAngle * (mcpAngle / 250 + 0.34)
        }
        var pipAngle = calculate3DAngle(mcp, pip, dip)
        if (correct && pipAngle > 90 && pipAngle < 180) {
            pipAngle = pipAngle * (pipAngle / 250 + 0.34)
        }
        var dipAngle = calculate3DAngle(pip, dip, tip)
        if (correct && dipAngle > 90 && dipAngle < 180) {
            dipAngle = dipAngle * (dipAngle / 250 + 0.34)
        }
        return max(min(mcpAngle, 185.0), 85.0) + max(min(pipAngle, 185.0), 85.0) + max(min(dipAngle, 185.0), 85.0);
    }

    private fun requestCameraPermission() {
        val act = activity ?: factory?.getActivity() ?: (lifecycleOwner as? Activity) ?: (context as? Activity)
        if (act == null) {
            Log.e("CameraPreviewView", "Activity is null")
            showErrorMessage("Cannot request camera permission")
            return
        }
        ActivityCompat.requestPermissions(act, arrayOf(android.Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            lifecycleOwner?.let { initializeCamera(it) }
        } else {
            Log.e("CameraPreviewView", "Camera permission denied")
            showErrorMessage("Camera permission denied")
        }
    }

    private fun showErrorMessage(message: String) {
        val tv = TextView(context).apply {
            text = message
            setTextColor(Color.RED)
            gravity = Gravity.CENTER
            textSize = 14f
        }
        setBackgroundColor(Color.BLACK)
        addView(tv, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    private fun initializeCamera(lifecycleOwner: LifecycleOwner) {
        ProcessCameraProvider.getInstance(context).addListener({
            try {
                cameraProvider = ProcessCameraProvider.getInstance(context).get()
                val cameraSelector = CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_FRONT).build()
                previewView.post {
                    preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                    val imageAnalysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888).build().also {
                            it.setAnalyzer(ContextCompat.getMainExecutor(context)) { imageProxy ->
                                processImage(imageProxy)
                            }
                        }
                    try {
                        cameraProvider?.unbindAll()
                        cameraProvider?.bindToLifecycle(lifecycleOwner, cameraSelector, preview, imageAnalysis)
                    } catch (e: Exception) {
                        Log.e("CameraPreviewView", "Failed to bind camera", e)
                        showErrorMessage("Failed to start camera: ${e.message}")
                    }
                }
            } catch (e: ExecutionException) {
                Log.e("CameraPreviewView", "Camera provider error", e)
                showErrorMessage("Camera provider error")
            } catch (e: InterruptedException) {
                Log.e("CameraPreviewView", "Camera interrupted", e)
                showErrorMessage("Camera interrupted")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun processImage(imageProxy: ImageProxy) {
        if (handLandmarker == null || poseLandmarker == null) {
            imageProxy.close()
            return
        }
        val rotatedBitmap = imageProxy.toRotatedBitmapForInference()
        if (rotatedBitmap == null) {
            imageProxy.close()
            return
        }
        inferenceImageWidth = rotatedBitmap.width
        inferenceImageHeight = rotatedBitmap.height
        timestamp += 1
        try {
            val mpImage = BitmapImageBuilder(rotatedBitmap).build()
            handLandmarker?.detectAsync(mpImage, timestamp)
            poseLandmarker?.detectAsync(mpImage, timestamp)
        } catch (e: Exception) {
            Log.e("CameraPreviewView", "Detection error", e)
        }
        imageProxy.close()
    }

    /**
     * Converts ImageProxy to a bitmap rotated and mirrored to match the preview (MediaPipe official approach).
     * Landmarks will be in the same coordinate system as this image, so overlay can use simple scale+offset.
     */
    private fun ImageProxy.toRotatedBitmapForInference(): android.graphics.Bitmap? {
        return try {
            val sourceBitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
            sourceBitmap.copyPixelsFromBuffer(planes[0].buffer)
            val rotationMatrix = Matrix().apply {
                postRotate(imageInfo.rotationDegrees.toFloat())
            }
            val rotatedBitmap = android.graphics.Bitmap.createBitmap(
                sourceBitmap, 0, 0, sourceBitmap.width, sourceBitmap.height, rotationMatrix, true
            )
            if (rotatedBitmap != sourceBitmap) sourceBitmap.recycle()
            val isFrontCamera = true
            val result = if (isFrontCamera) {
                val flipMatrix = Matrix().apply {
                    postScale(-1f, 1f, rotatedBitmap.width / 2f, rotatedBitmap.height / 2f)
                }
                android.graphics.Bitmap.createBitmap(
                    rotatedBitmap, 0, 0, rotatedBitmap.width, rotatedBitmap.height, flipMatrix, true
                )
            } else rotatedBitmap
            if (result != rotatedBitmap) rotatedBitmap.recycle()
            result
        } catch (e: Exception) {
            Log.e("CameraPreviewView", "toRotatedBitmapForInference failed", e)
            null
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        try {
            handLandmarker?.close()
            poseLandmarker?.close()
            cameraProvider?.unbindAll()
        } catch (e: Exception) {
            Log.e("CameraPreviewView", "Error cleanup", e)
        }
    }

    /**
     * Overlay that draws hand and pose landmarks the same way (MediaPipe official approach):
     * Landmarks are in normalized coords (0–1) of the inference image (rotated+mirrored to match preview).
     * Scale and offset match PreviewView FILL mode so the skeleton sits on the real hand/body.
     */
    inner class LandmarkOverlayView(context: Context) : android.view.View(context) {
        private val connectionPaint = Paint().apply {
            color = Color.GREEN
            style = Paint.Style.STROKE
            strokeWidth = 4f
            isAntiAlias = true
        }
        private val pointPaint = Paint().apply {
            color = Color.GREEN
            style = Paint.Style.FILL
            isAntiAlias = true
        }

        /** MediaPipe hand connections (21 landmarks): thumb, index, middle, ring, pinky, palm. */
        private val handConnections = listOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 4, 0 to 5, 5 to 6, 6 to 7, 7 to 8,
            0 to 9, 9 to 10, 10 to 11, 11 to 12, 0 to 13, 13 to 14, 14 to 15, 15 to 16,
            0 to 17, 17 to 18, 18 to 19, 19 to 20, 5 to 9, 9 to 13, 13 to 17
        )

        /** MediaPipe pose connections (33 landmarks): face, arms, torso, legs. */
        private val poseConnections = listOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 7, 0 to 4, 4 to 5, 5 to 6, 6 to 8, 9 to 10,
            11 to 12, 11 to 13, 13 to 15, 15 to 17, 15 to 19, 15 to 21, 17 to 19,
            12 to 14, 14 to 16, 16 to 18, 16 to 20, 16 to 22, 18 to 20,
            11 to 23, 12 to 24, 23 to 24,
            23 to 25, 25 to 27, 27 to 29, 27 to 31,
            24 to 26, 26 to 28, 28 to 30, 28 to 32
        )

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val imageW = inferenceImageWidth.coerceAtLeast(1)
            val imageH = inferenceImageHeight.coerceAtLeast(1)
            val viewW = width.toFloat()
            val viewH = height.toFloat()
            val scaleFactor = max(viewW / imageW, viewH / imageH)
            val offsetX = (viewW - imageW * scaleFactor) / 2f
            val offsetY = (viewH - imageH * scaleFactor) / 2f
//            drawLandmarks(canvas, lastPoseResult?.landmarks(), poseConnections, 33, imageW, imageH, scaleFactor, offsetX, offsetY)
//            drawLandmarks(canvas, lastHandResult?.landmarks(), handConnections, 21, imageW, imageH, scaleFactor, offsetX, offsetY)
        }

        /** Draws connections and points for hand or pose landmarks (same style and logic). */
        private fun drawLandmarks(
            canvas: Canvas,
            landmarkLists: List<HandLandmarks>?,
            connections: List<Pair<Int, Int>>,
            minSize: Int,
            imageW: Int,
            imageH: Int,
            scaleFactor: Float,
            offsetX: Float,
            offsetY: Float
        ) {
            if (landmarkLists == null) return
            val w = imageW.toFloat()
            val h = imageH.toFloat()
            for (landmarks in landmarkLists) {
                if (landmarks.size < minSize) continue
                val path = Path()
                for ((startIdx, endIdx) in connections) {
                    if (startIdx >= landmarks.size || endIdx >= landmarks.size) continue
                    val start = landmarks[startIdx]
                    val end = landmarks[endIdx]
                    val sx = offsetX + start.x() * w * scaleFactor
                    val sy = offsetY + start.y() * h * scaleFactor
                    val ex = offsetX + end.x() * w * scaleFactor
                    val ey = offsetY + end.y() * h * scaleFactor
                    path.moveTo(sx, sy)
                    path.lineTo(ex, ey)
                }
                canvas.drawPath(path, connectionPaint)
                for (lm in landmarks) {
                    val px = offsetX + lm.x() * w * scaleFactor
                    val py = offsetY + lm.y() * h * scaleFactor
                    canvas.drawCircle(px, py, 6f, pointPaint)
                }
            }
        }
    }
}
