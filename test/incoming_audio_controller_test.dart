import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/incoming_audio/application/incoming_audio_controller.dart';
import 'package:clutter/features/incoming_audio/data/incoming_audio_service.dart';
import 'package:clutter/features/incoming_audio/domain/incoming_audio_receipt.dart';

class _FakeIncomingAudioService implements IncomingAudioService {
  final List<IncomingAudioReceipt> pending = [];
  Future<void> Function()? _handler;

  @override
  Future<void> acknowledgeImports(Iterable<String> ids) async {
    final acknowledged = ids.toSet();
    pending.removeWhere((receipt) => acknowledged.contains(receipt.id));
  }

  @override
  Future<List<IncomingAudioReceipt>> listPendingImports() async =>
      List.of(pending);

  @override
  void setImportsAvailableHandler(Future<void> Function()? handler) {
    _handler = handler;
  }

  Future<void> announceImports() async {
    await _handler?.call();
  }
}

const _firstReceipt = IncomingAudioReceipt(
  id: 'first',
  copiedCount: 2,
  failedCount: 0,
  ignoredCount: 0,
);

const _secondReceipt = IncomingAudioReceipt(
  id: 'second',
  copiedCount: 1,
  failedCount: 0,
  ignoredCount: 0,
);

void main() {
  test(
    'acknowledges copied files only after the library scan succeeds',
    () async {
      final service = _FakeIncomingAudioService()..pending.add(_firstReceipt);
      final messages = <String>[];
      final controller = IncomingAudioController(
        service: service,
        importManagedAudio: () async => 2,
        showMessage: messages.add,
      );

      await controller.start();

      expect(service.pending, isEmpty);
      expect(messages, ['imported 2 songs']);
      controller.dispose();
    },
  );

  test('keeps the receipt for a later retry when scanning fails', () async {
    final service = _FakeIncomingAudioService()..pending.add(_firstReceipt);
    final messages = <String>[];
    final controller = IncomingAudioController(
      service: service,
      importManagedAudio: () => Future<int>.error(StateError('scan failed')),
      showMessage: messages.add,
    );

    await controller.start();

    expect(service.pending, [_firstReceipt]);
    expect(messages, ['could not import audio — will retry']);
    controller.dispose();
  });

  test('coalesces an import notification received during a scan', () async {
    final service = _FakeIncomingAudioService()..pending.add(_firstReceipt);
    final firstScanStarted = Completer<void>();
    final finishFirstScan = Completer<int>();
    var scanCount = 0;
    final controller = IncomingAudioController(
      service: service,
      importManagedAudio: () {
        scanCount++;
        if (scanCount == 1) {
          firstScanStarted.complete();
          return finishFirstScan.future;
        }
        return Future.value(1);
      },
      showMessage: (_) {},
    );

    final processing = controller.start();
    await firstScanStarted.future;
    service.pending.add(_secondReceipt);
    await service.announceImports();
    finishFirstScan.complete(2);
    await processing;

    expect(scanCount, 2);
    expect(service.pending, isEmpty);
    controller.dispose();
  });
}
