import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/models/music_library.dart';
import 'package:clutter/ui/views/c_view.dart';

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
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text("Add Directory"),
            onPressed: () {
              var library = Provider.of<MusicLibrary>(context, listen: false);
              library.openFilePicker();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Consumer<MusicLibrary>(
            builder: (context, musicLibrary, child) {
              if (musicLibrary.directories.isEmpty) {
                return const Center(child: Text("No directories added yet."));
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
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () {
                        musicLibrary.removeDirectory(dir);
                      },
                    ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(),
              );
            },
          ),
        ),
      ],
    );
  }
}
