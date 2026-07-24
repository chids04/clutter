import 'package:flutter/material.dart';

import 'package:clutter/src/rust/api/models.dart';

class SftpDownloadPanel extends StatelessWidget {
  final List<SftpDownloadProgressData> jobs;
  final Future<void> Function(String jobId) onCancel;

  const SftpDownloadPanel({
    super.key,
    required this.jobs,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final active = jobs.reversed.first;
    final terminal = _isTerminal(active.state);
    final progress = active.bytesTotal == BigInt.zero
        ? null
        : active.bytesCompleted.toDouble() / active.bytesTotal.toDouble();
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            if (terminal)
              Icon(_stateIcon(active.state))
            else
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(value: progress),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_stateLabel(active)),
                  if (active.currentName case final name?)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (!terminal)
              IconButton(
                tooltip: 'cancel download',
                onPressed: () => onCancel(active.jobId),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(SftpDownloadProgressData progress) {
    final count = '${progress.filesCompleted}/${progress.filesTotal} files';
    return switch (progress.state) {
      SftpDownloadStateData.discovering => 'checking folder…',
      SftpDownloadStateData.downloading => 'downloading · $count',
      SftpDownloadStateData.importing => 'adding to library · $count',
      SftpDownloadStateData.completed => 'download complete · $count',
      SftpDownloadStateData.completedWithErrors =>
        'complete with ${progress.failedFiles} failed · $count',
      SftpDownloadStateData.cancelled => 'download cancelled · $count',
      SftpDownloadStateData.failed => progress.message ?? 'download failed',
    };
  }

  bool _isTerminal(SftpDownloadStateData state) => switch (state) {
    SftpDownloadStateData.completed ||
    SftpDownloadStateData.completedWithErrors ||
    SftpDownloadStateData.cancelled ||
    SftpDownloadStateData.failed => true,
    _ => false,
  };

  IconData _stateIcon(SftpDownloadStateData state) => switch (state) {
    SftpDownloadStateData.completed => Icons.check_circle_outline,
    SftpDownloadStateData.completedWithErrors => Icons.warning_amber,
    SftpDownloadStateData.cancelled => Icons.cancel_outlined,
    SftpDownloadStateData.failed => Icons.error_outline,
    _ => Icons.downloading,
  };
}
