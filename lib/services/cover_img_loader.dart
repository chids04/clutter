import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

Widget coverImg(String? coverPath, double size, {int? cacheSize}) {
  if (coverPath == null) return _fallbackCover(size);

  final cache = cacheSize ?? (size * 3).toInt();

  return Image.file(
    File(coverPath),
    width: size,
    height: size,
    cacheWidth: cache,
    cacheHeight: cache,
    errorBuilder: (_, _, _) => _fallbackCover(size),
  );
}

Widget _fallbackCover(double size) {
  return SvgPicture.asset(
    "assets/note.svg",
    width: size,
    height: size,
    colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
  );
}
