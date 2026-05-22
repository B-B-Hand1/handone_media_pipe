import Flutter
import UIKit

class CameraPlatformView: NSObject, FlutterPlatformView {
    private let cameraView: CameraPreviewView

    init(frame: CGRect, exerciseType: ExerciseType, debug: Bool = false) {
        self.cameraView = CameraPreviewView(frame: frame, exerciseType: exerciseType, debug: debug)
        super.init()
    }

    func view() -> UIView {
        return cameraView
    }
}
