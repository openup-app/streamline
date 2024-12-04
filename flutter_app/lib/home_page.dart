import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calling Demo'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  hintText: 'Room ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return FilledButton(
                    onPressed: _controller.text.isEmpty
                        ? null
                        : () =>
                            _joinRoom(_controller.text.trim(), isHost: true),
                    child: const Text('Create'),
                  );
                },
              ),
              const Center(
                child: Text('or'),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return FilledButton(
                    onPressed: _controller.text.isEmpty
                        ? null
                        : () =>
                            _joinRoom(_controller.text.trim(), isHost: false),
                    child: const Text('Join'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _joinRoom(String roomId, {required bool isHost}) {
    context.pushNamed(
      'video',
      pathParameters: {'roomId': roomId},
      queryParameters: {'isHost': isHost ? 'true' : 'false'},
    );
  }
}
