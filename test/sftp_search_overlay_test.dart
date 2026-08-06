import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clutter/app/theme.dart';
import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/presentation/sftp_browser.dart';
import 'package:clutter/shared/presentation/session_scroll_position.dart';
import 'package:clutter/src/rust/api/models.dart';

import 'sftp_controller_test.dart' show FakeSftpCredentials, FakeSftpRepository;

void main() {
  testWidgets('breadcrumb search finds every entry kind in the subtree', (
    tester,
  ) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..searchEntries = [
        _entry('folder', SftpEntryKindData.directory),
        _entry('folder/song.mp3', SftpEntryKindData.file),
        _entry('folder/cover.jpg', SftpEntryKindData.unsupported),
      ];
    final credentials = FakeSftpCredentials()..passwords['home'] = 'secret';
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await controller.hydrate();
    await _pumpBrowser(tester, controller);

    final search = find.byKey(const ValueKey('sftp-search-button'));
    expect(
      tester.getCenter(search).dx,
      lessThan(tester.getCenter(find.text('root')).dx),
    );
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sftp-search-field')),
      'folder',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repository.searchedPath, '');
    expect(repository.searchedQuery, 'folder');
    expect(
      find.byKey(const ValueKey('sftp-search-result-folder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sftp-search-result-folder/song.mp3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sftp-search-result-folder/cover.jpg')),
      findsOneWidget,
    );
    final unsupportedButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('sftp-search-download-folder/cover.jpg')),
    );
    expect(unsupportedButton.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('sftp-search-download-folder/song.mp3')),
    );
    await tester.pump();
    expect(repository.downloadedPaths, ['folder/song.mp3']);

    await tester.tap(find.byKey(const ValueKey('sftp-search-result-folder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sftp-search-panel')), findsNothing);
    expect(repository.browsedPaths.last, 'folder');

    await repository.closeDownloads();
    controller.dispose();
  });

  testWidgets('search reports when results are capped at 200', (tester) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..searchEntries = List.generate(
        201,
        (index) => _entry('match-$index.mp3', SftpEntryKindData.file),
      );
    final credentials = FakeSftpCredentials()..passwords['home'] = 'secret';
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await controller.hydrate();
    await _pumpBrowser(tester, controller);

    await tester.tap(find.byKey(const ValueKey('sftp-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sftp-search-field')),
      'match',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('showing the first 200 results'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('tab cycles actionable SFTP results and escape is layered', (
    tester,
  ) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..searchEntries = [
        _entry('folder', SftpEntryKindData.directory),
        _entry('folder/song.mp3', SftpEntryKindData.file),
        _entry('folder/cover.jpg', SftpEntryKindData.unsupported),
      ];
    final credentials = FakeSftpCredentials()..passwords['home'] = 'secret';
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await controller.hydrate();
    await _pumpBrowser(tester, controller);
    await _openAndSearch(tester, 'folder');
    final field = find.byKey(const ValueKey('sftp-search-field'));

    expect(_fieldHasPrimaryFocus(tester, field), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_focusedListTileKey(), const ValueKey('sftp-search-result-folder'));
    final folderKey = const ValueKey('sftp-search-result-folder');
    expect(
      _focusBorder(tester, folderKey).color,
      darkTheme.colorScheme.onSurface,
    );
    expect(_focusBorder(tester, folderKey).width, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      _focusedListTileKey(),
      const ValueKey('sftp-search-result-folder/song.mp3'),
    );
    expect(_focusBorder(tester, folderKey).color, Colors.transparent);
    expect(
      _focusBorder(
        tester,
        const ValueKey('sftp-search-result-folder/song.mp3'),
      ).color,
      darkTheme.colorScheme.onSurface,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_fieldHasPrimaryFocus(tester, field), isTrue);

    await _sendShiftTab(tester);
    expect(
      _focusedListTileKey(),
      const ValueKey('sftp-search-result-folder/song.mp3'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(repository.downloadedPaths, ['folder/song.mp3']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(field, findsOneWidget);
    expect(_fieldHasPrimaryFocus(tester, field), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);

    await repository.closeDownloads();
    controller.dispose();
  });

  testWidgets('enter on an SFTP folder opens it', (tester) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..searchEntries = [_entry('folder', SftpEntryKindData.directory)];
    final credentials = FakeSftpCredentials()..passwords['home'] = 'secret';
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await controller.hydrate();
    await _pumpBrowser(tester, controller);
    await _openAndSearch(tester, 'folder');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sftp-search-panel')), findsNothing);
    expect(repository.browsedPaths.last, 'folder');
    controller.dispose();
  });

  testWidgets('tab reaches and scrolls to off-screen SFTP results', (
    tester,
  ) async {
    final repository = FakeSftpRepository()
      ..profiles = [_profile]
      ..searchEntries = List.generate(
        20,
        (index) => _entry('match-$index.mp3', SftpEntryKindData.file),
      );
    final credentials = FakeSftpCredentials()..passwords['home'] = 'secret';
    final controller = SftpController(
      repository: repository,
      credentials: credentials,
      onLibraryChanged: () async {},
    );
    await controller.hydrate();
    await _pumpBrowser(tester, controller);
    await _openAndSearch(tester, 'match');

    for (var index = 0; index < 15; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pump();

    expect(
      _focusedListTileKey(),
      const ValueKey('sftp-search-result-match-14.mp3'),
    );
    final resultScrollView = find.descendant(
      of: find.byKey(const ValueKey('sftp-search-panel')),
      matching: find.byType(SingleChildScrollView),
    );
    final scrollable = find.descendant(
      of: resultScrollView,
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
    controller.dispose();
  });
}

Future<void> _openAndSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byKey(const ValueKey('sftp-search-button')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('sftp-search-field')),
    query,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

bool _fieldHasPrimaryFocus(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).focusNode!.hasPrimaryFocus;

Key? _focusedListTileKey() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<ListTile>()
    ?.key;

BorderSide _focusBorder(WidgetTester tester, Key resultKey) {
  final frame = find.ancestor(
    of: find.byKey(resultKey),
    matching: find.byType(AnimatedContainer),
  );
  final decoration =
      tester.widget<AnimatedContainer>(frame).foregroundDecoration!
          as BoxDecoration;
  return decoration.border!.top;
}

Future<void> _sendShiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Future<void> _pumpBrowser(
  WidgetTester tester,
  SftpController controller,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        Provider(create: (_) => SessionScrollPositionStore()),
      ],
      child: MaterialApp(
        theme: darkTheme,
        home: const Scaffold(body: SftpBrowser()),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

SftpEntryData _entry(String relativePath, SftpEntryKindData kind) =>
    SftpEntryData(
      name: relativePath.split('/').last,
      relativePath: relativePath,
      kind: kind,
      downloaded: false,
    );
