import 'package:flutter/material.dart';

import 'package:clutter/app/app_shell.dart';
import 'package:clutter/app/theme.dart';
import 'package:clutter/features/incoming_audio/presentation/incoming_audio_scope.dart';

class ClutterApp extends StatelessWidget {
  const ClutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'clutter',
      themeMode: ThemeMode.dark,
      theme: darkTheme,
      home: const IncomingAudioScope(child: AppShell()),
    );
  }
}
