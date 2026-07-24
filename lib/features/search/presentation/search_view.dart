import 'package:flutter/material.dart';

import 'package:clutter/features/remote_sources/presentation/sftp_browser.dart';
import 'package:clutter/shared/presentation/base_view.dart';

enum _RemoteSource { sftp }

class SearchView extends CView {
  const SearchView({super.key}) : super(viewTitle: 'search');

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends CViewState<SearchView> {
  _RemoteSource _source = _RemoteSource.sftp;

  @override
  Widget buildViewContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            children: _RemoteSource.values
                .map(
                  (source) => _SourceTab(
                    label: source.name,
                    selected: source == _source,
                    onTap: () => setState(() => _source = source),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_source) {
            _RemoteSource.sftp => const SftpBrowser(),
          },
        ),
      ],
    );
  }
}

class _SourceTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey(
        'remote-source-${label.toLowerCase()}-${selected ? 'active' : 'inactive'}',
      ),
      color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
