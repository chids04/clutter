import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/library/application/music_library.dart';
import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/features/library/presentation/library_view.dart';
import 'package:clutter/features/settings/presentation/settings_view.dart';
import 'package:clutter/features/search/presentation/search_view.dart';
import 'package:clutter/features/playback/presentation/media_bar.dart';
import 'package:clutter/features/quick_play/presentation/quick_play_sidebar.dart';
import 'package:clutter/features/search/presentation/omni_search_overlay.dart';
import 'package:clutter/features/keybindings/presentation/desktop_shortcut_scope.dart';
import 'package:clutter/shared/platform/desktop_platform.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isOmniSearchOpen = false;
  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'root-shortcuts');
  final GlobalKey<NavigatorState> _libraryNavigatorKey =
      GlobalKey<NavigatorState>();
  final ValueNotifier<LibraryPage> _libraryPage = ValueNotifier(
    LibraryPage.songs,
  );

  @override
  void initState() {
    super.initState();
    _scheduleShortcutFocus();
  }

  void _scheduleShortcutFocus() {
    // focus requests need a rendered node, so schedule them after this frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedIndex != 0 || _isOmniSearchOpen) return;
      _shortcutFocusNode.requestFocus();
    });
  }

  void _openLibraryPage(LibraryPage page) {
    _libraryPage.value = page;
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    _scheduleShortcutFocus();
  }

  Future<void> _openOmniSearch() async {
    if (_selectedIndex != 0 || _isOmniSearchOpen) return;
    _isOmniSearchOpen = true;
    try {
      await showOmniSearchOverlay(
        context: context,
        libraryNavigatorKey: _libraryNavigatorKey,
      );
    } finally {
      _isOmniSearchOpen = false;
      _scheduleShortcutFocus();
    }
  }

  Future<void> _openOmniSearchFromLongPress() async {
    if (_selectedIndex != 0 || _isOmniSearchOpen) return;
    if (Platform.isIOS || Platform.isMacOS) {
      await HapticFeedback.mediumImpact();
    }
    await _openOmniSearch();
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _scheduleShortcutFocus();
    }
  }

  @override
  void dispose() {
    // state objects own these listenables and must release them with the route
    _shortcutFocusNode.dispose();
    _libraryPage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widgetOptions = <Widget>[
      _TabNavigator(
        navigatorKey: _libraryNavigatorKey,
        child: LibraryView(
          currentPageListenable: _libraryPage,
          onPageChanged: _openLibraryPage,
        ),
      ),
      _TabNavigator(child: const SearchView()),
      _TabNavigator(child: const SettingsView()),
    ];

    final content = Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      skipTraversal: true,
      child: Scaffold(
        body: QuickPlaySidebar(
          child: IndexedStack(index: _selectedIndex, children: widgetOptions),
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
            MediaBar(
              activeLibraryPageListenable: _libraryPage,
              onLibraryPageSelected: _openLibraryPage,
            ),

            _SearchLongPressBottomNav(
              onSearchLongPress: _openOmniSearchFromLongPress,
              child: BottomNavigationBar(
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
                onTap: _selectTab,
              ),
            ),
          ],
        ),
      ),
    );
    if (!isDesktopPlatform) return content;
    final library = context.read<MusicLibrary>();
    return DesktopShortcutScope(
      onPlayPause: library.togglePlay,
      onPreviousTrack: library.playPrevious,
      onNextTrack: library.playNext,
      onOmniSearch: _openOmniSearch,
      child: content,
    );
  }
}

class _SearchLongPressBottomNav extends StatelessWidget {
  final Widget child;
  final VoidCallback onSearchLongPress;

  const _SearchLongPressBottomNav({
    required this.child,
    required this.onSearchLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 350),
              ),
              (recognizer) {
                recognizer.onLongPressStart = (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null || !box.hasSize) return;
                  final itemWidth = box.size.width / 3;
                  final pressedIndex = (details.localPosition.dx / itemWidth)
                      .floor();
                  if (pressedIndex == 1) {
                    onSearchLongPress();
                  }
                };
              },
            ),
      },
      child: child,
    );
  }
}

/// owns a `navigator` per bottom-nav tab so `navigator.push` calls from within
/// a tab (e.g., into `albumdetailview`) stack inside the tab's body and leave
/// the mediabar + bottomnavigationbar from the root `scaffold` visible.
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget child;
  const _TabNavigator({this.navigatorKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
    );
  }
}

/// small transient message pill rendered just above the mediabar. watches
/// `musiclibrary.toastmessage`, which clears itself on a 2 s timer.
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: theme.dividerTheme.color ?? Colors.transparent,
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
