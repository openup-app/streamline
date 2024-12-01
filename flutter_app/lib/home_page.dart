import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:streamline/partcipant.dart';
import 'package:streamline/record.dart';
import 'package:video_player/video_player.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  VideoPlayerController? _controller;
  final _particpant = Participant('com_openup_phone');
  Connection? _connection;

  void _initFile(File file) async {
    print('INITING with ${file.path}');
    _controller?.dispose();
    setState(() => _controller = null);
    _controller = VideoPlayerController.file(file);
    _controller!.initialize().then((_) {
      print('DONE');
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller?.value.hasError == true) {
      print(_controller?.value.errorDescription);
    } else {
      print('No error with video controller');
    }
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () async {
                print('Request');
                final status = await Permission.camera.request();
                print('Status $status');
              },
              child: const Text('Request Permissions'),
            ),
            FilledButton(
              onPressed: () async {
                _controller?.dispose();
                setState(() => _controller = null);
                final stream = await startRecording();
                if (stream != null) {
                  // print('Has stream');
                  stream.listen((data) {
                    // _connection?.sendUint8List(Uint8List.fromList(data));
                  });
                  // startHttpStreamServer(stream);
                  // streamMKVToVLC(stream, '192.168.86.139', 12345);
                  // uploadFile(
                  //   await file.readAsBytes(),
                  //   'output${path.extension(file.path)}',
                  // );
                }

                // if (mounted && file != null) {
                // _initFile(file);
                // }
              },
              child: const Text('Record'),
            ),
            FilledButton(
              onPressed: () => cancelAll(),
              child: const Text('Cancel All'),
            ),
            FilledButton(
              onPressed: _startPeer,
              child: const Text('Start Peer'),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  print(
                      'COntroller is null? ${controller == null}, ineted? ${controller?.value.isInitialized}');
                  if (controller == null || !controller.value.isInitialized) {
                    return const Center(
                      child: Text('No video'),
                    );
                  }
                  return ColoredBox(
                    color: Colors.orange,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          controller.value.isPlaying
                              ? controller.pause()
                              : controller.play();
                        });
                      },
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startPeer() async {
    final connection = await _particpant.listen();
    print('Phone connected');
    if (mounted) {
      setState(() => _connection = connection);
    }
    await Future.delayed(const Duration(seconds: 1));
    connection.send('WOWOW');
  }
}

Future<void> uploadFile(Uint8List fileBytes, String filename) async {
  final uri = Uri.parse('http://192.168.86.139:8080/upload');
  final request = http.MultipartRequest('POST', uri)
    ..files.add(http.MultipartFile.fromBytes(
      'file', // Key expected by the Flask server
      fileBytes,
      filename: filename,
    ));
  final response = await request.send();

  if (response.statusCode == 200) {
    print('File uploaded successfully!');
  } else {
    print('Failed to upload file: ${response.statusCode}');
  }
}

void startHttpStreamServer(Stream<List<int>> mkvStream) async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('Listening on http://localhost:8080');

  await for (var request in server) {
    request.response.headers.contentType = ContentType("video", "x-matroska");
    request.response.statusCode = HttpStatus.ok;

    // Stream the MKV data directly
    await for (var chunk in mkvStream) {
      request.response.add(chunk); // Stream chunks to the client
    }

    await request.response.close();
  }
}

Future<void> streamMKVToVLC(
    Stream<List<int>> mkvStream, String targetIp, int targetPort) async {
  // Create a UDP socket for streaming
  final RawDatagramSocket socket =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  // Specify the destination address and port
  final destinationAddress = InternetAddress(targetIp);
  final destinationPort = targetPort;

  // Listen to the MKV data stream and send over UDP
  await for (var chunk in mkvStream) {
    // Send the chunk to the target address
    socket.send(chunk, destinationAddress, destinationPort);
  }

  socket.close();
}
