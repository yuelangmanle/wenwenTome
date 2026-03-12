import 'package:flutter/services.dart';

class ReaderVolumeKeyService {
  static const MethodChannel _controlChannel = MethodChannel(
    'wenwen_tome/reader_volume_control',
  );
  static const EventChannel _eventChannel = EventChannel(
    'wenwen_tome/reader_volume_events',
  );

  Stream<String>? _eventStream;

  Stream<String> volumeKeyEvents() {
    return _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is String)
        .cast<String>();
  }

  Future<bool> setPagingEnabled(bool enabled) async {
    try {
      return await _controlChannel.invokeMethod<bool>(
            'setVolumePagingEnabled',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
