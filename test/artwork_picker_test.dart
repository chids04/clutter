import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:clutter/features/metadata_editor/data/platform_artwork_picker.dart';
import 'package:clutter/features/metadata_editor/domain/artwork_picker.dart';
import 'package:clutter/features/metadata_editor/presentation/artwork_selection.dart';

void main() {
  group('platform artwork picker', () {
    test(
      'uses the gallery picker with cover-friendly image settings',
      () async {
        final images = _RecordingImagePicker();
        final picker = PlatformArtworkPicker(
          imagePicker: images,
          platform: TargetPlatform.iOS,
        );

        final path = await picker.pick(ArtworkSource.gallery);

        expect(path, '/tmp/cover.jpg');
        expect(images.source, ImageSource.gallery);
        expect(images.maxWidth, 2048);
        expect(images.maxHeight, 2048);
        expect(images.imageQuality, 90);
        expect(images.requestFullMetadata, isFalse);
      },
    );

    test('uses the camera when requested on mobile', () async {
      final images = _RecordingImagePicker();
      final picker = PlatformArtworkPicker(
        imagePicker: images,
        platform: TargetPlatform.android,
      );

      await picker.pick(ArtworkSource.camera);

      expect(images.source, ImageSource.camera);
    });

    test('keeps the filtered file flow on desktop', () async {
      var filePickerCalls = 0;
      final picker = PlatformArtworkPicker(
        platform: TargetPlatform.macOS,
        desktopPicker: () async {
          filePickerCalls++;
          return FilePickerResult([
            PlatformFile(name: 'cover.png', size: 1, path: '/tmp/cover.png'),
          ]);
        },
      );

      final path = await picker.pick(ArtworkSource.files);

      expect(path, '/tmp/cover.png');
      expect(filePickerCalls, 1);
      expect(picker.usesNativeSources, isFalse);
    });
  });

  group('artwork source sheet', () {
    testWidgets('offers and routes camera roll selection', (tester) async {
      final picker = _FakeArtworkPicker(usesNativeSources: true);
      await _pumpPickerButton(tester, picker);

      await tester.tap(find.text('choose image'));
      await tester.pumpAndSettle();

      expect(find.text('camera roll'), findsOneWidget);
      expect(find.text('take a picture'), findsOneWidget);
      await tester.tap(find.text('camera roll'));
      await tester.pumpAndSettle();

      expect(picker.sources, [ArtworkSource.gallery]);
    });

    testWidgets('routes take a picture to the camera', (tester) async {
      final picker = _FakeArtworkPicker(usesNativeSources: true);
      await _pumpPickerButton(tester, picker);

      await tester.tap(find.text('choose image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('take a picture'));
      await tester.pumpAndSettle();

      expect(picker.sources, [ArtworkSource.camera]);
    });

    testWidgets('cancelling the source sheet does not invoke the picker', (
      tester,
    ) async {
      final picker = _FakeArtworkPicker(usesNativeSources: true);
      await _pumpPickerButton(tester, picker);

      await tester.tap(find.text('choose image'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(picker.sources, isEmpty);
    });

    testWidgets('desktop goes directly to the file picker', (tester) async {
      final picker = _FakeArtworkPicker(usesNativeSources: false);
      await _pumpPickerButton(tester, picker);

      await tester.tap(find.text('choose image'));
      await tester.pumpAndSettle();

      expect(picker.sources, [ArtworkSource.files]);
      expect(find.text('camera roll'), findsNothing);
    });

    testWidgets('permission failures show feedback without returning a path', (
      tester,
    ) async {
      final picker = _FakeArtworkPicker(
        usesNativeSources: true,
        error: PlatformException(code: 'camera_access_denied'),
      );
      await _pumpPickerButton(tester, picker);

      await tester.tap(find.text('choose image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('take a picture'));
      await tester.pumpAndSettle();

      expect(find.text('camera access was denied'), findsOneWidget);
      expect(find.text('no image selected'), findsOneWidget);
    });
  });
}

Future<void> _pumpPickerButton(
  WidgetTester tester,
  ArtworkPicker picker,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _PickerHarness(picker: picker)),
    ),
  );
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness({required this.picker});

  final ArtworkPicker picker;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  String? _path;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () async {
            final path = await chooseArtwork(context, picker: widget.picker);
            if (mounted) setState(() => _path = path);
          },
          child: const Text('choose image'),
        ),
        Text(_path ?? 'no image selected'),
      ],
    );
  }
}

class _FakeArtworkPicker implements ArtworkPicker {
  _FakeArtworkPicker({required this.usesNativeSources, this.error});

  @override
  final bool usesNativeSources;
  final Object? error;
  final List<ArtworkSource> sources = [];

  @override
  Future<String?> pick(ArtworkSource source) async {
    sources.add(source);
    if (error != null) throw error!;
    return '/tmp/cover.jpg';
  }
}

class _RecordingImagePicker extends ImagePicker {
  ImageSource? source;
  double? maxWidth;
  double? maxHeight;
  int? imageQuality;
  bool? requestFullMetadata;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    this.requestFullMetadata = requestFullMetadata;
    return XFile('/tmp/cover.jpg');
  }
}
