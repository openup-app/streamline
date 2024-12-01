import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:peerdart/peerdart.dart';
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
  final _server = Server();
  final _streamController = StreamController<Uint8List>.broadcast();

  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _server.dispose();
    _streamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: () async {
              final connection = await _participant.connect('com_openup_phone');
              print('Mac Connected!');
              await _server.start(connection.binaryStream);
              _initVideoController();
            },
            child: const Text('Connect'),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final controller = _videoController;
                if (controller == null || controller.value.isInitialized) {
                  return const ColoredBox(
                    color: Colors.grey,
                  );
                }
                return ColoredBox(
                  color: Colors.pink,
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _initVideoController() {
    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse('http://localhost:8080'),
    );
    _videoController?.initialize().then((_) {
      setState(() {});
    });
  }
}
