import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:streamline/incoming_video.dart';
import 'package:streamline/partcipant.dart';

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
  IncomingVideoLocalServer? _localServer;
  Connection? _connection;
  late final _player = Player();
  late final _videoController = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _initLocalServer().then((_) {
      if (mounted) {
        _connect();
      }
    });
  }

  @override
  void dispose() {
    _localServer?.dispose();
    _connection?.close();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initLocalServer() async {
    final server = await IncomingVideoLocalServer.create();
    if (!mounted) {
      server.dispose();
      return;
    }
    setState(() => _localServer = server);
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

    final h265Stream =
        connection.binaryStream.map((e) => Uint8List.fromList(e));
    final mp4Stream = await h265ToMp4(h265Stream);
    if (!mounted || mp4Stream == null) {
      return;
    }
    _localServer?.addStream(mp4Stream);
  }

  @override
  Widget build(BuildContext context) {
    final localServer = _localServer;
    if (localServer == null) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Video(
        controller: _videoController,
        controls: (_) => const SizedBox.shrink(),
      ),
    );
  }
}
