import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/app/app_shell.dart';
import 'package:clutter/app/theme.dart';
import 'package:clutter/features/incoming_audio/presentation/incoming_audio_scope.dart';
import 'package:clutter/shared/presentation/clutter_scroll_behavior.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

class ClutterApp extends StatelessWidget {
  const ClutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => SessionScrollPositionStore(),
      child: MaterialApp(
        title: 'clutter',
        themeMode: ThemeMode.dark,
        theme: darkTheme,
        scrollBehavior: const ClutterScrollBehavior(),
        home: const IncomingAudioScope(child: AppShell()),
      ),
    );
  }
}
