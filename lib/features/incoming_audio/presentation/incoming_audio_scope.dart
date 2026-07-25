import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/incoming_audio/application/incoming_audio_controller.dart';
import 'package:clutter/features/incoming_audio/data/incoming_audio_service.dart';
import 'package:clutter/features/library/application/music_library.dart';

class IncomingAudioScope extends StatefulWidget {
  final Widget child;
  final IncomingAudioService? service;

  const IncomingAudioScope({super.key, required this.child, this.service});

  @override
  State<IncomingAudioScope> createState() => _IncomingAudioScopeState();
}

class _IncomingAudioScopeState extends State<IncomingAudioScope> {
  IncomingAudioController? _controller;

  bool get _enabled => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enabled || _controller != null) return;
    final library = context.read<MusicLibrary>();
    _controller = IncomingAudioController(
      service: widget.service ?? const MethodChannelIncomingAudioService(),
      importManagedAudio: library.importManagedAudio,
      showMessage: library.showToast,
    );
    unawaited(_controller!.start());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
