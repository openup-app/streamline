import 'dart:async';

import 'package:flutter/material.dart';
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
  final _hlsServer = HlsServer();
  Connection? _connection;
  VideoPlayerController? _videoPlayerController;
  bool _ready = false;
  StreamSubscription? _outputStreamSubscription;

  @override
  void initState() {
    super.initState();
    _hlsServer.start().then((_) async {
      if (!mounted) {
        return;
      }
      _connect();
    });
  }

  @override
  void dispose() {
    stopRecording();
    _hlsServer.dispose();
    _connection?.close();
    _outputStreamSubscription?.cancel();
    super.dispose();
  }

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
    await Future.delayed(const Duration(seconds: 3));

    // Receive remote video
    final h265Stream = connection.binaryStream;
    if (!await h265ToHls(h265Stream, _hlsServer.url)) {
      debugPrint('[VideoPage] Failed to start H265 to HLS conversion');
      return;
    }
    if (!mounted) {
      return;
    }

    // Send local video
    final outputStream = await startRecording();
    _outputStreamSubscription = outputStream?.listen(connection.sendUint8List);

    if (!mounted) {
      return;
    }
    setState(() => _ready = true);

    await _hlsServer.hasContent;
    debugPrint('[VideoPlayer] Start');
    final tempPlayDelay = Completer<void>();
    _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse('${_hlsServer.url}/stream.m3u8'))
      ..initialize().then((_) {
        if (mounted) {
          Future.delayed(const Duration(seconds: 2))
              .then(((_) => tempPlayDelay.complete()));
          setState(() {});
        }
      });

    await tempPlayDelay.future;
    if (mounted) {
      debugPrint('[VideoPlayer] Play');
      _videoPlayerController?.play();
    }
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
          return Stack(
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final controller = _videoPlayerController;
                    if (controller == null || !controller.value.isInitialized) {
                      return const SizedBox.shrink();
                    }
                    return AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    );
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
