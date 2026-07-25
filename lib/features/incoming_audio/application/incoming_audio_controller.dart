import 'dart:async';

import 'package:clutter/features/incoming_audio/data/incoming_audio_service.dart';

class IncomingAudioController {
  final IncomingAudioService service;
  final Future<int> Function() importManagedAudio;
  final void Function(String message) showMessage;

  IncomingAudioController({
    required this.service,
    required this.importManagedAudio,
    required this.showMessage,
  });

  bool _processing = false;
  bool _processAgain = false;
  bool _disposed = false;

  Future<void> start() async {
    service.setImportsAvailableHandler(processPending);
    await processPending();
  }

  Future<void> processPending() async {
    if (_disposed) return;
    if (_processing) {
      _processAgain = true;
      return;
    }
    _processing = true;
    try {
      do {
        _processAgain = false;
        await _processBatch();
      } while (_processAgain && !_disposed);
    } finally {
      _processing = false;
    }
  }

  Future<void> _processBatch() async {
    final receipts = await service.listPendingImports();
    if (receipts.isEmpty) return;

    final copied = receipts.fold<int>(
      0,
      (total, receipt) => total + receipt.copiedCount,
    );
    final failed = receipts.fold<int>(
      0,
      (total, receipt) => total + receipt.failedCount,
    );
    final ids = receipts.map((receipt) => receipt.id);

    if (copied == 0) {
      await service.acknowledgeImports(ids);
      showMessage(
        failed > 0
            ? 'could not copy the selected audio'
            : 'no supported audio files found',
      );
      return;
    }

    try {
      final added = await importManagedAudio();
      await service.acknowledgeImports(ids);
      if (failed > 0 || added < copied) {
        showMessage('imported $added of $copied audio files');
      } else {
        showMessage('imported $added song${added == 1 ? '' : 's'}');
      }
    } catch (_) {
      showMessage('could not import audio — will retry');
    }
  }

  void dispose() {
    _disposed = true;
    service.setImportsAvailableHandler(null);
  }
}
