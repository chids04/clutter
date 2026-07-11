import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:clutter/app/clutter_app.dart';
import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/playback/infrastructure/audio_service.dart';
import 'package:clutter/src/rust/api/library.dart';
import 'package:clutter/src/rust/frb_generated.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  final audio = await initAudioService();
  final documents = await getApplicationDocumentsDirectory();
  final clutter = p.join(documents.path, 'clutter');
  final music = p.join(documents.path, 'Music');
  await Directory(music).create(recursive: true);

  final api = await LibraryApi.init(
    dbPath: p.join(clutter, 'library.db'),
    coversDir: p.join(clutter, 'covers'),
    baseDir: documents.path,
  );
  final repository = RustLibraryRepository(api);

  runApp(
    ChangeNotifierProvider(
      // provider owns this notifier, so it will also call dispose for us
      create: (_) => MusicLibrary(
        catalogRepository: repository,
        playbackPersistence: repository,
        player: audio,
        musicDir: music,
      ),
      child: const ClutterApp(),
    ),
  );
}
