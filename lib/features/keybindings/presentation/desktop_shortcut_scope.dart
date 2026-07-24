import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/keybindings/application/keybinding_controller.dart';
import 'package:clutter/features/library/domain/library_entities.dart';

class DesktopShortcutScope extends StatelessWidget {
  final Widget child;
  final FutureOr<void> Function() onPlayPause;
  final FutureOr<void> Function(int seconds) onSeekBackward;
  final FutureOr<void> Function(int seconds) onSeekForward;
  final FutureOr<void> Function() onPreviousTrack;
  final FutureOr<void> Function() onNextTrack;
  final FutureOr<void> Function() onOmniSearch;

  const DesktopShortcutScope({
    super.key,
    required this.child,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    required this.onPreviousTrack,
    required this.onNextTrack,
    required this.onOmniSearch,
  });

  @override
  Widget build(BuildContext context) {
    final keybindings = context.watch<KeybindingController>();
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (_shouldIgnore(context)) return KeyEventResult.ignored;
        final action = keybindings.actionFor(event);
        if (action == null) return KeyEventResult.ignored;
        final isRepeat = event is KeyRepeatEvent;
        switch (action) {
          case KeybindingAction.playPause:
            if (!isRepeat) unawaited(Future.sync(onPlayPause));
          case KeybindingAction.seekBackward:
            unawaited(
              Future.sync(() => onSeekBackward(keybindings.seekStepSeconds)),
            );
          case KeybindingAction.seekForward:
            unawaited(
              Future.sync(() => onSeekForward(keybindings.seekStepSeconds)),
            );
          case KeybindingAction.previousTrack:
            if (!isRepeat) unawaited(Future.sync(onPreviousTrack));
          case KeybindingAction.nextTrack:
            if (!isRepeat) unawaited(Future.sync(onNextTrack));
          case KeybindingAction.omniSearch:
            if (!isRepeat) unawaited(Future.sync(onOmniSearch));
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }

  bool _shouldIgnore(BuildContext context) {
    // a route above the shell is usually a dialog, so never act behind it
    if (ModalRoute.of(context)?.isCurrent == false) return true;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
