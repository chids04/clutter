import 'package:flutter/material.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/src/rust/api/models.dart';

class SftpDownloadPanel extends StatelessWidget {
  final List<SftpDownloadJob> jobs;
  final Future<void> Function(String jobId) onCancel;

  const SftpDownloadPanel({
    super.key,
    required this.jobs,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView.separated(
          reverse: true,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: jobs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final job = jobs[jobs.length - index - 1];
            return _DownloadRow(
              key: ValueKey('sftp-download-${job.jobId}'),
              job: job,
              onCancel: onCancel,
            );
          },
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final SftpDownloadJob job;
  final Future<void> Function(String jobId) onCancel;

  const _DownloadRow({super.key, required this.job, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final progress = job.progress;
    final fraction = progress.bytesTotal == BigInt.zero
        ? null
        : progress.bytesCompleted.toDouble() / progress.bytesTotal.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          if (job.isTerminal)
            Icon(_stateIcon(progress.state))
          else
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(value: fraction),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(job.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  _stateLabel(progress),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (progress.currentName case final name?
                    when name != job.label)
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (!job.isTerminal)
            IconButton(
              key: ValueKey('cancel-sftp-download-${job.jobId}'),
              tooltip: 'cancel ${job.label}',
              onPressed: () => onCancel(job.jobId),
              icon: const Icon(Icons.close),
            ),
        ],
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

  IconData _stateIcon(SftpDownloadStateData state) => switch (state) {
    SftpDownloadStateData.completed => Icons.check_circle_outline,
    SftpDownloadStateData.completedWithErrors => Icons.warning_amber,
    SftpDownloadStateData.cancelled => Icons.cancel_outlined,
    SftpDownloadStateData.failed => Icons.error_outline,
    _ => Icons.downloading,
  };
}
