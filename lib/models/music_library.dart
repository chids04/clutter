import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:metatagger/metatagger.dart';

import 'package:clutter/utils/log.dart';
import 'package:clutter/src/rust/api/scanner.dart';

// song model is now immutable. added copywith just in case we need to update a title later.
class Song {
  final String id;
  final String title;
  final List<String> artists;
  final String albumId;
  final int trackNum;
  final String path;
  final CoverImage? coverImg;

  const Song({
    required this.id,
    required this.title,
    required this.artists,
    required this.albumId,
    required this.trackNum,
    required this.path,
    required this.coverImg,
  });

  Song copyWith({
    String? id,
    String? title,
    List<String>? artists,
    String? albumId,
    String? path,
    int? trackNum,
    CoverImage? coverImg,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      albumId: albumId ?? this.albumId,
      path: path ?? this.path,
      trackNum: trackNum ?? this.trackNum,
      coverImg: coverImg ?? this.coverImg,
    );
  }
}

class CoverImage {
  final Uint8List bytes;
  final String mimeType;

  const CoverImage({required this.bytes, required this.mimeType});
}

class Album {
  final String id;
  final String name;
  final List<String> artists;
  final Set<String> songs;

  const Album({
    required this.id,
    required this.name,
    required this.artists,
    required this.songs,
  });

  Album copyWith({required Song songs}) {
    return Album(id: id, name: name, artists: artists, songs: this.songs);
  }
}

class Artist {
  final String id;
  final String name;
  const Artist({required this.id, required this.name});
}

// this is the main state object. it holds everything and doesn't change itself.
class MusicLibraryState {
  final List<String> directories;
  final Map<String, Song> songs;
  final Map<String, Album> albums;
  final Map<String, Artist> artists;
  final String? playingId;
  final bool isScanning;
  final bool isPlaying;

  const MusicLibraryState({
    this.directories = const [],
    this.songs = const {},
    this.artists = const {},
    this.albums = const {},
    this.playingId,
    this.isScanning = false,
    this.isPlaying = false,
  });

