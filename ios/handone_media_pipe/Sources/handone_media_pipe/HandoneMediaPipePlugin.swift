import Flutter
import UIKit

public class HandoneMediaPipePlugin: NSObject, FlutterPlugin {
    private static var eventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "handone_media_pipe",
            binaryMessenger: registrar.messenger()
        )
        let instance = HandoneMediaPipePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Setup EventChannel for dataReceived
        let eventChannel = FlutterEventChannel(
            name: "handone_media_pipe/dataReceived",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(DataReceivedStreamHandler())

        let factory = CameraPlatformViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "camera_preview")
    }
    
    static func sendData(_ data: [String: Any]) {
        eventSink?(data)
    }
    
    static func setEventSink(_ sink: FlutterEventSink?) {
        eventSink = sink
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

class DataReceivedStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        HandoneMediaPipePlugin.setEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        HandoneMediaPipePlugin.setEventSink(nil)
        return nil
    }
}
