import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

List<int?> sessionIds = [];

FFmpegSession? _session;

void cancelAll() async {
  _session?.cancel();
  for (final sessionId in sessionIds) {
    await FFmpegKit.cancel(sessionId);
  }
  print('Cancelled');
  sessionIds.clear();
}

Future<Stream<List<int>>?> startRecording() async {
  final tempDir = await getTemporaryDirectory();
  final outputDir = Directory('${tempDir.path}/recordings');
  const extension = 'mkv';
  const format = 'mpegts';
  outputDir.create(recursive: true);
  final id = Random().nextInt(100000000);
  // final outputFile = File('${outputDir.path}/recording_$id.$extension');
  final outputFile = File('${outputDir.path}/out.sdp');
  await outputFile.create();

  final pipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (pipe == null) {
    return null;
  }
  final String command;
  if (Platform.isIOS) {
    command =
        '''-hide_banner -s 1920x1080 -f avfoundation -framerate 30 -i \"0\" -c:v hevc_videotoolbox -b:v 25M -r 30 -g 2 -profile:v main10 -pix_fmt nv12 -t 10 -y -f hevc $pipe''';
  } else {
    command =
        '''-hide_banner -s 1920x1080 -f android_camera -framerate 30 -i "0" -c:v hevc -b:v 25M -r 30 -g 2 -profile:v main10 -pix_fmt nv12 -t 10 -y -f rtp rtp://192.168.86.22:1234 -sdp_file ${outputFile.path}''';
  }

  // Read the output from the pipe
  final outputSink = outputFile.openWrite();
  final byteStream = File(pipe).openRead();
  // byteStream.listen(outputSink.add);

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await FFmpegKitConfig.closeFFmpegPipe(pipe);
      // await outputSink.flush();
      // await outputSink.close();

      // completer.complete(outputFile);
    },
    (log) => print(log.getMessage()),
  );

  await Future.delayed(const Duration(seconds: 1));
  final sdp = await outputFile.readAsString();
  print(sdp);

  return byteStream;
  // return Stream.fromIterable([]);
  // await FFmpegKit.execute(command);
  // return outputFile;
}
