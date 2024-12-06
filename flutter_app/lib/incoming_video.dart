import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

class HlsServer {
  HttpServer? _server;
  StreamSubscription? _streamSubscription;

  final memoryStore = <String, List<int>>{};
  final _hasContent = Completer<void>();

  Future<void> start() async {
    final app = Router()
      ..put('/<path|.*>', _handlePut)
      ..get('/<path|.*>', _handleGet)
      ..delete('/path|.*>', _handleDelete);

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(app.call);
    final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
    _server = server;
    debugPrint(
        'HLS server listening on http://${_server?.address.host}:${server.port}');
  }

  void addStream(Stream<Uint8List> stream) {
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen((data) {});
  }

  void dispose() {
    _streamSubscription?.cancel();
    _server?.close();
  }

  Future<void> get hasContent => _hasContent.future;

  String get url =>
      _server == null ? '' : 'http://${_server?.address.host}:${_server?.port}';

  Future<Response> _handlePut(Request request) async {
    final path = request.url.path;
    debugPrint('[HLS Server] Put $path');
    final content = await request.read().toList();
    memoryStore[path] = content.expand((e) => e).toList();
    if (!_hasContent.isCompleted) {
      _hasContent.complete();
    }
    return Response.ok('Received $path');
  }

  Response _handleGet(Request request) {
    final path = request.url.path;
    debugPrint('[HLS Server] Get $path');
    if (memoryStore.containsKey(path)) {
      return Response.ok(memoryStore[path]!, headers: {
        'Content-Type': path.endsWith('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : 'video/mp2t',
      });
    }
    return Response.notFound('Not found');
  }

  Response _handleDelete(Request request) {
    final path = request.url.path;
    debugPrint('[HLS Server] Delete $path');
    if (memoryStore.containsKey(path)) {
      memoryStore.remove(path);
      return Response.ok('Removed $path');
    }
    return Response.notFound('Not found');
  }
}

Future<bool> h265ToHls(Stream<Uint8List> videoData, String url) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null) {
    return false;
  }

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -c:v copy -y -f hls -hls_segment_type fmp4 -hls_time 2 -hls_list_size 5 -hls_flags delete_segments -tag:v hvc1 -method PUT $url/stream.m3u8';

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
    },
    (log) => debugPrint(log.getMessage()),
  );
  return true;
}
