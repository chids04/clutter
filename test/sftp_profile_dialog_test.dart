import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/presentation/sftp_profile_dialog.dart';
import 'package:clutter/src/rust/api/models.dart';

import 'sftp_controller_test.dart' show FakeSftpCredentials, FakeSftpRepository;

void main() {
  testWidgets('escape and system back dismiss the profile dialog', (
    tester,
  ) async {
    final controller = SftpController(
      repository: FakeSftpRepository(),
      credentials: FakeSftpCredentials(),
      onLibraryChanged: () async {},
    );
    await _pumpLauncher(tester, controller);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('add sftp server'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('add sftp server'), findsNothing);
    controller.dispose();
  });

  testWidgets('dismissing during fingerprint probe stops before trust', (
    tester,
  ) async {
    final repository = FakeSftpRepository()
      ..probeCompleter = Completer<String>();
    final controller = SftpController(
      repository: repository,
      credentials: FakeSftpCredentials(),
      onLibraryChanged: () async {},
    );
    await _pumpLauncher(tester, controller);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _fillNewProfile(tester);
    await tester.tap(find.text('connect'));
    await tester.pump();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    expect(find.text('add sftp server'), findsNothing);
    repository.probeCompleter!.complete('SHA256:new');
    await tester.pump();
    expect(repository.savedProfiles, isEmpty);
    controller.dispose();
  });

  testWidgets('cancel stays enabled while a trusted connection continues', (
    tester,
  ) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..testConnectionCompleter = Completer<void>();
    final credentials = FakeSftpCredentials();
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await _pumpLauncher(tester, controller, profile: _profile);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.text('connect'));
    await tester.pump();

    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'cancel'),
    );
    expect(cancel.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'cancel'));
    await tester.pumpAndSettle();
    expect(find.text('edit sftp server'), findsNothing);

    repository.testConnectionCompleter!.complete();
    await tester.pump();
    await tester.pump();
    expect(repository.savedProfiles, hasLength(1));
    expect(credentials.passwords['home'], 'secret');
    controller.dispose();
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  SftpController controller, {
  SftpProfileData? profile,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSftpProfileDialog(context, profile: profile),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _fillNewProfile(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(1), '100.64.0.1');
  await tester.enterText(fields.at(3), 'music');
  await tester.enterText(fields.at(5), 'secret');
}

const _profile = SftpProfileData(
  id: 'home',
  name: 'home',
  host: '100.64.0.1',
  port: 22,
  username: 'music',
  rootPath: '/music',
  hostKeyFingerprint: 'SHA256:test',
  isSelected: true,
);
