import 'package:flutter_test/flutter_test.dart';
import 'package:clutter/app/clutter_app.dart';
import 'package:clutter/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('app widget can be constructed after rust starts', () {
    expect(const ClutterApp(), isA<ClutterApp>());
  });
}
