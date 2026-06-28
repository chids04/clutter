import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/ui/views/c_view.dart';
import 'package:clutter/ui/widgets/confirm_dialog.dart';

class SettingsView extends CView {
  const SettingsView({super.key}) : super(viewTitle: 'settings');

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends CViewState<SettingsView> {
  @override
  Widget buildViewContent(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const <Widget>[Expanded(child: DirectoriesView())],
      ),
    );
  }
}

class DirectoriesView extends StatefulWidget {
  const DirectoriesView({super.key});

  @override
  State<DirectoriesView> createState() => _DirectoriesViewState();
}

class _DirectoriesViewState extends State<DirectoriesView> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            "Music Folders",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Consumer<MusicLibrary>(
            builder: (context, musicLibrary, _) => ElevatedButton.icon(
              icon: Icon(
                musicLibrary.usesSandboxMusicFolder
                    ? Icons.refresh
                    : Icons.folder_open,
              ),
              label: Text(
                musicLibrary.usesSandboxMusicFolder
                    ? "scan music folder"
                    : "choose music folder",
              ),
              onPressed: musicLibrary.isScanning
                  ? null
                  : () => musicLibrary.chooseOrScanMusicFolder(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Consumer<MusicLibrary>(
            builder: (context, musicLibrary, child) {
              if (musicLibrary.directories.isEmpty) {
                return Center(
                  child: Text(
                    musicLibrary.usesSandboxMusicFolder
                        ? "copy songs into the Music directory of the app's application directroy, then scan."
                        : "choose one music folder to scan.",
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: musicLibrary.directories.length,
                itemBuilder: (BuildContext context, int index) {
                  final dir = musicLibrary.directories[index];
                  return ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(
                      dir,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: "Rescan",
                          icon: const Icon(Icons.refresh),
                          onPressed: musicLibrary.isScanning
                              ? null
                              : () => musicLibrary.rescanDirectory(dir),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Remove directory"),
                                content: Text(
                                  "Remove \"$dir\" from the library? All songs indexed from this path will be removed. Files on disk will not be deleted.",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text("cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text(
                                      "Remove",
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await musicLibrary.removeDirectory(dir);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Consumer<MusicLibrary>(
            builder: (context, musicLibrary, _) => ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              label: const Text(
                "Reset Database",
                style: TextStyle(color: Colors.redAccent),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final ok = await confirmDestructive(
                  context,
                  title: "Reset database",
                  message:
                      "All songs, albums, playlists, and scan history will be removed from the library. Files on disk will not be deleted.",
                  actionLabel: "Reset",
                );
                if (ok && context.mounted) {
                  await musicLibrary.resetLibrary();
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
