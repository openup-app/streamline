import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';
import 'package:flutter/services.dart';

Future<Stream<Uint8List>?> decode(Stream<Uint8List> videoData) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  final outputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null || outputPipe == null) {
    return null;
  }

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -vf format=rgba -y -f rawvideo $outputPipe';

  final outputByteStream =
      File(outputPipe).openRead().map(Uint8List.fromList).asBroadcastStream();

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      print('#### Done');
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
      await FFmpegKitConfig.closeFFmpegPipe(outputPipe);
    },
    (log) => print(log.getMessage()),
  );

  return outputByteStream;
}

Future<Stream<Uint8List>?> convertToMKV(Stream<Uint8List> videoData) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  final outputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null || outputPipe == null) {
    return null;
  }

  // Open the input pipe for writing the incoming video stream
  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  // The FFmpeg command to convert H.265 to MKV format
  final command =
      '-hide_banner -i $inputPipe -c:v copy -y -f mp4 -movflags +frag_keyframe+empty_moov $outputPipe';

  // Create a stream for the output MKV data
  final outputByteStream =
      File(outputPipe).openRead().map(Uint8List.fromList).asBroadcastStream();

  // Execute the FFmpeg command asynchronously
  await FFmpegKit.executeAsync(
    command,
    (_) async {
      print('#### Conversion to MKV Complete');
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
      await FFmpegKitConfig.closeFFmpegPipe(outputPipe);
    },
    (log) => print(log.getMessage()),
  );

  // Return the output stream of MKV data
  return outputByteStream;
}

Future<Stream<Uint8List>?> muxToMp4(Stream<Uint8List> h265Stream) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  final outputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null || outputPipe == null) {
    return null;
  }

  final inputSink = File(inputPipe).openWrite();

  final command =
      '-hide_banner -f hevc -fflags +genpts  -i $inputPipe -c:v copy -y -movflags frag_keyframe+empty_moov -f mp4 $outputPipe';

  final mp4Stream =
      File(outputPipe).openRead().map(Uint8List.fromList).asBroadcastStream();

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      print('#### Muxing Completed');
      // await inputSink.close();
      // await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
      // await FFmpegKitConfig.closeFFmpegPipe(outputPipe);
    },
    (log) => print(log.getMessage()),
  );

  h265Stream.listen((d) {
    inputSink.add(d);
  });
  // inputSink.addStream(h265Stream);

  return mp4Stream;
}

Future<Stream<List<int>>?> decodeToHLS(Stream<List<int>> videoData) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  final outputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();

  if (inputPipe == null || outputPipe == null) return null;

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -c:v hevc_videotoolbox -hls_time 4 -hls_list_size 5 -y -f mpegts $outputPipe';

  // Output stream for reading from the output pipe
  final outputStream = File(outputPipe)
      .openRead()
      .map((list) => list as List<int>)
      .asBroadcastStream();

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
      await FFmpegKitConfig.closeFFmpegPipe(outputPipe);
    },
    (log) => print(log.getMessage()),
  );

  return outputStream;
}

Future<String?> decodeToRTSP(Stream<List<int>> videoData) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();

  if (inputPipe == null) return null;

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -c:v hevc_videotoolbox -f rtsp rtsp://localhost:8554/live.sdp';

  // Execute FFmpeg to start streaming to RTSP server
  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
    },
    (log) => print(log.getMessage()),
  );
  return 'rtsp://localhost:8554/live.sdp';
}

class VideoToolbox {
  static const _eventChannel = EventChannel('com.openup.media.texture');
  static const _methodChannel = MethodChannel('com.openup.media.encoded');
  // final _textureController = StreamController<int>.broadcast();

  VideoToolbox() {
    // _eventChannel.receiveBroadcastStream().listen((data) => _textureController.add));
  }

  // void dispose() {
  //   _textureController.close();
  // }

  void decode(Uint8List data) async {
    try {
      await _methodChannel.invokeMethod('decode', data);
      print('Success');
    } on PlatformException catch (e) {
      print(e.message);
    }
  }

  // Stream<int> get textures => _textureController.stream;
  Stream<int> get textureIds =>
      _eventChannel.receiveBroadcastStream().map((e) => e as int);
}
