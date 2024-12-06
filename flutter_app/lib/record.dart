import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';

List<int?> sessionIds = [];

void stopRecording() async {
  for (final sessionId in sessionIds) {
    await FFmpegKit.cancel(sessionId);
  }
  sessionIds.clear();
}

Future<Stream<List<int>>?> startRecording() async {
  final pipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (pipe == null) {
    return null;
  }
  final String command;
  if (Platform.isIOS) {
    command =
        '''-hide_banner -s 1920x1080 -f avfoundation -framerate 30 -i \"0\" -c:v hevc_videotoolbox -b:v 25M -r 30 -g 30 -profile:v main10 -pix_fmt nv12 -tag:v hvc1 -y -f hevc $pipe''';
  } else {
    command =
        '''-hide_banner -s 1920x1080 -f android_camera -framerate 30 -i "0" -c:v hevc -b:v 25M  -g 30 -profile:v main10 -level:v 5.1 -pix_fmt yuv420p10le -y -f hevc $pipe''';
  }

  final byteStream = File(pipe).openRead();

  final session = await FFmpegKit.executeAsync(
    command,
    (_) async {
      await FFmpegKitConfig.closeFFmpegPipe(pipe);
    },
    (log) => print(log.getMessage()),
  );
  sessionIds.add(session.getSessionId());
  return byteStream;
}
