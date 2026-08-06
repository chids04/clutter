import 'package:flutter/material.dart';

class SearchResultFocusTile extends StatefulWidget {
  final Key resultKey;
  final bool dense;
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SearchResultFocusTile({
    super.key,
    required this.resultKey,
    this.dense = false,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  State<SearchResultFocusTile> createState() => _SearchResultFocusTileState();
}

class _SearchResultFocusTileState extends State<SearchResultFocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _focused
            ? colors.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: radius,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: _focused ? colors.onSurface : Colors.transparent,
          width: 2,
        ),
        borderRadius: radius,
      ),
      child: ListTile(
        key: widget.resultKey,
        dense: widget.dense,
        leading: widget.leading,
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: widget.trailing,
        tileColor: Colors.transparent,
        focusColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onTap: widget.onTap,
      ),
    );
  }
}
