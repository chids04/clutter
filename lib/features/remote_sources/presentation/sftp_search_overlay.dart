import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/shared/presentation/search_result_focus_tile.dart';
import 'package:clutter/src/rust/api/models.dart';

Future<void> showSftpSearchOverlay(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (context, _, _) => const _SftpSearchDialog(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DismissSftpSearchIntent extends Intent {
  const _DismissSftpSearchIntent();
}

class _SftpSearchDialog extends StatefulWidget {
  const _SftpSearchDialog();

  @override
  State<_SftpSearchDialog> createState() => _SftpSearchDialogState();
}

class _SftpSearchDialogState extends State<_SftpSearchDialog> {
  final _queryController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'sftp-search-field');
  final _focusScopeNode = FocusScopeNode(
    debugLabel: 'sftp-search-scope',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  SftpSearchResults? _results;
  String? _error;
  bool _isLoading = false;
  int _searchToken = 0;

  @override
  void dispose() {
    _queryController.dispose();
    _searchFocusNode.dispose();
    _focusScopeNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      _searchToken++;
      setState(() {
        _results = null;
        _error = null;
        _isLoading = false;
      });
      return;
    }
    if (_isLoading) return;
    final token = ++_searchToken;

    setState(() {
      _results = null;
      _error = null;
      _isLoading = true;
    });
    try {
      final results = await context.read<SftpController>().searchCurrentSubtree(
        query,
      );
      if (!mounted || token != _searchToken) return;
      if (_queryController.text.trim() != query) {
        setState(() => _isLoading = false);
        return;
      }
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _error = 'search failed';
        _isLoading = false;
      });
    }
  }

  void _dismiss() {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _handleEscape() {
    if (_searchFocusNode.hasPrimaryFocus) {
      _dismiss();
    } else {
      _searchFocusNode.requestFocus();
    }
  }

  void _openFolder(SftpEntryData entry) {
    final controller = context.read<SftpController>();
    _dismiss();
    unawaited(controller.browse(entry.relativePath));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final theme = Theme.of(context);
    final isMobile = size.width < 640;
    final horizontalInset = isMobile ? 14.0 : 24.0;
    final topInset = mediaQuery.padding.top + (isMobile ? 12.0 : 24.0);
    final bottomInset =
        mediaQuery.padding.bottom +
        mediaQuery.viewInsets.bottom +
        (isMobile ? 12.0 : 24.0);
    final maxWidth = isMobile ? size.width - (horizontalInset * 2) : 620.0;
    final availableHeight = size.height - topInset - bottomInset;
    final maxHeight = isMobile
        ? math.max(180.0, math.min(availableHeight, 560.0))
        : math.min(size.height * 0.72, 680.0);

    final body = Column(
      mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('sftp-search-field'),
          controller: _queryController,
          focusNode: _searchFocusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onEditingComplete: () {},
          onSubmitted: _submit,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: 'search this folder and subfolders',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ExcludeFocus(
                    child: IconButton(
                      tooltip: 'search',
                      onPressed: () => _submit(_queryController.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
          ),
        ),
        Divider(
          height: 1,
          color: theme.dividerTheme.color ?? Colors.transparent,
        ),
        if (isMobile)
          Expanded(child: _buildResults())
        else
          Flexible(child: _buildResults()),
      ],
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissSftpSearchIntent(),
      },
      child: Actions(
        actions: {
          _DismissSftpSearchIntent: CallbackAction<_DismissSftpSearchIntent>(
            onInvoke: (_) {
              _handleEscape();
              return null;
            },
          ),
        },
        child: FocusScope.withExternalFocusNode(
          focusScopeNode: _focusScopeNode,
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                topInset,
                horizontalInset,
                bottomInset,
              ),
              child: Align(
                alignment: isMobile ? Alignment.topCenter : Alignment.center,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    key: const ValueKey('sftp-search-panel'),
                    width: maxWidth,
                    height: isMobile ? maxHeight : null,
                    constraints: isMobile
                        ? null
                        : BoxConstraints(maxHeight: maxHeight),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.dividerTheme.color ?? Colors.transparent,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 32,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_error case final error?) {
      return _CenteredMessage(text: error);
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _results;
    if (results == null) {
      return const _CenteredMessage(
        text: 'type a name, then press search or return',
      );
    }
    if (results.entries.isEmpty) {
      return const _CenteredMessage(text: 'no matching files or folders');
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          if (results.truncated) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                'showing the first 200 results',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
          ],
          for (var index = 0; index < results.entries.length; index++) ...[
            _SearchResultTile(
              entry: results.entries[index],
              onFolderTap: _openFolder,
            ),
            if (index != results.entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final SftpEntryData entry;
  final ValueChanged<SftpEntryData> onFolderTap;

  const _SearchResultTile({required this.entry, required this.onFolderTap});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<SftpController>();
    final isDirectory = entry.kind == SftpEntryKindData.directory;
    final isSupported = entry.kind != SftpEntryKindData.unsupported;
    final icon = switch (entry.kind) {
      SftpEntryKindData.directory => Icons.folder_outlined,
      SftpEntryKindData.file => Icons.audio_file_outlined,
      SftpEntryKindData.unsupported => Icons.insert_drive_file_outlined,
    };
    final primaryAction = switch (entry.kind) {
      SftpEntryKindData.directory => () => onFolderTap(entry),
      SftpEntryKindData.file => () => unawaited(
        controller.startDownload(entry),
      ),
      SftpEntryKindData.unsupported => null,
    };
    return ExcludeFocus(
      excluding: !isSupported,
      child: SearchResultFocusTile(
        resultKey: ValueKey('sftp-search-result-${entry.relativePath}'),
        leading: Icon(icon),
        title: Row(
          children: [
            Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
            if (entry.downloaded) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('downloaded', style: TextStyle(fontSize: 10)),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(entry.relativePath, overflow: TextOverflow.ellipsis),
        onTap: primaryAction,
        trailing: ExcludeFocus(
          child: IconButton(
            key: ValueKey('sftp-search-download-${entry.relativePath}'),
            tooltip: isDirectory ? 'download folder' : 'download file',
            onPressed: isSupported
                ? () => unawaited(controller.startDownload(entry))
                : null,
            icon: const Icon(Icons.download_outlined),
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;

  const _CenteredMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
