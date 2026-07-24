import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:clutter/app/clutter_app.dart';
import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/data/library_repository.dart';
import 'package:clutter/features/keybindings/application/keybinding_controller.dart';
import 'package:clutter/features/keybindings/data/keybinding_repository.dart';
import 'package:clutter/features/playback/infrastructure/audio_service.dart';
import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/data/sftp_credential_store.dart';
import 'package:clutter/features/remote_sources/data/sftp_repository.dart';
import 'package:clutter/shared/platform/desktop_platform.dart';
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
  final sftpRepository = RustSftpRepository(api);
  final keybindings = isDesktopPlatform
      ? KeybindingController(RustKeybindingRepository(api))
      : null;
  if (keybindings != null) await keybindings.load();

  runApp(
    MultiProvider(
      providers: [
        // provider owns these notifiers and disposes them with the app tree
        ChangeNotifierProvider(
          create: (_) => MusicLibrary(
            catalogRepository: repository,
            playbackPersistence: repository,
            player: audio,
            musicDir: music,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final controller = SftpController(
              repository: sftpRepository,
              credentials: const PlatformSftpCredentialStore(),
              onLibraryChanged: context
                  .read<MusicLibrary>()
                  .refreshAfterRemoteImport,
            );
            controller.hydrate();
            return controller;
          },
        ),
        if (keybindings != null)
          ChangeNotifierProvider(create: (_) => keybindings),
      ],
      child: const ClutterApp(),
    ),
  );
}