  MusicLibraryState copyWith({
    List<String>? directories,
    Map<String, Song>? songs,
    Map<String, Artist>? artists,
    Map<String, Album>? albums,
    String? playingId,
    bool? isScanning,
    bool? isPlaying,
  }) {
    return MusicLibraryState(
      directories: directories ?? this.directories,
      songs: songs ?? this.songs,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      playingId: playingId ?? this.playingId,
      isScanning: isScanning ?? this.isScanning,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

class MusicLibrary extends ChangeNotifier {
  // private state holder
  MusicLibraryState _state = const MusicLibraryState();

  // state (from rust)
  CLibrary cLibrary = CLibrary();

  // getters for the ui to consume. wrapping in unmodifiable views
  UnmodifiableListView<String> get directories =>
      UnmodifiableListView(_state.directories);
  UnmodifiableListView<Song> get songs =>
      UnmodifiableListView(_state.songs.values);

  // getters for immutable state
  String? get playingId => _state.playingId;
  bool get isScanning => _state.isScanning;
  bool get isPlaying => _state.isPlaying;
  Song? songDetails(String id) => _state.songs[id];

  CSongDart? get currentSong => cLibrary.currentSong();

  // getters for mutable state
  Duration? get playerDuration => _duration;
  Duration? get playerPosition => _position;
  final List<StreamSubscription> _subscriptions = [];
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
  final songQueue = Queue<String>();
  Duration? _duration;
  Duration? _position;

  String getArtistStr(String songID) {
    if (_state.songs[songID] == null) {
      return "unknown artists";
    }
    if (_state.songs[songID]!.artists.length == 1) {
      var artistID = _state.songs[songID]!.artists[0];

      if (_state.artists[artistID] == null) {
        return "unknown artist";
      }

      return _state.artists[artistID]!.name;
    } else {
      return _state.songs[songID]!.artists
          .map((artistId) => _state.artists[artistId])
          .toList()
          .join(",");
    }
  }

  MusicLibrary([String? initPath]) {
    if (initPath != null && initPath != "") {
      addDirectory(initPath);
    }
    initPlaybackEvents();
  }

  void initPlaybackEvents() {
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (songQueue.isEmpty) {
          _position = Duration(milliseconds: 0);
          _state = _state.copyWith(isPlaying: false);
        } else {
          onPlaySong(songQueue.removeFirst());
        }
      }),
    );

    _subscriptions.add(
      _player.onDurationChanged.listen((Duration d) {
        _duration = d;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onPositionChanged.listen((Duration d) {
        _position = d;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.onPlayerStateChanged.listen((PlayerState s) => {}),
    );
  }

  @override
  void dispose() {
    for (var s in _subscriptions) {
      s.cancel();
    }

    super.dispose();
  }

  void setPlayerPosition(double value) {
    var newPos = Duration(milliseconds: value.toInt());
    _player.seek(newPos).then((_) {
      _position = newPos;
      notifyListeners();
    });
  }

  void onPlaySong(String id) async {
    //_state = _state.copyWith(playingId: id, isPlaying: true);

    // if (currentSong == null) {
    //   Log.w("Song not found in in-memory hash map");
    //   return;
    // }
    var song = await cLibrary.playSong(id: id);

    if (song == null) {
      Log.e("SONG $id IS NULL");
      return;
    }

    await _player.play(DeviceFileSource(song.path));
    _duration = await _player.getDuration();

    Log.d("playing new song");
    notifyListeners();
  }

  void togglePlay() {
    if (_state.isPlaying == false) {
      _player.resume();
    } else {
      _player.pause();
    }

    _state = _state.copyWith(isPlaying: !_state.isPlaying);

    notifyListeners();
  }

  void pause() {
    _player.pause();
    _state = _state.copyWith(isPlaying: false);
    notifyListeners();
  }

  void resume() {
    if (currentSong == null) {
      return;
    }

    _player.resume();
    _state = _state.copyWith(isPlaying: true);
  }

  void queueSong(String id) {
    var song = _state.songs[id];

    if (song == null) {
      return;
    }

    songQueue.addLast(song.id);
  }

  // push a new dir into the list and start the scan
  void addDirectory(String directory) {
    final updatedDirs = List<String>.from(_state.directories)..add(directory);

    _state = _state.copyWith(directories: updatedDirs, isScanning: true);
    notifyListeners();

    scanForMusic(directory).whenComplete(() {
      Log.d("finished scanning for music");
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    });
  }

  void removeDirectory(String directory) {
    final updatedDirs = List<String>.from(_state.directories)
      ..remove(directory);
    _state = _state.copyWith(directories: updatedDirs);
    notifyListeners();
    // In a real app, we might want to also remove songs that were in this directory.
    // For now, just removing the directory from the list as requested.
  }

  Future<void> scanForMusic(String path) async {
    final dir = Directory(path);

    await for (var entity in dir.list(recursive: true, followLinks: true)) {
      final songPath = entity.absolute.path;

      if (await FileSystemEntity.isFile(songPath) &&
          songPath.endsWith(".mp3")) {
        Log.d("found mp3 file $songPath, beginning parsing");

        extractMetadata(
          library_: cLibrary,
          path: songPath,
          config: Config(isDeezer: true),
        );
      }
    }

    notifyListeners();

    // get the list of songs from the rust backend
  }

  Future<Song?> parseMetadata(String path) async {
    return null;

    // var metadata = await MetadataGod.readMetadata(file: path);

    // var id = Uuid().v4();

    // var tagger = MetaTagger();

    // // some id3 tags store the artists as a / seperated list
    // // apparently id3v2.4 can store things

    // var title = metadata.title ?? p.basename(path);

    // if (metadata.artist != null) {
    //   Log.d("found artists: ${metadata.artist}");
    // }

    // final artistsList = metadata.artist?.split('/') ?? ["unknown artist"];
    // Log.d("raw artists ${metadata.albumArtist}");

    // final List<String> artistIDs = artistsList
    //     .map((a) => updateArtist(artistName: a))
    //     .toList();

    // final albumName = metadata.album ?? "unknown album";
    // // right now we dont actually split do string splits
    // final albumArtists = [
    //   metadata.albumArtist ?? path,
    // ].map((s) => updateArtist(artistName: s)).toList();

    // final albumId = "$albumName,${albumArtists.join(",")}";

    // updateAlbum(
    //   albumID: albumId,
    //   albumName: albumName,
    //   albumArtists: albumArtists,
    //   songID: id,
    // );

    // CoverImage? img;
    // if (metadata.picture != null) {
    //   img = CoverImage(
    //     bytes: metadata.picture!.data,
    //     mimeType: metadata.picture!.mimeType,
    //   );

    //   Log.d("found cover art");
    // }

    // return Song(
    //   id: const Uuid().v4(),
    //   title: title,
    //   artists: artistIDs,
    //   albumId: albumId,
    //   path: path,
    //   trackNum: metadata.trackNumber ?? 1,
    //   coverImg: img,
    // );
  }

  // adds song id to existing album or creates a new album and adds to state
  void updateAlbum({
    required String albumID,
    required String albumName,
    required List<String> albumArtists,
    required String songID,
  }) {
    if (_state.albums.containsKey(albumID)) {
      var albums = Map<String, Album>.of(_state.albums);
      albums[albumID]!.songs.add(songID);
      _state = _state.copyWith(albums: albums);
    } else {
      var album = Album(
        id: albumID,
        name: albumName,
        artists: albumArtists,
        songs: {songID},
      );
      var albums = Map<String, Album>.of(_state.albums);
      albums[albumID] = album;

      _state = _state.copyWith(albums: albums);
    }
  }

  String updateArtist({required String artistName}) {
    if (!_state.artists.containsKey(artistName)) {
      var id = Uuid().v4();
      var artist = Artist(id: id, name: artistName);
      var newArtists = Map<String, Artist>.of(_state.artists);
      newArtists[id] = artist;

      _state.copyWith(artists: newArtists);
      return id;
    } else {
      return _state.artists[artistName]!.id;
    }
  }

  void openFilePicker() async {
    try {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: "select directory to scan for music",
      );

      if (directory != null) {
        addDirectory(directory);
      }
    } on PlatformException catch (e) {
      Log.e("unsupported file picker op", e);
    }
  }
}
