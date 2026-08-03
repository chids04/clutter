import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/presentation/sftp_download_panel.dart';
import 'package:clutter/src/rust/api/models.dart';

void main() {
  testWidgets('shows and cancels simultaneous downloads independently', (
    tester,
  ) async {
    final cancelled = <String>[];
    final jobs = [
      _job('job-1', 'first album', SftpDownloadStateData.downloading),
      _job('job-2', 'second.mp3', SftpDownloadStateData.importing),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: SftpDownloadPanel(
            jobs: jobs,
            onCancel: (jobId) async => cancelled.add(jobId),
          ),
        ),
      ),
    );

    expect(find.text('first album'), findsOneWidget);
    expect(find.text('second.mp3'), findsOneWidget);
    expect(find.text('downloading · 1/2 files'), findsOneWidget);
    expect(find.text('adding to library · 1/2 files'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel-sftp-download-job-1')));
    await tester.pump();

    expect(cancelled, ['job-1']);
  });
}

SftpDownloadJob _job(String jobId, String label, SftpDownloadStateData state) {
  return SftpDownloadJob(
    label: label,
    progress: SftpDownloadProgressData(
      jobId: jobId,
      state: state,
      currentName: label,
      filesCompleted: 1,
      filesTotal: 2,
      bytesCompleted: BigInt.from(50),
      bytesTotal: BigInt.from(100),
      failedFiles: 0,
    ),
  );
}
