import 'dart:async';

import 'package:flutter/foundation.dart';

class ToastController extends ChangeNotifier {
  String? _message;
  Timer? _timer;

  String? get message => _message;

  void show(String message) {
    _message = message;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      _message = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    // timers keep their callback alive, so always cancel them with the owner
    _timer?.cancel();
    super.dispose();
  }
}
