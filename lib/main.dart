import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/utils/colors.dart';
import 'package:clutter/ui/views/library_view.dart';
import 'package:clutter/ui/views/settings_view.dart';
import 'package:clutter/ui/views/playlist_view.dart';
import 'package:clutter/ui/views/mediabar.dart';
import 'package:clutter/ui/views/quick_play_sidebar.dart';
import 'package:clutter/services/audio_service_helper.dart';

import 'package:clutter/src/rust/api/scanner.dart';
import 'package:clutter/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  final audioHandler = await initAudioService();

  final appDir = await getApplicationDocumentsDirectory();
  final clutterDir = p.join(appDir.path, 'clutter');
  final dbPath = p.join(clutterDir, 'library.db');
  final coversDir = p.join(clutterDir, 'covers');

  final library = await CLibrary.init(
    dbPath: dbPath,
    coversDir: coversDir,
    baseDir: appDir.path,
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => MusicLibrary(library: library, handler: audioHandler),
      child: const MyApp(),
    ),
  );
}

class ThemeManager extends ChangeNotifier {
  final (Color, Color) containerBackground = (
    const Color(0xFF212021),
    const Color(0xFFFFFFFF),
  );
  final (Color, Color) containerBorder = (
    const Color(0xFF2B2A2B),
    const Color(0xFFE0E0E0),
  );
}

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.darkBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.darkBackground,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.darkBackground,
    selectedItemColor: AppColors.accent,
    unselectedItemColor: AppColors.textSecondary,
    elevation: 0,
    type: BottomNavigationBarType.fixed,
  ),
  dividerTheme: const DividerThemeData(
    color: AppColors.darkDivider,
    thickness: 1,
    space: 1,
  ),
  colorScheme: const ColorScheme.dark(
    surface: AppColors.darkSurface,
    onSurface: AppColors.textPrimary,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.darkSurfaceSecondary,
    onSecondary: AppColors.textPrimary,
    error: AppColors.errorRed,
  ),
  listTileTheme: const ListTileThemeData(
    textColor: AppColors.textPrimary,
    iconColor: AppColors.textSecondary,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.darkSurfaceSecondary,
      foregroundColor: AppColors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'clutter',
      themeMode: ThemeMode.dark,
      theme: darkTheme,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  static final List<Widget> _widgetOptions = <Widget>[
    _TabNavigator(child: const LibraryView()),
    _TabNavigator(child: const SearchView()),
    _TabNavigator(child: const SettingsView()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuickPlaySidebar(
        child: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      ),

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color:
                      Theme.of(context).dividerTheme.color ??
                      Colors.transparent,
                ),
              ),
            ),
          ),
          const _ToastPill(),
          const MediaBar(),

          BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music),
                label: 'library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'settings',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
        ],
      ),
    );
  }
}

/// Owns a `Navigator` per bottom-nav tab so `Navigator.push` calls from within
/// a tab (e.g., into `AlbumDetailView`) stack inside the tab's body and leave
/// the MediaBar + BottomNavigationBar from the root `Scaffold` visible.
class _TabNavigator extends StatelessWidget {
  final Widget child;
  const _TabNavigator({required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    );
  }
}

/// Small transient message pill rendered just above the MediaBar. Watches
/// `MusicLibrary.toastMessage`, which clears itself on a 2 s timer.
class _ToastPill extends StatelessWidget {
  const _ToastPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<MusicLibrary>(
      builder: (context, lib, _) {
        final message = lib.toastMessage;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: message == null
              ? const SizedBox(key: ValueKey('toast-empty'), height: 0)
              : Padding(
                  key: const ValueKey('toast-visible'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: theme.dividerTheme.color ??
                              Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
