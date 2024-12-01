import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

class Server {
  HttpServer? _server;

  void dispose() {
    _server?.close();
  }

  Future<void> start(Stream<Uint8List> stream) async {
    _server?.close();
    final server =
        await serve((request) => _handler(request, stream), 'localhost', 8080);
    _server = server;
    print(
        'Serving MPEG-TS stream at http://${server.address.host}:${server.port}');
  }

  FutureOr<Response> _handler(Request request, Stream<Uint8List> stream) async {
    // Respond with the MPEG-TS stream
    return Response(
      200,
      body: stream,
      headers: {
        'Content-Type': 'video/mp2t', // Correct MIME type for MPEG-TS
        'Cache-Control': 'no-cache', // Prevent caching for live streams
        'Transfer-Encoding': 'chunked', // Enable chunked transfer encoding
      },
    );
  }
}
