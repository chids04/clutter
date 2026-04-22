import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/utils/colors.dart';
import 'package:clutter/ui/views/library_view.dart';
import 'package:clutter/ui/views/settings_view.dart';
import 'package:clutter/ui/views/playlist_view.dart';
import 'package:clutter/ui/views/mediabar.dart';

import 'package:clutter/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  runApp(
    ChangeNotifierProvider(
      // probably should add this to assets soon
      create: (context) => MusicLibrary(
        "/Users/c/Documents/music-player-projects/clutter/test/Playboi Carti - Whole Lotta Red",
      ),
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
    selectedItemColor: AppColors.accentBlue,
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
    primary: AppColors.accentBlue,
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

  static const List<Widget> _widgetOptions = <Widget>[
    LibraryView(),
    SearchView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),

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
