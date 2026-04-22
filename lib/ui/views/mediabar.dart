import 'package:clutter/models/music_library.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MediaBar extends StatefulWidget {
  const MediaBar({super.key});

  @override
  State<MediaBar> createState() => _MediaBarState();
}

class _MediaBarState extends State<MediaBar> {
  Widget getCoverImg(CoverImage? img) {
    return img == null
        ? SvgPicture.asset(
            "assets/note.svg",
            width: 50,
            height: 50,
            colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
          )
        : Image.memory(
            img.bytes,
            width: 50,
            height: 50,
            cacheWidth: 300,
            cacheHeight: 300,
          );
  }

  String formatDuration(Duration? duration) {
    if (duration == null) {
      return "";
    }
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicLibrary>(
      builder: (context, musicLibrary, child) {
        return Padding(
          padding: EdgeInsets.only(bottom: 5, left: 7),
          child: Column(
            children: [
              Row(
                children: [
                  getCoverImg(musicLibrary.currentSong?.coverImg),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MediaQuery.of(context).size.width < 600
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: Icon(Icons.skip_previous, size: 30),
                                onPressed: () => {},
                              ),
                              IconButton(
                                icon: musicLibrary.isPlaying
                                    ? Icon(Icons.pause, size: 30)
                                    : Icon(Icons.play_arrow, size: 30),
                                onPressed: () => musicLibrary.togglePlay(),
                              ),
                              IconButton(
                                icon: Icon(Icons.skip_next, size: 30),
                                onPressed: () => {},
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              SizedBox(
                                width: 47,
                                child: Text(
                                  formatDuration(musicLibrary.playerPosition),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value:
                                      musicLibrary
                                          .playerPosition
                                          ?.inMilliseconds
                                          .toDouble() ??
                                      0,
                                  max:
                                      musicLibrary
                                          .playerDuration
                                          ?.inMilliseconds
                                          .toDouble() ??
                                      0,

                                  onChangeStart: (_) {
                                    musicLibrary.pause();
                                  },

                                  onChangeEnd: (_) {
                                    musicLibrary.resume();
                                  },
                                  onChanged: (double value) =>
                                      musicLibrary.setPlayerPosition(value),
                                ),
                              ),
                              SizedBox(
                                width: 47,
                                child: Text(
                                  formatDuration(musicLibrary.playerDuration),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                musicLibrary.currentSong != null
                    ? "${musicLibrary.currentSong!.title} - ${musicLibrary.getArtistStr(musicLibrary.currentSong!.title)}"
                    : "",
              ),
            ],
          ),
        );
      },
    );
  }
}
