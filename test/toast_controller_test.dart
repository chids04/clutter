import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/shared/presentation/toast_controller.dart';

void main() {
  testWidgets('toast clears itself after its display window', (tester) async {
    final controller = ToastController()..show('saved');
    expect(controller.message, 'saved');

    await tester.pump(const Duration(seconds: 2));

    expect(controller.message, isNull);
    controller.dispose();
  });
}
