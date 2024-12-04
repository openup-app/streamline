import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart' as sr;
import 'package:streamline_web/decoder.dart';
import 'package:streamline_web/participant.dart';
import 'package:streamline_web/server.dart';
import 'package:video_player/video_player.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Playback'),
      ),
      body: const PeerWidget(),
    );
  }
}

class PeerWidget extends StatefulWidget {
  const PeerWidget({super.key});

  @override
  State<PeerWidget> createState() => _PeerWidgetState();
}

class _PeerWidgetState extends State<PeerWidget> {
  final _participant = Participant('com_openup_mac');
  // final _server = Server();
  final _streamController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List>? _decdodedStream;
  ui.Image? _image;
  int _port = 0;
  HttpServer? _server;

  VideoPlayerController? _videoController;
  final _videoToolbox = VideoToolbox();
  IOSink? _sink;
  late final player = mk.Player();
  late final mediaController = mkv.VideoController(player);
  String? _uri;

  @override
  void initState() {
    super.initState();
    _videoToolbox.textureIds.listen((textureId) {
      print('Received texture ID $textureId');
    });
    createStreamUri(_streamController.stream).then((uri) {
      print(uri);
      setState(() => _uri = uri);
      print('READY $uri');
      _initVideoController(Uri.parse('http://localhost:8888'));
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    // _server.dispose();
    _streamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () async {
              print('Tapped');
              final connection = await _participant.connect('com_openup_phone');
              await player.open(mk.Media('http://localhost:8888'));
              // print('URI: $path, ${player.state.duration}');
              // final h265Data = h265File.openRead();
              // h265Data.listen((e) {
              //   _streamController.add(Uint8List.fromList(e));
              // });
              print('OPEN!');
              final mkvStream = await convertToMKV(connection.binaryStream);
              if (mkvStream != null) {
                mkvStream.listen((e) {
                  _streamController.add(e);
                });
              }
            },
            child: Text('Connect and Stream'),
          ),
          // FilledButton(
          //   onPressed: () async {
          //     print('Tapped');
          // final tempDir = await getTemporaryDirectory();
          // final tempOutput = File('${tempDir.path}/out.h265');
          // await tempOutput.create(recursive: true);
          // final connection = await _participant.connect('com_openup_phone');
          // print('Temp output ${tempOutput.path}');
          // print('Mac Connected!');
          // final sink = tempOutput.openWrite();
          // _sink = sink;
          // connection.binaryStream.listen((d) {
          //   print('Got data ${d.length}');
          //   sink.add(d);
          // });
          // connection.binaryStream
          //     .bufferCount(2)
          //     .map((e) => Uint8List.fromList(e.expand((e) => e).toList()))
          //     // .expand((e) => List.from(e.expand((e) => e)))
          //     .listen(_videoToolbox.decode);
          // final decodedStream = await decode(connection.binaryStream);
          // if (decodedStream == null) {
          //   print('Decoded stream is null');
          //   return;
          // }
          // setState(() => _decdodedStream = decodedStream);
          // print('Got decode stream');
          // const bufferSize = 8192;
          // const pixelCount = 1920 * 1080 * 4;
          // final count = 1013; //((1920 * 1080 * 4) / bufferSize).ceil();
          // final images = decodedStream
          //     .bufferCount(count)
          //     .map((b) => b.expand((e) => e))
          //     .map((e) => Uint8List.fromList(e.toList()))
          //     .where((e) => e.length == pixelCount)
          //     .asyncMap((e) async {
          //   print('### Decoding ${e.length} bytes');
          //   final start = DateTime.now();
          //   final image = decodeImageFromPixelsFuture(
          //       e, 1920, 1080, PixelFormat.rgba8888);
          //   print(
          //       'Took  ${DateTime.now().difference(start).inMicroseconds / 1000}ms');
          //   return image;
          // });
          // images.listen((e) {
          //   // print('### DECODED IMAGE');
          //   // setState(() => _image = e);
          // });
          // print('Decoding image now');
          // decodeImageFromPixels(pixels, 1920, 1080, PixelFormat.rgba8888,
          //     (image) async {
          //   print(
          //       'Decoded image ${image.width}x${image.height} took');
          //   // final dir = await getTemporaryDirectory();
          //   // final outFile = File('${dir.path}/out.png');
          //   if (mounted) {

          //   }
          // });

          // final image =
          // final tempFile = File('${dir.path}/temp.')

          // await Future.delayed(const Duration(minutes: 1));
          // print('Path is ${outputFile.path}');

          // print('Closing');
          // await sink.flush();
          // await sink.close();

          // await _server.start(connection.binaryStream);
          // _initVideoController();
          //   },
          //   child: const Text('Connect'),
          // ),
          // FilledButton(
          //   onPressed: () async {
          //     final h265File = File(
          //         '/Users/jaween/Library/Containers/com.example.webApp/Data/Library/Caches/source.h265');
          //     final h265Data = h265File.openRead();
          //     h265Data.map((e) => Uint8List.fromList(e)).listen((data) {
          //       _videoToolbox.decode(data);
          //     });
          //   },
          //   child: Text('Decode Local File'),
          // ),
          // // const SizedBox(height: 8),
          // FilledButton(
          //   onPressed: () async {
          //     await _sink?.flush();
          //     await _sink?.close();
          //     print('Closed');
          //   },
          //   child: Text('CLOSE Temp file'),
          // ),
          // if (_image != null)
          //   Expanded(
          //     child: CustomPaint(
          //       painter: _MyPainter(image: _image!),
          //     ),
          //   ),
          // Expanded(
          //   child: Builder(
          //     builder: (context) {
          //       final decodedStream = _decdodedStream;
          //       if (decodedStream == null) {
          //         return const ColoredBox(
          //           color: Colors.grey,
          //         );
          //       }
          //       return StreamBuilder<Uint8List>(
          //         stream: decodedStream,
          //         builder: (context, snapshot) {
          //           if (snapshot.hasData) {
          //             final imageData = snapshot.data!;
          //             return _MyImage(
          //               data: imageData,
          //             );
          //           }
          //           return const CircularProgressIndicator();
          //         },
          //       );
          //       // final controller = _videoController;
          //       // if (controller == null || controller.value.isInitialized) {
          //       //   return const ColoredBox(
          //       //     color: Colors.grey,
          //       //   );
          //       // }
          //       // return ColoredBox(
          //       //   color: Colors.pink,
          //       //   child: AspectRatio(
          //       //     aspectRatio: controller.value.aspectRatio,
          //       //     child: VideoPlayer(controller),
          //       //   ),
          //       // );
          //     },
          //   ),
          // ),
          // FilledButton(
          //   onPressed: () async {
          //     // _initVideoController();
          //     final h265File = File(
          //         '/Users/jaween/Library/Containers/com.example.webApp/Data/Library/Caches/source.h265');
          //     final path = _uri;
          //     if (path == null) {
          //       return;
          //     }
          //     await player.open(mk.Media('http://localhost:8888'));
          //     print('URI: $path, ${player.state.duration}');
          //     // final h265Data = h265File.openRead();
          //     // h265Data.listen((e) {
          //     //   _streamController.add(Uint8List.fromList(e));
          //     // });
          //     final data = await convertToMKV(
          //         h265File.openRead().map((e) => Uint8List.fromList(e)));
          //     if (data != null) {
          //       _streamController.addStream(data);
          //     }

          //     // final muxed =
          //     //     await decodeToHLS(h265Data.map((e) => Uint8List.fromList(e)));
          //     // final url = await decodeToRTSP(h265Data);
          //     // if (url != null) {
          //     // }
          //     //   muxed?.listen((data) {
          //     //     // _videoToolbox.decode(data);
          //     //     _streamController.add(Uint8List.fromList(data));
          //     //   });
          //   },
          //   child: Text('Decode'),
          // ),
          Expanded(
            child: Builder(
              builder: (context) {
                // final controller = _videoController;
                // if (controller == null || controller.value.isInitialized) {
                //   return const ColoredBox(
                //     color: Colors.grey,
                //   );
                // }
                // return ColoredBox(
                //   color: Colors.pink,
                //   child: AspectRatio(
                //     aspectRatio: controller.value.aspectRatio,
                //     child: VideoPlayer(controller),
                //   ),
                // );
                return mkv.Video(
                  controller: mediaController,
                  // controls: (_) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<ui.Image> decodeImageFromPixelsFuture(
      Uint8List pixels, int width, int height, PixelFormat format) {
    final completer = Completer<ui.Image>();
    decodeImageFromPixels(
      pixels,
      width,
      height,
      format,
      (image) => completer.complete(image),
    );
    return completer.future;
  }

  void _initVideoController(Uri uri) {
    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(uri);
    _videoController?.initialize().then((_) {
      setState(() {});
    });
  }

  Future<String> createStreamUri(Stream<Uint8List> videoStream) async {
    final router = sr.Router();

    // Route to stream the video data
    router.get('/', (Request request) {
      return Response.ok(
        videoStream,
        headers: {
          'Content-Type': 'video/mp4', // Set appropriate MIME type
          // 'Transfer-Encoding': 'chunked',
        },
      );
    });

    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(router);

    _server = await serve(handler, 'localhost', 8888);
    return 'http://localhost:8888';
  }
}

class _MyImage extends StatefulWidget {
  final Uint8List data;

  const _MyImage({
    super.key,
    required this.data,
  });

  @override
  State<_MyImage> createState() => __MyImageState();
}

class __MyImageState extends State<_MyImage> {
  ui.Image? _image;

  @override
  void didUpdateWidget(covariant _MyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    print(
        'Did update size ${widget.data.length} ${widget.data.sublist(0, 100).toList()}');
    final imageFuture = decodeImageFromList(widget.data);
    imageFuture.then((image) {
      if (mounted) {
        setState(() => _image = image);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const FlutterLogo();
    }
    return Container(
      color: Colors.pink,
      child: CustomPaint(
        painter: _MyPainter(image: image),
      ),
    );
  }
}

class _MyPainter extends CustomPainter {
  final ui.Image image;

  _MyPainter({
    required this.image,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.blue);
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
