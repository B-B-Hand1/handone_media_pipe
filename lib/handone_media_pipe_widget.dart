import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ExerciseType {
  openingAndClosingTheFist,
  wristExtensionAndFlexion,
  forearmSupinationAndPronation,
}

class HandoneMediaPipeWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) dataReceived;
  final bool debug;
  final ExerciseType exerciseType;

  const HandoneMediaPipeWidget({
    required this.dataReceived,
    this.debug = false,
    required this.exerciseType,
    super.key,
  });

  @override
  State<HandoneMediaPipeWidget> createState() => _HandoneMediaPipeWidgetState();
}

class _HandoneMediaPipeWidgetState extends State<HandoneMediaPipeWidget> {
  static const EventChannel _eventChannel = EventChannel(
    'handone_media_pipe/dataReceived',
  );
  StreamSubscription<dynamic>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _dataSubscription = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          widget.dataReceived(Map<String, dynamic>.from(data));
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('Error receiving data: $error');
        }
      },
    );
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'debug': widget.debug,
      'exerciseType': widget.exerciseType.name,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'camera_preview',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'camera_preview',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (int id) {
          // Platform view created - arguments should be available
          if (kDebugMode) {
            print(
              'UiKitView created with id: $id, debug: ${widget.debug}, exerciseType: ${widget.exerciseType.name}',
            );
          }
        },
      );
    }

    return Text('$defaultTargetPlatform is not yet supported by this plugin');
  }
}
