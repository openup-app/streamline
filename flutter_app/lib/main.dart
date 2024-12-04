import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:streamline/home_page.dart';
import 'package:streamline/video_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final _goRouter = _initRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flutter Demo',
      routerConfig: _goRouter,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
    );
  }

  GoRouter _initRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) {
            return const HomePage();
          },
        ),
        GoRoute(
          path: '/video/:roomId',
          name: 'video',
          builder: (context, state) {
            final roomId = state.pathParameters['roomId'] as String;
            final isHost = state.uri.queryParameters['isHost'] == 'true';
            return VideoPage(
              roomId: roomId,
              isHost: isHost,
            );
          },
        ),
      ],
    );
  }
}
