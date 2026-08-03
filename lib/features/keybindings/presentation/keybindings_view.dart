import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/keybindings/application/keybinding_controller.dart';
import 'package:clutter/features/keybindings/domain/key_code_codec.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/presentation/confirm_dialog.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

class KeybindingsView extends StatefulWidget {
  const KeybindingsView({super.key});

  @override
  State<KeybindingsView> createState() => _KeybindingsViewState();
}

class _KeybindingsViewState extends State<KeybindingsView> {
  final FocusNode _recorderFocus = FocusNode(debugLabel: 'keybinding-recorder');
  KeybindingAction? _recording;
  int? _seekStepDraft;
  bool _savingSeekStep = false;

  @override
  void dispose() {
    _recorderFocus.dispose();
    super.dispose();
  }

  void _startRecording(KeybindingAction action) {
    setState(() => _recording = action);
    // the recorder must own focus before the next hardware event bubbles up
    _recorderFocus.requestFocus();
  }

  KeyEventResult _record(KeyEvent event) {
    final action = _recording;
    if (action == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _recording = null);
      return KeyEventResult.handled;
    }
    final binding = KeyCodeCodec.capture(action, event);
    if (binding == null) return KeyEventResult.handled;
    _save(binding);
    return KeyEventResult.handled;
  }

  Future<void> _save(KeybindingData binding) async {
    try {
      await context.read<KeybindingController>().update(binding);
      if (!mounted) return;
      setState(() => _recording = null);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _clear(KeybindingAction action) async {
    try {
      await context.read<KeybindingController>().clear(action);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    final message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('_', ' ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reset() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'reset keyboard shortcuts?',
      message: 'all desktop shortcuts will return to their defaults.',
      actionLabel: 'reset',
    );
    if (!confirmed || !mounted) return;
    await context.read<KeybindingController>().reset();
  }

  Future<void> _saveSeekStep(double value) async {
    final seconds = value.round();
    setState(() => _savingSeekStep = true);
    try {
      await context.read<KeybindingController>().updateSeekStepSeconds(seconds);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _savingSeekStep = false;
          _seekStepDraft = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _recorderFocus,
      onKeyEvent: (node, event) => _record(event),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('keyboard shortcuts'),
          actions: [
            TextButton(onPressed: _reset, child: const Text('reset defaults')),
          ],
        ),
        body: Consumer<KeybindingController>(
          builder: (context, controller, _) {
            if (controller.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final seekStep = _seekStepDraft ?? controller.seekStepSeconds;
            return RememberedScrollPosition(
              id: 'settings:keybindings',
              builder: (context, scrollController) => ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: KeybindingAction.values.length + 1,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.fast_forward),
                      title: const Text('seek interval'),
                      subtitle: Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: seekStep.toDouble(),
                              min: 1,
                              max: 30,
                              divisions: 29,
                              label: '$seekStep seconds',
                              onChanged: _savingSeekStep
                                  ? null
                                  : (value) => setState(
                                      () => _seekStepDraft = value.round(),
                                    ),
                              onChangeEnd: _savingSeekStep
                                  ? null
                                  : _saveSeekStep,
                            ),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text(
                              '$seekStep seconds',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final action = KeybindingAction.values[index - 1];
                  final recording = _recording == action;
                  return ListTile(
                    title: Text(_actionLabel(action)),
                    subtitle: Text(
                      recording
                          ? 'press a shortcut, or escape to cancel'
                          : controller.labelFor(action),
                    ),
                    leading: Icon(_actionIcon(action)),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'clear shortcut',
                          onPressed: () => _clear(action),
                          icon: const Icon(Icons.backspace_outlined),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _startRecording(action),
                          child: Text(recording ? 'listening…' : 'record'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  String _actionLabel(KeybindingAction action) => switch (action) {
    KeybindingAction.playPause => 'play / pause',
    KeybindingAction.seekBackward => 'seek backward',
    KeybindingAction.seekForward => 'seek forward',
    KeybindingAction.previousTrack => 'previous track',
    KeybindingAction.nextTrack => 'next track',
    KeybindingAction.omniSearch => 'omni search',
  };

  IconData _actionIcon(KeybindingAction action) => switch (action) {
    KeybindingAction.playPause => Icons.play_arrow,
    KeybindingAction.seekBackward => Icons.replay_5,
    KeybindingAction.seekForward => Icons.forward_5,
    KeybindingAction.previousTrack => Icons.skip_previous,
    KeybindingAction.nextTrack => Icons.skip_next,
    KeybindingAction.omniSearch => Icons.search,
  };
}
