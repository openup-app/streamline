import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as mk;
import 'package:streamline/incoming_video.dart';
import 'package:streamline/partcipant.dart';
import 'package:streamline/record.dart';
import 'package:video_player/video_player.dart';

class VideoPage extends StatefulWidget {
  final String roomId;
  final bool isHost;

  const VideoPage({
    super.key,
    required this.roomId,
    required this.isHost,
  });

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  // IncomingVideoLocalServer? _localServer;
  final _hlsServer = HlsServer();
  Connection? _connection;
  late final _player = Player();
  // late final _videoController = VideoController(_player);
  VideoPlayerController? _videoPlayerController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _hlsServer.start().then((_) async {
      if (!mounted) {
        return;
      }
      _connect();
    });
    // _initLocalServer().then((_) {
    //   if (mounted) {
    //     _connect();
    //   }
    // });
  }

  @override
  void dispose() {
    stopRecording();
    // _localServer?.dispose();
    _hlsServer.dispose();
    _connection?.close();
    _player.dispose();
    super.dispose();
  }

  // Future<void> _initLocalServer() async {
  //   final server = await IncomingVideoLocalServer.create();
  //   if (!mounted) {
  //     server.dispose();
  //     return;
  //   }
  //   setState(() => _localServer = server);
  // }

  void _connect() async {
    final baseId = 'com_openup_${widget.roomId}';
    final myId = '${baseId}_${widget.isHost ? 'host' : 'client'}';
    final partnerId = '${baseId}_${!widget.isHost ? 'host' : 'client'}';
    final participant = Participant(myId);
    final Connection connection;
    if (widget.isHost) {
      connection = await participant.listen();
    } else {
      connection = await participant.connect(partnerId);
    }
    if (!mounted) {
      connection.close();
      return;
    }

    setState(() => _connection = connection);

    // Receive remote video
    final h265Stream =
        connection.binaryStream.map((e) => Uint8List.fromList(e));
    final result = await h265ToHls(h265Stream, _hlsServer.url);
    if (!mounted) {
      return;
    }
    if (!result) {
      return;
    }

    // Send local video
    final outputStream = await startRecording();
    outputStream
        ?.map((e) => Uint8List.fromList(e))
        .listen((data) => connection.sendUint8List(data));

    if (!mounted) {
      return;
    }
    setState(() => _ready = true);

    await Future.delayed(const Duration(seconds: 5));
    print('### Start video player');
    _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse('${_hlsServer.url}/stream.m3u8'))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
        }
      });

    // await _player.open(Media('${_hlsServer.url}/stream.m3u8'));
    // final localServer = _localServer;
    // if (localServer != null) {
    //   await _player.open(Media(localServer.url));
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Builder(
        builder: (context) {
          // final localServer = _localServer;
          // if (localServer == null) {
          //   return const SizedBox.shrink();
          // }
          return Stack(
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final controller = _videoPlayerController;
                    if (controller == null || !controller.value.isInitialized) {
                      return const SizedBox.shrink();
                    }
                    return VideoPlayer(controller);
                    // return Video(
                    //   controller: _videoController,
                    //   controls: (_) => const SizedBox.shrink(),
                    // );
                  },
                ),
              ),
              Positioned(
                left: 8,
                top: MediaQuery.of(context).padding.top + 8,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Room: ${widget.roomId} (${widget.isHost ? 'Host' : 'Client'})'),
                      Text(
                          'Status: ${_connection == null ? 'Waiting for connection' : !_ready ? 'Connecting' : 'Connected'}'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
