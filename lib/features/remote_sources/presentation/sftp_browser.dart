import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/features/remote_sources/presentation/sftp_download_panel.dart';
import 'package:clutter/features/remote_sources/presentation/sftp_profile_dialog.dart';
import 'package:clutter/src/rust/api/models.dart';

class SftpBrowser extends StatelessWidget {
  const SftpBrowser({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SftpController>(
      builder: (context, controller, _) {
        if (controller.profiles.isEmpty) {
          return _EmptyProfiles(loading: controller.loading);
        }
        return Column(
          children: [
            _ProfileToolbar(controller: controller),
            if (controller.error case final error?)
              _ErrorBanner(message: error),
            _Breadcrumbs(path: controller.currentPath),
            Expanded(child: _EntryList(controller: controller)),
            if (controller.jobs.isNotEmpty)
              SftpDownloadPanel(
                jobs: controller.jobs,
                onCancel: controller.cancelDownload,
              ),
          ],
        );
      },
    );
  }
}

class _EmptyProfiles extends StatelessWidget {
  final bool loading;

  const _EmptyProfiles({required this.loading});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_outlined, size: 48),
            const SizedBox(height: 14),
            const Text('connect an sftp music source'),
            const SizedBox(height: 6),
            Text(
              'the server stays in rust and the password is saved in your device vault.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: loading ? null : () => showSftpProfileDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('add sftp server'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileToolbar extends StatelessWidget {
  final SftpController controller;

  const _ProfileToolbar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedProfile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selected?.id,
              decoration: const InputDecoration(
                labelText: 'server',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: controller.profiles
                  .map(
                    (profile) => DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
                  )
                  .toList(),
              onChanged: controller.loading
                  ? null
                  : (id) {
                      if (id != null) controller.selectProfile(id);
                    },
            ),
          ),
          IconButton(
            tooltip: 'add server',
            onPressed: controller.loading
                ? null
                : () => showSftpProfileDialog(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'edit server',
            onPressed: selected == null || controller.loading
                ? null
                : () => showSftpProfileDialog(context, profile: selected),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'server actions',
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('reconnect')),
              PopupMenuItem(value: 'delete', child: Text('delete server')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final selected = controller.selectedProfile;
    if (selected == null) return;
    if (action == 'refresh') {
      await controller.connectSelected();
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('delete sftp server?'),
        content: Text('remove ${selected.name} and its saved password?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('delete'),
          ),
        ],
      ),
    );
    if (remove == true) await controller.deleteProfile(selected.id);
  }
}

class _Breadcrumbs extends StatelessWidget {
  final String path;

  const _Breadcrumbs({required this.path});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<SftpController>();
    final parts = path.isEmpty ? <String>[] : path.split('/');
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          TextButton.icon(
            onPressed: () => controller.browse(''),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('root'),
          ),
          for (var index = 0; index < parts.length; index++) ...[
            const Center(child: Icon(Icons.chevron_right, size: 18)),
            TextButton(
              onPressed: () =>
                  controller.browse(parts.take(index + 1).join('/')),
              child: Text(parts[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  final SftpController controller;

  const _EntryList({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.loading && controller.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.connected) {
      return const Center(child: Text('not connected'));
    }
    if (controller.entries.isEmpty) {
      return const Center(child: Text('this folder is empty'));
    }
    return RefreshIndicator(
      onRefresh: () => controller.browse(controller.currentPath),
      child: ListView.separated(
        itemCount: controller.entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = controller.entries[index];
          return _EntryTile(entry: entry, controller: controller);
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final SftpEntryData entry;
  final SftpController controller;

  const _EntryTile({required this.entry, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDirectory = entry.kind == SftpEntryKindData.directory;
    final supported = entry.kind != SftpEntryKindData.unsupported;
    return ListTile(
      leading: Icon(isDirectory ? Icons.folder_outlined : Icons.audio_file),
      title: Row(
        children: [
          Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
          if (entry.downloaded) ...[
            const SizedBox(width: 8),
            const _DownloadedBadge(),
          ],
        ],
      ),
      subtitle: entry.size == null || isDirectory
          ? null
          : Text(_formatBytes(entry.size!)),
      onTap: isDirectory ? () => controller.browse(entry.relativePath) : null,
      trailing: IconButton(
        tooltip: isDirectory ? 'download folder' : 'download file',
        onPressed: supported ? () => controller.startDownload(entry) : null,
        icon: const Icon(Icons.download_outlined),
      ),
    );
  }

  String _formatBytes(BigInt bytes) {
    final value = bytes.toDouble();
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} gb';
    }
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} mb';
    }
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} kb';
    return '${bytes.toString()} bytes';
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text('downloaded', style: TextStyle(fontSize: 10)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        message.replaceFirst('Exception: ', ''),
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
