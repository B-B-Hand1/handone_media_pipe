import Flutter
import UIKit

class CameraPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }
    
    // CRITICAL: This method must be implemented for creationParams to be received
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        print("CameraPlatformViewFactory: Received arguments type: \(type(of: args))")
        print("CameraPlatformViewFactory: Received arguments: \(String(describing: args))")
        
        // exerciseType must be provided from Dart
        guard let args = args else {
            fatalError("exerciseType parameter is required. Arguments are nil. Make sure creationParams are passed to UiKitView.")
        }
        
        // Try to cast to dictionary
        guard let argsDict = args as? [String: Any] else {
            print("CameraPlatformViewFactory: Arguments is not a dictionary. Type: \(type(of: args))")
            fatalError("exerciseType parameter is required. Arguments must be a dictionary. Received: \(String(describing: args))")
        }
        
        guard let exerciseTypeString = argsDict["exerciseType"] as? String else {
            print("CameraPlatformViewFactory: exerciseType key not found in dictionary. Keys: \(argsDict.keys)")
            fatalError("exerciseType parameter is required. Key 'exerciseType' not found in arguments. Available keys: \(argsDict.keys)")
        }
        
        guard let exerciseType = ExerciseType(rawValue: exerciseTypeString) else {
            fatalError("exerciseType parameter has invalid value: '\(exerciseTypeString)'. Valid values are: openingAndClosingTheFist, wristExtensionAndFlexion, forearmSupinationAndPronation")
        }
        
        // Parse debug parameter (defaults to false if not provided)
        let debug = argsDict["debug"] as? Bool ?? false
        
        print("CameraPlatformViewFactory: Successfully parsed exerciseType from arguments: \(exerciseTypeString)")
        print("CameraPlatformViewFactory: Debug mode: \(debug)")
        print("CameraPlatformViewFactory: Creating CameraPlatformView with exerciseType: \(exerciseType.rawValue)")
        return CameraPlatformView(frame: frame, exerciseType: exerciseType, debug: debug)
    }
}
