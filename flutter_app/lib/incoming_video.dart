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

  String get url => 'http://localhost:${_server.port}';
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

Future<bool> h265ToHls(Stream<Uint8List> videoData, String url) async {
  final inputPipe = await FFmpegKitConfig.registerNewFFmpegPipe();
  if (inputPipe == null) {
    return false;
  }

  final inputSink = File(inputPipe).openWrite();
  inputSink.addStream(videoData);

  final command =
      '-hide_banner -i $inputPipe -c:v copy -y -f hls -hls_time 4 -hls_list_size 5 -hls_flags delete_segments -method PUT $url/stream.m3u8';
  print('### Command $command');

  await FFmpegKit.executeAsync(
    command,
    (_) async {
      await inputSink.close();
      await FFmpegKitConfig.closeFFmpegPipe(inputPipe);
    },
    (log) => print(log.getMessage()),
  );
  return true;
}

class HlsServer {
  HttpServer? _server;
  StreamSubscription? _streamSubscription;

  final memoryStore = <String, List<int>>{};

  Future<void> start() async {
    final app = Router()
      ..put('/<path|.*>', _handlePut)
      ..get('/<path|.*>', _serveHls);

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(app.call);
    final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
    _server = server;
    print(
        '### Server listening on http://${server.address.host}:${server.port}');
  }

  void addStream(Stream<Uint8List> stream) {
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen((data) {});
  }

  void dispose() {
    _streamSubscription?.cancel();
    _server?.close();
  }

  String get url =>
      _server == null ? '' : 'http://${_server?.address.host}:${_server?.port}';

  Future<Response> _handlePut(Request request) async {
    final path = request.url.path;
    print('#### Put $path');
    final content = await request.read().toList();
    memoryStore[path] = content.expand((e) => e).toList();
    return Response.ok('Received $path');
  }

  Response _serveHls(Request request) {
    final path = request.url.path;
    print('#### Get $path');
    if (memoryStore.containsKey(path)) {
      print('### Found');
      return Response.ok(memoryStore[path]!, headers: {
        'Content-Type': path.endsWith('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : 'video/mp2t',
      });
    }
    print('### Not Found');
    return Response.notFound('Not found');
  }
}
