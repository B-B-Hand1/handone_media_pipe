package dev.ohanyan.handone_media_pipe

import android.app.Activity
import android.content.Context
import android.view.View
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.platform.PlatformView

class CameraPlatformView(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val factory: CameraPlatformViewFactory,
    private val exerciseType: ExerciseType,
    private val debug: Boolean
) : PlatformView {

    private val cameraView: CameraPreviewView = CameraPreviewView(
        context,
        lifecycleOwner,
        factory.getActivity() ?: (lifecycleOwner as? Activity) ?: (context as? Activity),
        factory,
        exerciseType,
        debug
    )

    override fun getView(): View = cameraView

    override fun dispose() {
        factory.unregisterCameraView(cameraView)
    }
}

