import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ArtworkCropOutputStore {
  const ArtworkCropOutputStore();

  Future<String> write(Uint8List bytes) async {
    final cache = await getTemporaryDirectory();
    final directory = Directory(p.join(cache.path, 'artwork-crops'));
    await directory.create(recursive: true);
    // rust sniffs the bytes, so the temporary suffix is only for humans.
    final path = p.join(directory.path, '${const Uuid().v4()}.image');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> remove(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
