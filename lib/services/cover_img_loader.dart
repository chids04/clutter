import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

Widget coverImg(
  String? coverPath,
  double size, {
  int? cacheSize,
  BoxFit fit = BoxFit.cover,
  Widget? fallback,
  bool expand = false,
}) {
  final placeholder = fallback ?? _fallbackCover(size);
  if (coverPath == null) return placeholder;

  final cache = cacheSize ?? _cacheSizeFor(size);
  final width = expand ? double.infinity : size;
  final height = expand ? double.infinity : size;

  return Image.file(
    File(coverPath),
    width: width,
    height: height,
    fit: fit,
    cacheWidth: cache,
    cacheHeight: cache,
    errorBuilder: (_, _, _) => placeholder,
  );
}

int _cacheSizeFor(double size) {
  if (size <= 44) return 132;
  if (size <= 56) return 168;
  if (size <= 96) return 256;
  return 360;
}

Widget _fallbackCover(double size) {
  return SvgPicture.asset(
    "assets/note.svg",
    width: size,
    height: size,
    colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
  );
}
