import UIKit
import AVFoundation
import MediaPipeTasksVision

enum ExerciseType: String {
    case openingAndClosingTheFist = "openingAndClosingTheFist"
    case wristExtensionAndFlexion = "wristExtensionAndFlexion"
    case forearmSupinationAndPronation = "forearmSupinationAndPronation"
}

class CameraPreviewView: UIView {

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let overlayLayer = CAShapeLayer()
    private let videoOutputQueue = DispatchQueue(label: "VideoOutputQueue")
    private let exerciseType: ExerciseType
    private let debug: Bool
    private let exerciseTypeTextLayer: CATextLayer
    private let informationLayer: CALayer

    private var indexFingerTotalAngle: Int?
    private var indexFingerTotalMaxAngle: Int?
    private var indexFingerTotalMinAngle: Int?
    private var middleFingerTotalAngle: Int?
    private var middleFingerTotalMaxAngle: Int?
    private var middleFingerTotalMinAngle: Int?
    private var ringFingerTotalAngle: Int?
    private var ringFingerTotalMaxAngle: Int?
    private var ringFingerTotalMinAngle: Int?
    private var pinkyTotalAngle: Int?
    private var pinkyTotalMaxAngle: Int?
    private var pinkyTotalMinAngle: Int?
    private var flexionAngle: Int?
    private var flexionMaxAngle: Int?
    private var extensionAngle: Int?
    private var extensionMaxAngle: Int?
    private var supinationAngle: Int?
    private var supinationMaxAngle: Int?
    private var pronationAngle: Int?
    private var pronationMaxAngle: Int?

    /// Row labels for the information layer based on exercise type.
    private var informationRows: [String] {
        switch exerciseType {
        case .openingAndClosingTheFist:
            return [
                "Index: \(indexFingerTotalAngle.map { "\($0)°" } ?? "-"), min: \(indexFingerTotalMinAngle.map { "\($0)°" } ?? "-"), max: \(indexFingerTotalMaxAngle.map { "\($0)°" } ?? "-")",
                "Middle: \(middleFingerTotalAngle.map { "\($0)°" } ?? "-"), min: \(middleFingerTotalMinAngle.map { "\($0)°" } ?? "-"), max: \(middleFingerTotalMaxAngle.map { "\($0)°" } ?? "-")",
                "Ring: \(ringFingerTotalAngle.map { "\($0)°" } ?? "-"), min: \(ringFingerTotalMinAngle.map { "\($0)°" } ?? "-"), max: \(ringFingerTotalMaxAngle.map { "\($0)°" } ?? "-")",
                "Pinky: \(pinkyTotalAngle.map { "\($0)°" } ?? "-"), min: \(pinkyTotalMinAngle.map { "\($0)°" } ?? "-"), max: \(pinkyTotalMaxAngle.map { "\($0)°" } ?? "-")"
            ]
        case .wristExtensionAndFlexion:
            return [
                "Flexion: \(flexionAngle.map { "\($0)°" } ?? "-"), max: \(flexionMaxAngle.map { "\($0)°" } ?? "-")",
                "Extension: \(extensionAngle.map { "\($0)°" } ?? "-"), max: \(extensionMaxAngle.map { "\($0)°" } ?? "-")"
            ]
        case .forearmSupinationAndPronation:
            return [
                "Supination: \(supinationAngle.map { "\($0)°" } ?? "-"), max: \(supinationMaxAngle.map { "\($0)°" } ?? "-")",
                "Pronation: \(pronationAngle.map { "\($0)°" } ?? "-"), max: \(pronationMaxAngle.map { "\($0)°" } ?? "-")"
            ]
        }
    }

    /// Full text for the information layer: Type line + exercise-specific rows.
    private var informationText: String {
        let typeTitle: String
        switch exerciseType {
        case .openingAndClosingTheFist:
            typeTitle = "Opening and closing the fist"
        case .wristExtensionAndFlexion:
            typeTitle = "Wrist extension and flexion"
        case .forearmSupinationAndPronation:
            typeTitle = "Forearm supination and pronation"
        }
        let typeLine = "Type: \(typeTitle)"
        let rows = informationRows.joined(separator: "\n")
        return "\(typeLine)\n\(rows)"
    }

