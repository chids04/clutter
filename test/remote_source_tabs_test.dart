import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/search/presentation/search_view.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';

import 'sftp_controller_test.dart' show FakeSftpCredentials, FakeSftpRepository;

void main() {
  testWidgets('the sftp source is a compact active tab below search', (
    tester,
  ) async {
    final controller = SftpController(
      repository: FakeSftpRepository(),
      credentials: FakeSftpCredentials(),
      onLibraryChanged: () async {},
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          Provider(create: (_) => SessionScrollPositionStore()),
        ],
        child: const MaterialApp(home: SearchView()),
      ),
    );

    expect(find.text('search'), findsOneWidget);
    expect(find.text('sftp'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote-source-sftp-active')),
      findsOneWidget,
    );
    controller.dispose();
  });
}
