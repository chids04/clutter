import 'package:flutter/services.dart';

import 'package:clutter/features/incoming_audio/domain/incoming_audio_receipt.dart';

abstract interface class IncomingAudioService {
  void setImportsAvailableHandler(Future<void> Function()? handler);
  Future<List<IncomingAudioReceipt>> listPendingImports();
  Future<void> acknowledgeImports(Iterable<String> ids);
}

class MethodChannelIncomingAudioService implements IncomingAudioService {
  static const _channel = MethodChannel('com.chx.clutter/incoming_audio');

  const MethodChannelIncomingAudioService();

  @override
  void setImportsAvailableHandler(Future<void> Function()? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'importsAvailable') await handler();
    });
  }

  @override
  Future<List<IncomingAudioReceipt>> listPendingImports() async {
    final raw = await _channel.invokeListMethod<Object?>('listPendingImports');
    return [
      for (final item in raw ?? const <Object?>[])
        IncomingAudioReceipt.fromMap((item! as Map<Object?, Object?>)),
    ];
  }

  @override
  Future<void> acknowledgeImports(Iterable<String> ids) {
    return _channel.invokeMethod<void>(
      'acknowledgeImports',
      ids.toList(growable: false),
    );
  }
}