    init(frame: CGRect, exerciseType: ExerciseType, debug: Bool = false) {
        self.exerciseType = exerciseType
        self.debug = debug

        // Create background layer for information display
        let backgroundLayer = CALayer()
        backgroundLayer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
        backgroundLayer.cornerRadius = 8
        self.informationLayer = backgroundLayer

        // Create text layer for information display
        let textLayer = CATextLayer()
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.fontSize = 13
        textLayer.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textLayer.alignmentMode = .left
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.backgroundColor = UIColor.clear.cgColor
        textLayer.isWrapped = true
        self.exerciseTypeTextLayer = textLayer

        super.init(frame: frame)

        // Set text after init so informationText is available
        exerciseTypeTextLayer.string = informationText

        print("ExerciseType parameter value: \(exerciseType.rawValue)")
        setupHolisticLandmarker()
        setupCamera()
    }

    required init?(coder: NSCoder) {
        // This initializer is required by UIKit but won't be used in practice
        // Since exerciseType must come from Dart, we can't initialize without it
        fatalError("init(coder:) has not been implemented - exerciseType must be provided from Dart")
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Model Loading Helper

    private func findModelFile(name: String, type: String = "task") -> String? {
        #if SWIFT_PACKAGE
        if let path = Bundle.module.path(forResource: name, ofType: type) {
            print("Found \(name) model in SPM module bundle")
            return path
        }
        #endif

        // Try resource bundle first (created by resource_bundles in podspec)
        if let resourceBundlePath = Bundle.main.path(forResource: "handone_media_pipe", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath),
           let path = resourceBundle.path(forResource: name, ofType: type) {
            print("Found \(name) model in resource bundle: \(resourceBundlePath)")
            return path
        }

        // Try main bundle
        if let path = Bundle.main.path(forResource: name, ofType: type) {
            print("Found \(name) model in main bundle")
            return path
        }

        // Try plugin bundle
        let pluginBundle = Bundle(for: CameraPreviewView.self)
        if let path = pluginBundle.path(forResource: name, ofType: type) {
            print("Found \(name) model in plugin bundle: \(pluginBundle.bundleIdentifier ?? "unknown")")
            return path
        }

        // Try finding in all bundles
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: name, ofType: type) {
                print("Found \(name) model in bundle: \(bundle.bundleIdentifier ?? bundle.bundlePath)")
                return path
            }
        }

