import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Keeps scroll offsets in memory for the lifetime of the application.
class SessionScrollPositionStore {
  final Map<String, double> _positions = {};

  double positionFor(String id) => _positions[id] ?? 0;

  void remember(String id, double position) {
    _positions[id] = position;
  }
}

typedef RememberedScrollBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// Owns a scroll controller whose offset survives disposal and recreation.
class RememberedScrollPosition extends StatefulWidget {
  final String id;
  final RememberedScrollBuilder builder;
  final ValueChanged<ScrollController>? onControllerChanged;

  const RememberedScrollPosition({
    super.key,
    required this.id,
    required this.builder,
    this.onControllerChanged,
  });

  @override
  State<RememberedScrollPosition> createState() =>
      _RememberedScrollPositionState();
}

class _RememberedScrollPositionState extends State<RememberedScrollPosition> {
  late SessionScrollPositionStore _store;
  late ScrollController _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _store = context.read<SessionScrollPositionStore>();
    _controller = _createController(widget.id);
    _initialized = true;
    widget.onControllerChanged?.call(_controller);
  }

  @override
  void didUpdateWidget(RememberedScrollPosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    _remember(oldWidget.id);
    _controller.dispose();
    _controller = _createController(widget.id);
    widget.onControllerChanged?.call(_controller);
  }

  ScrollController _createController(String id) {
    final controller = ScrollController(
      initialScrollOffset: _store.positionFor(id),
      keepScrollOffset: false,
    );
    controller.addListener(_rememberCurrentPosition);
    return controller;
  }

  void _rememberCurrentPosition() {
    _remember(widget.id);
  }

  void _remember(String id) {
    if (_controller.hasClients) {
      _store.remember(id, _controller.offset);
    }
  }

  void _scheduleClampToContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      if (!position.hasContentDimensions) return;
      final clamped = _controller.offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (clamped != _controller.offset) {
        _controller.jumpTo(clamped);
      }
    });
  }

  @override
  void dispose() {
    if (_initialized) {
      _remember(widget.id);
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleClampToContent();
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleClampToContent();
        return false;
      },
      child: widget.builder(context, _controller),
    );
  }
}
