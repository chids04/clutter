import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/shared/presentation/clutter_scroll_behavior.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

void main() {
  testWidgets('vertical scrollbars use the left draggable pill treatment', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const ClutterScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 100,
            itemBuilder: (_, index) => Text('item $index'),
          ),
        ),
      ),
    );

    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.left);
    expect(scrollbar.thickness, 3);
    expect(scrollbar.radius, const Radius.circular(2));
    expect(scrollbar.thumbVisibility, isFalse);
    expect(scrollbar.trackVisibility, isFalse);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thumbColor?.a, closeTo(0.24, 0.001));

    controller.jumpTo(200);
    await tester.pump(const Duration(milliseconds: 100));
    final beforeThumbDrag = controller.offset;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(4, 65));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(const Offset(4, 65));
    await mouse.moveTo(const Offset(4, 215));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.offset, greaterThan(beforeThumbDrag));
  });

  testWidgets('horizontal scrollables do not receive a vertical pill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const ClutterScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemExtent: 100,
            itemCount: 20,
            itemBuilder: (_, index) => Text('item $index'),
          ),
        ),
      ),
    );

    expect(find.byType(RawScrollbar), findsNothing);
  });

  testWidgets('scroll offsets survive disposal and remain independent by id', (
    tester,
  ) async {
    final store = SessionScrollPositionStore();
    String? activeId = 'songs';
    ScrollController? activeController;
    late StateSetter rebuild;

    await tester.pumpWidget(
      Provider.value(
        value: store,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final id = activeId;
                if (id == null) return const SizedBox.shrink();
                return RememberedScrollPosition(
                  id: id,
                  onControllerChanged: (controller) =>
                      activeController = controller,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    itemExtent: 50,
                    itemCount: 100,
                    itemBuilder: (_, index) => Text('$id item $index'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    activeController!.jumpTo(480);
    await tester.pump();
    expect(activeController!.offset, 480);

    rebuild(() => activeId = null);
    await tester.pump();
    rebuild(() => activeId = 'albums');
    await tester.pump();
    expect(activeController!.offset, 0);

    activeController!.jumpTo(240);
    await tester.pump();
    rebuild(() => activeId = null);
    await tester.pump();
    rebuild(() => activeId = 'songs');
    await tester.pump();
    expect(activeController!.offset, 480);

    rebuild(() => activeId = null);
    await tester.pump();
    rebuild(() => activeId = 'albums');
    await tester.pump();
    expect(activeController!.offset, 240);
  });

  testWidgets('restored offsets clamp when content becomes shorter', (
    tester,
  ) async {
    final store = SessionScrollPositionStore()..remember('short-list', 900);
    ScrollController? controller;
    await tester.pumpWidget(
      Provider.value(
        value: store,
        child: MaterialApp(
          home: Scaffold(
            body: RememberedScrollPosition(
              id: 'short-list',
              onControllerChanged: (value) => controller = value,
              builder: (context, scrollController) => ListView.builder(
                controller: scrollController,
                itemExtent: 50,
                itemCount: 2,
                itemBuilder: (_, index) => Text('item $index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      controller!.offset,
      inInclusiveRange(0, controller!.position.maxScrollExtent),
    );
  });
}
