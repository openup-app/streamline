import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

class IncomingVideoLocalServer {
  final HttpServer _server;
  final StreamController<Uint8List> _responseController;
  StreamSubscription? _streamSubscription;

  static Future<IncomingVideoLocalServer> create({
    String mimeType = 'video/mp4',
  }) async {
    final responseController = StreamController<Uint8List>.broadcast();
    final server = await _createServer(responseController.stream, mimeType);
    return IncomingVideoLocalServer._(server, responseController);
  }

  IncomingVideoLocalServer._(this._server, this._responseController);

  void addStream(Stream<Uint8List> stream) {
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen((data) {
      _responseController.add(data);
    });
  }

  void dispose() {
    _streamSubscription?.cancel();
    _server.close();
    _responseController.close();
  }

  String get url => 'http://${_server.address.host}:${_server.port}';
}

Future<HttpServer> _createServer(
  Stream<Uint8List> responseStream,
  String mimeType,
) async {
  final router = Router();

  router.get('/', (Request request) {
    return Response.ok(
      responseStream,
      headers: {
        'Content-Type': mimeType,
        // 'Transfer-Encoding': 'chunked',
      },
    );
  });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  return await serve(handler, 'localhost', 0);
}

Future<Stream<Uint8List>?> h265ToMp4(Stream<Uint8List> videoData) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  final outputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null || outputPipe == null) {
    return null;
  }

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -c:v copy -y -f mp4 -movflags +frag_keyframe+empty_moov $outputPipe';

  final outputByteStream =
      File(outputPipe).openRead().map(Uint8List.fromList).asBroadcastStream();

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
      await FFmpegKitConfig.closeFFmpegPipe(outputPipe);
    },
    (log) => print(log.getMessage()),
  );

  return outputByteStream;
}