        return nil
    }

    // MARK: - Holistic Detection Setup (using combined Hand + Pose)

    private func setupHolisticLandmarker() {
        // Since HolisticLandmarker may not be available, we'll use a combined approach
        // with HandLandmarker and PoseLandmarker working together
        setupHandLandmarker()
        setupPoseLandmarker()
    }

    private var handLandmarker: HandLandmarker?
    private var poseLandmarker: PoseLandmarker?
    private var handResult: HandLandmarkerResult?
    private var poseResult: PoseLandmarkerResult?

    private func setupHandLandmarker() {
        guard let modelPath = findModelFile(name: "hand_landmarker", type: "task") else {
            print("Model file hand_landmarker.task not found in any bundle")
            return
        }

        print("Using hand model at path: \(modelPath)")

        var options = HandLandmarkerOptions()
        configureHandLandmarkerOptions(&options, modelPath: modelPath)

        do {
            handLandmarker = try HandLandmarker(options: options)
        } catch {
            print("Failed to initialize HandLandmarker:", error)
        }
    }

    private func setupPoseLandmarker() {
        guard let modelPath = findModelFile(name: "pose_landmarker_heavy", type: "task") else {
            print("Model file pose_landmarker_heavy.task not found in any bundle")
            return
        }

        print("Using pose model at path: \(modelPath)")

        var options = PoseLandmarkerOptions()
        configurePoseLandmarkerOptions(&options, modelPath: modelPath)

        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
            print("Failed to initialize PoseLandmarker:", error)
        }
    }

    private func configureHandLandmarkerOptions(_ options: inout HandLandmarkerOptions, modelPath: String) {
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numHands = 2
        options.minHandDetectionConfidence = 0.7
        options.minHandPresenceConfidence = 0.7
        options.minTrackingConfidence = 0.7
        options.handLandmarkerLiveStreamDelegate = self
    }

    private func configurePoseLandmarkerOptions(_ options: inout PoseLandmarkerOptions, modelPath: String) {
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.6
        options.minPosePresenceConfidence = 0.6
        options.minTrackingConfidence = 0.6
        options.poseLandmarkerLiveStreamDelegate = self
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        if isSimulator {
            showSimulatorMessage()
            print("Camera not available in Simulator")
            return
        }

        captureSession.sessionPreset = .high

        let cameraTypes: [AVCaptureDevice.DeviceType] = [.builtInTrueDepthCamera, .builtInWideAngleCamera]

        var camera: AVCaptureDevice? = nil

        for type in cameraTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: .front) {
                camera = device
                break
            }
        }

        guard let selectedCamera = camera,
              let input = try? AVCaptureDeviceInput(device: selectedCamera)
        else {
            print("No camera available")
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Setup video output for frame processing
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Set video connection orientation for front camera
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        // Setup preview layer
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        self.layer.addSublayer(layer)
        previewLayer = layer

        // Setup overlay layer for drawing landmarks (on top of preview)
        overlayLayer.frame = bounds
        overlayLayer.strokeColor = UIColor.green.cgColor
        overlayLayer.fillColor = UIColor.green.cgColor
        overlayLayer.lineWidth = 2.0
        overlayLayer.zPosition = 1.0 // Ensure it's above the preview layer
        self.layer.addSublayer(overlayLayer)

        // Setup information layer (on top of everything)
        setupInformationLayer()

        captureSession.startRunning()
    }

    private func setupInformationLayer() {
        updateInformationLayerLayout()
        informationLayer.zPosition = 999
        informationLayer.isHidden = !debug
        self.layer.addSublayer(informationLayer)
        informationLayer.addSublayer(exerciseTypeTextLayer)

        let textString = exerciseTypeTextLayer.string as? String ?? ""
        print("ExerciseType text layer added. Background frame: \(informationLayer.frame), Text frame: \(exerciseTypeTextLayer.frame), Text: \(textString), Debug: \(debug)")
    }

    private func updateInformationLayerLayout() {
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 8
        let labelY: CGFloat = 166

        // Background layer: horizontal margin 16 on each side
        let backgroundWidth: CGFloat = bounds.width - 32
        let backgroundX: CGFloat = 16

        // Text area width inside the background
        let textWidth: CGFloat = backgroundWidth - (horizontalPadding * 2)
        let textX: CGFloat = horizontalPadding

        // Measure height for full information text
        let font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let text = informationText
        let textHeight = text.boundingRect(
            with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height.rounded(.up)

        // Background height = text + vertical padding
        let labelHeight = textHeight + (verticalPadding * 2)

        // Update background layer
        informationLayer.frame = CGRect(x: backgroundX, y: labelY, width: backgroundWidth, height: labelHeight)
        informationLayer.zPosition = 999

        // Text layer: padding inside the background
        exerciseTypeTextLayer.frame = CGRect(
            x: textX,
            y: verticalPadding,
            width: textWidth,
            height: textHeight
        )
        exerciseTypeTextLayer.zPosition = 1000
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        overlayLayer.frame = bounds
        updateInformationLayerLayout()
    }

    deinit {
        captureSession.stopRunning()
    }

    private func showSimulatorMessage() {
        backgroundColor = .black
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.frame = bounds
        label.numberOfLines = 0
        label.text = "Camera not available in Simulator"
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
                                        label.centerXAnchor.constraint(equalTo: centerXAnchor),
                                        label.centerYAnchor.constraint(equalTo: centerYAnchor),
                                        label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
                                        label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
                                    ])
    }

    // MARK: - Geometry Helpers

    /// Calculates the angle (in degrees) at point B formed by points A, B, and C.
    /// Each point is a NormalizedLandmark with x and z coordinates (y is ignored).
    private func calculateXZAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark) -> Double {
        let v1 = (x: a.x - b.x, z: a.z - b.z)
        let v2 = (x: c.x - b.x, z: c.z - b.z)

        let dotProduct = Double(v1.x * v2.x + v1.z * v2.z)

        let mag1 = Double(sqrt(v1.x * v1.x + v1.z * v1.z))
        let mag2 = Double(sqrt(v2.x * v2.x + v2.z * v2.z))

        // Avoid division by zero
        if mag1 == 0 || mag2 == 0 {
            return 0
        }

        // Clamp the cosine value to [-1, 1] to avoid NaN from acos due to precision errors
        let cosTheta = max(-1.0, min(1.0, dotProduct / (mag1 * mag2)))
        let angleInRadians = acos(cosTheta)

        return angleInRadians * 180.0 / .pi
    }

    /// Calculates the angle (in degrees) at point B formed by points A, B, and C.
    /// Each point is a NormalizedLandmark with x and y coordinates (z is ignored).
    private func calculateXYAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark) -> Double {
        let v1 = (x: a.x - b.x, y: a.y - b.y)
        let v2 = (x: c.x - b.x, y: c.y - b.y)

        let dotProduct = Double(v1.x * v2.x + v1.y * v2.y)

        let mag1 = Double(sqrt(v1.x * v1.x + v1.y * v1.y))
        let mag2 = Double(sqrt(v2.x * v2.x + v2.y * v2.y))

        // Avoid division by zero
        if mag1 == 0 || mag2 == 0 {
            return 0
        }

        // Clamp the cosine value to [-1, 1] to avoid NaN from acos due to precision errors
        let cosTheta = max(-1.0, min(1.0, dotProduct / (mag1 * mag2)))
        let angleInRadians = acos(cosTheta)

        return angleInRadians * 180.0 / .pi
    }

    /// Calculates the angle (in degrees) at point B formed by points A, B, and C.
    /// Each point is a NormalizedLandmark with y and z coordinates (x is ignored).
    private func calculateYZAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark) -> Double {
        let v1 = (y: a.y - b.y, z: a.z - b.z)
        let v2 = (y: c.y - b.y, z: c.z - b.z)

        let dotProduct = Double(v1.y * v2.y + v1.z * v2.z)

        let mag1 = Double(sqrt(v1.y * v1.y + v1.z * v1.z))
        let mag2 = Double(sqrt(v2.y * v2.y + v2.z * v2.z))

        // Avoid division by zero
        if mag1 == 0 || mag2 == 0 {
            return 0
        }

        // Clamp the cosine value to [-1, 1] to avoid NaN from acos due to precision errors
        let cosTheta = max(-1.0, min(1.0, dotProduct / (mag1 * mag2)))
        let angleInRadians = acos(cosTheta)

        return angleInRadians * 180.0 / .pi
    }

    /// Calculates the angle (in degrees) at point B formed by points A, B, and C.
    /// Each point is a NormalizedLandmark with x, y, and z coordinates.
    private func calculate3DAngle(a: NormalizedLandmark, b: NormalizedLandmark, c: NormalizedLandmark) -> Double {
        let v1 = (x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
        let v2 = (x: c.x - b.x, y: c.y - b.y, z: c.z - b.z)

        let dotProduct = Double(v1.x * v2.x + v1.y * v2.y + v1.z * v2.z)

        let mag1 = Double(sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z))
        let mag2 = Double(sqrt(v2.x * v2.x + v2.y * v2.y + v2.z * v2.z))

        // Avoid division by zero
        if mag1 == 0 || mag2 == 0 {
            return 0
        }

        // Clamp the cosine value to [-1, 1] to avoid NaN from acos due to precision errors
        let cosTheta = max(-1.0, min(1.0, dotProduct / (mag1 * mag2)))
        let angleInRadians = acos(cosTheta)

        return angleInRadians * 180.0 / .pi
    }

    /// Calculates the total angle of a finger by summing the angles at MCP, PIP, and DIP joints.
    private func calculateFingerTotalAngle(wrist: NormalizedLandmark, mcp: NormalizedLandmark, pip: NormalizedLandmark, dip: NormalizedLandmark, tip: NormalizedLandmark, correct: Bool = false) -> Double {
        var mcpAngle = calculate3DAngle(a: wrist, b: mcp, c: pip)
        if correct && mcpAngle > 90 && mcpAngle < 180 {
            mcpAngle = mcpAngle * (mcpAngle / 250 + 0.34 )
        }
        var pipAngle = calculate3DAngle(a: mcp, b: pip, c: dip)
        if correct && pipAngle > 90 && pipAngle < 180 {
            pipAngle = pipAngle * (pipAngle / 250 + 0.34 )
        }
        var dipAngle = calculate3DAngle(a: pip, b: dip, c: tip)
        if correct && dipAngle > 90 && dipAngle < 180 {
            dipAngle = dipAngle * (dipAngle / 250 + 0.34 )
        }
        if mcpAngle + pipAngle < 320 {
            dipAngle = min((mcpAngle + pipAngle) / 2, dipAngle)
        }
        return max(min(mcpAngle, 185), 85) + max(min(pipAngle, 185), 85) + max(min(dipAngle, 185), 85)
    }

    // MARK: - Landmark Drawing

    private func drawLandmarks(handResult: HandLandmarkerResult?, poseResult: PoseLandmarkerResult?) {
        DispatchQueue.main.async {
            let path = UIBezierPath()
            let width = self.bounds.width
            let height = self.bounds.height

            // Draw pose landmarks
            if let poseResult = poseResult {
                for poseLandmarks in poseResult.landmarks {
                    guard poseLandmarks.count > 0 else {
                        continue
                    }
                    self.drawPoseLandmarks(poseLandmarks, path: path, width: width, height: height)
                }
            }

            // Draw hand landmarks
            if let handResult = handResult {
                for handLandmarks in handResult.landmarks {
                    guard handLandmarks.count > 0 else {
                        continue
                    }
                    self.drawHandLandmarks(handLandmarks, path: path, width: width, height: height)
                }
            }

            self.overlayLayer.path = path.cgPath
        }
    }

    private func drawPoseLandmarks(_ landmarks: [NormalizedLandmark], path: UIBezierPath, width: CGFloat, height: CGFloat) {
        // MediaPipe Pose has 33 landmarks with standard connections
        // Define key connections manually since PoseLandmarker.poseConnections may not be available
        let poseConnections: [(Int, Int)] = [
            // Face
            (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8), (9, 10),
            // Arms
            (11, 12), (11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19),
            (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
            // Torso
            (11, 23), (12, 24), (23, 24),
            // Legs
            (23, 25), (25, 27), (27, 29), (27, 31),
            (24, 26), (26, 28), (28, 30), (28, 32)
        ]

        drawLandmarkConnections(landmarks: landmarks, connections: poseConnections, path: path, width: width, height: height)
        drawLandmarkPoints(landmarks: landmarks, path: path, width: width, height: height, radius: 4.0)
    }

    private func drawHandLandmarks(_ landmarks: [NormalizedLandmark], path: UIBezierPath, width: CGFloat, height: CGFloat) {
        let connections = HandLandmarker.handConnections.map {
            (Int($0.start), Int($0.end))
        }
        drawLandmarkConnections(landmarks: landmarks, connections: connections, path: path, width: width, height: height)
        drawLandmarkPoints(landmarks: landmarks, path: path, width: width, height: height, radius: 3.0)
    }

    private func drawLandmarkConnections(
        landmarks: [NormalizedLandmark],
        connections: [(Int, Int)],
        path: UIBezierPath,
        width: CGFloat,
        height: CGFloat
    ) {
        for (startIndex, endIndex) in connections {
            guard startIndex < landmarks.count && endIndex < landmarks.count else {
                continue
            }

            let startPoint = landmarks[startIndex]
            let endPoint = landmarks[endIndex]

            let startX = CGFloat(startPoint.x) * width
            let startY = CGFloat(startPoint.y) * height
            let endX = CGFloat(endPoint.x) * width
            let endY = CGFloat(endPoint.y) * height

            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
    }

    private func drawLandmarkPoints(
        landmarks: [NormalizedLandmark],
        path: UIBezierPath,
        width: CGFloat,
        height: CGFloat,
        radius: CGFloat
    ) {
        for landmark in landmarks {
            let x = CGFloat(landmark.x) * width
            let y = CGFloat(landmark.y) * height
            let circle = UIBezierPath(
                arcCenter: CGPoint(x: x, y: y),
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            path.append(circle)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        do {
            let mpImage = try MPImage(sampleBuffer: sampleBuffer, orientation: .up)
            let timestampMs = Int(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds * 1000)

            // Process hand detection
            if let handLandmarker = handLandmarker {
                try handLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            }

            // Process pose detection
            if let poseLandmarker = poseLandmarker {
                try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            }
        } catch {
            print("Error processing frame:", error)
        }
    }
}

// MARK: - Helper Methods

private func handleLandmarkDetectionError(_ error: Error?, resultName: String) -> Bool {
    if let error = error {
        print("\(resultName) landmark detection error: \(error)")
        return true
    }
    return false
}

// MARK: - HandLandmarkerLiveStreamDelegate
extension CameraPreviewView: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(_ handLandmarker: HandLandmarker,
                        didFinishDetection result: HandLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        guard !handleLandmarkDetectionError(error, resultName: "Hand") else {
            return
        }

        if let result = result, let firstHand = result.landmarks.first, firstHand.count > 20 {
            let wrist = firstHand[0]

            if exerciseType == .openingAndClosingTheFist {
                // Index finger: 5, 6, 7, 8
                let indexAngle = Int(calculateFingerTotalAngle(wrist: wrist, mcp: firstHand[5], pip: firstHand[6], dip: firstHand[7], tip: firstHand[8], correct: true).rounded())
                self.indexFingerTotalAngle = indexAngle

                // Middle finger: 9, 10, 11, 12
                let middleAngle = Int(calculateFingerTotalAngle(wrist: wrist, mcp: firstHand[9], pip: firstHand[10], dip: firstHand[11], tip: firstHand[12], correct: true).rounded())
                self.middleFingerTotalAngle = middleAngle

                // Ring finger: 13, 14, 15, 16
                let ringAngle = Int(calculateFingerTotalAngle(wrist: wrist, mcp: firstHand[13], pip: firstHand[14], dip: firstHand[15], tip: firstHand[16], correct: true).rounded())
                self.ringFingerTotalAngle = ringAngle

                // Pinky: 17, 18, 19, 20
                let pinkyAngle = Int(calculateFingerTotalAngle(wrist: wrist, mcp: firstHand[17], pip: firstHand[18], dip: firstHand[19], tip: firstHand[20], correct: true).rounded())
                self.pinkyTotalAngle = pinkyAngle

                var data: [String: Any] = [:]
                if indexAngle < 420 && middleAngle < 420 && ringAngle < 420 && pinkyAngle < 420 {
                    self.indexFingerTotalMinAngle = min(self.indexFingerTotalMinAngle ?? 1000, indexAngle)
                    self.middleFingerTotalMinAngle = min(self.middleFingerTotalMinAngle ?? 1000, middleAngle)
                    self.ringFingerTotalMinAngle = min(self.ringFingerTotalMinAngle ?? 1000, ringAngle)
                    self.pinkyTotalMinAngle = min(self.pinkyTotalMinAngle ?? 1000, pinkyAngle)

                    if let indexMax = indexFingerTotalMaxAngle, let middleMax = middleFingerTotalMaxAngle,
                       let ringMax = ringFingerTotalMaxAngle, let pinkyMax = pinkyTotalMaxAngle {
                        data["index_extension"] = indexMax
                        self.indexFingerTotalMaxAngle = nil
                        data["middle_extension"] = middleMax
                        self.middleFingerTotalMaxAngle = nil
                        data["ring_extension"] = ringMax
                        self.ringFingerTotalMaxAngle = nil
                        data["pinky_extension"] = pinkyMax
                        self.pinkyTotalMaxAngle = nil
                    }
                } else {
                    self.indexFingerTotalMaxAngle = max(self.indexFingerTotalMaxAngle ?? 0, indexAngle)
                    self.middleFingerTotalMaxAngle = max(self.middleFingerTotalMaxAngle ?? 0, middleAngle)
                    self.ringFingerTotalMaxAngle = max(self.ringFingerTotalMaxAngle ?? 0, ringAngle)
                    self.pinkyTotalMaxAngle = max(self.pinkyTotalMaxAngle ?? 0, pinkyAngle)

                    if let indexMin = indexFingerTotalMinAngle, let middleMin = middleFingerTotalMinAngle,
                       let ringMin = ringFingerTotalMinAngle, let pinkyMin = pinkyTotalMinAngle {
                        data["index_flexion"] = indexMin
                        self.indexFingerTotalMinAngle = nil
                        data["middle_flexion"] = middleMin
                        self.middleFingerTotalMinAngle = nil
                        data["ring_flexion"] = ringMin
                        self.ringFingerTotalMinAngle = nil
                        data["pinky_flexion"] = pinkyMin
                        self.pinkyTotalMinAngle = nil
                    }
                }
                // if let indexMax = indexFingerTotalMaxAngle, let middleMax = middleFingerTotalMaxAngle,
                //    let ringMax = ringFingerTotalMaxAngle, let pinkyMax = pinkyTotalMaxAngle,
                //    indexAngle < indexMax - 60 && middleAngle < middleMax - 60 &&
                //        ringAngle < ringMax - 60 && pinkyAngle < pinkyMax - 60 {
                //     data["index_extension"] = indexMax
                //     self.indexFingerTotalMaxAngle = nil
                //     data["middle_extension"] = middleMax
                //     self.middleFingerTotalMaxAngle = nil
                //     data["ring_extension"] = ringMax
                //     self.ringFingerTotalMaxAngle = nil
                //     data["pinky_extension"] = pinkyMax
                //     self.pinkyTotalMaxAngle = nil
                // } else {
                //     self.indexFingerTotalMaxAngle = max(self.indexFingerTotalMaxAngle ?? 0, indexAngle)
                //     self.middleFingerTotalMaxAngle = max(self.middleFingerTotalMaxAngle ?? 0, middleAngle)
                //     self.ringFingerTotalMaxAngle = max(self.ringFingerTotalMaxAngle ?? 0, ringAngle)
                //     self.pinkyTotalMaxAngle = max(self.pinkyTotalMaxAngle ?? 0, pinkyAngle)
                // }
                // if let indexMin = indexFingerTotalMinAngle, let middleMin = middleFingerTotalMinAngle,
                //    let ringMin = ringFingerTotalMinAngle, let pinkyMin = pinkyTotalMinAngle,
                //    indexAngle > indexMin + 60 && middleAngle > middleMin + 60 &&
                //        ringAngle > ringMin + 60 && pinkyAngle > pinkyMin + 60 {
                //     data["index_flexion"] = indexMin
                //     self.indexFingerTotalMinAngle = nil
                //     data["middle_flexion"] = middleMin
                //     self.middleFingerTotalMinAngle = nil
                //     data["ring_flexion"] = ringMin
                //     self.ringFingerTotalMinAngle = nil
                //     data["pinky_flexion"] = pinkyMin
                //     self.pinkyTotalMinAngle = nil
                // } else {
                //     self.indexFingerTotalMinAngle = min(self.indexFingerTotalMinAngle ?? 1000, indexAngle)
                //     self.middleFingerTotalMinAngle = min(self.middleFingerTotalMinAngle ?? 1000, middleAngle)
                //     self.ringFingerTotalMinAngle = min(self.ringFingerTotalMinAngle ?? 1000, ringAngle)
                //     self.pinkyTotalMinAngle = min(self.pinkyTotalMinAngle ?? 1000, pinkyAngle)
                // }

                if !data.isEmpty {
                    HandoneMediaPipePlugin.sendData(data)
                }
            } else if exerciseType == .wristExtensionAndFlexion {
                // Get elbow from pose landmarks
                var elbow: NormalizedLandmark? = nil
                // Determine handedness to pick correct elbow
                var handedness = result.handedness.first?.first?.categoryName
                if let poseResult = poseResult, let poseLandmarks = poseResult.landmarks.first, poseLandmarks.count > 14 {
                    let leftElbowVisibility = poseLandmarks[13].visibility?.doubleValue ?? 0.0
                    let rightElbowVisibility = poseLandmarks[14].visibility?.doubleValue ?? 0.0
                    if ((handedness == "Left" && leftElbowVisibility < 0.2) || (handedness == "Right" && rightElbowVisibility < 0.2)) {
                        handedness = nil
                    } else {
                        // MediaPipe Pose: 13 is Left Elbow, 14 is Right Elbow
                        if handedness == "Left" {
                            elbow = poseLandmarks[13]
                        } else {
                            elbow = poseLandmarks[14]
                        }
                    }
                }

                // Calculating angle between middle finger MCP, wrist, and elbow
                if let elbow = elbow {
                    let pinky = firstHand[17]
                    let wrist = firstHand[0]
                    let angle = abs(180 - Int(calculateXYAngle(a: pinky, b: wrist, c: elbow).rounded()))
                    let xApogee = wrist.x - (wrist.y - pinky.y) * ((wrist.x - elbow.x) / (wrist.y - elbow.y))
                    if (angle <= 90) {
                        var data: [String: Any] = [:]
                        if pinky.x < xApogee && handedness == "Left" || pinky.x > xApogee && handedness == "Right" {
                            self.flexionAngle = angle;
                            self.flexionMaxAngle = max(self.flexionMaxAngle ?? 0, angle)
                            self.extensionAngle = nil;
                            if let extensionMaxAngle = self.extensionMaxAngle {
                                if extensionMaxAngle > 9 {
                                    data["extension"] = extensionMaxAngle
                                }
                                self.extensionMaxAngle = nil
                            }
                        } else {
                            self.flexionAngle = nil;
                            if let flexionMaxAngle = self.flexionMaxAngle {
                                if flexionMaxAngle > 9 {
                                    data["flexion"] = flexionMaxAngle
                                }
                                self.flexionMaxAngle = nil
                            }
                            self.extensionAngle = angle;
                            self.extensionMaxAngle = max(self.extensionMaxAngle ?? 0, angle)
                        }
                        if !data.isEmpty {
                            HandoneMediaPipePlugin.sendData(data)
                        }
                    }
                }
            } else if exerciseType == .forearmSupinationAndPronation {
                let pinkyMcp = firstHand[17]
                let indexFingerMcp = firstHand[5]
                let indexFingerMcpZeroZ = NormalizedLandmark(
                    x: indexFingerMcp.x,
                    y: indexFingerMcp.y,
                    z: 0,
                    visibility: indexFingerMcp.visibility,
                    presence: indexFingerMcp.presence
                )
                var angle = Int(calculate3DAngle(a: pinkyMcp, b: indexFingerMcp, c: indexFingerMcpZeroZ).rounded())
                var data: [String: Any] = [:]
                var handedness = result.handedness.first?.first?.categoryName
                if pinkyMcp.x < indexFingerMcp.x && handedness == "Left" || pinkyMcp.x > indexFingerMcp.x && handedness == "Right" {
                    if (angle > 92 && (supinationMaxAngle ?? 0) < 88) {
                        angle = 180 - angle
                    }
                    if (angle > 91) {
                        return
                    }
                    self.supinationAngle = angle
                    self.supinationMaxAngle = max(self.supinationMaxAngle ?? 0, angle)
                    self.pronationAngle = nil
                    if let pronationMaxAngle = self.pronationMaxAngle {
                        if pronationMaxAngle > 9 {
                            data["pronation"] = pronationMaxAngle
                        }
                        self.pronationMaxAngle = nil
                    }
                } else {
                    if (angle > 92 && (pronationMaxAngle ?? 0) < 88) {
                        angle = 180 - angle
                    }
                    if (angle > 91) {
                        return
                    }
                    self.supinationAngle = nil
                    if let supinationMaxAngle = self.supinationMaxAngle {
                        if supinationMaxAngle > 9 {
                            data["supination"] = supinationMaxAngle
                        }
                        self.supinationMaxAngle = nil
                    }
                    self.pronationAngle = angle
                    self.pronationMaxAngle = max(self.pronationMaxAngle ?? 0, angle)
                }
                if !data.isEmpty {
                    HandoneMediaPipePlugin.sendData(data)
                }
            }

            DispatchQueue.main.async {
                self.exerciseTypeTextLayer.string = self.informationText
            }
        }

        handResult = result
        // drawLandmarks(handResult: handResult, poseResult: poseResult)
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate
extension CameraPreviewView: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        guard !handleLandmarkDetectionError(error, resultName: "Pose") else {
            return
        }

        poseResult = result
        // drawLandmarks(handResult: handResult, poseResult: poseResult)
    }
}
