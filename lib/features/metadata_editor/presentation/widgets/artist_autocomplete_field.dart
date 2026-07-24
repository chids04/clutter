import 'dart:async';

import 'package:flutter/material.dart';

import 'package:clutter/features/library/domain/library_entities.dart';

typedef ArtistSearch =
    Future<List<ArtistViewData>> Function(String query, {int limit});

class ArtistAutocompleteField extends StatefulWidget {
  const ArtistAutocompleteField({
    super.key,
    required this.controller,
    required this.searchArtists,
    required this.label,
    this.helperText,
    this.multiple = false,
    this.onChanged,
    this.focusNode,
    this.style,
  });

  final TextEditingController controller;
  final ArtistSearch searchArtists;
  final String label;
  final String? helperText;
  final bool multiple;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final TextStyle? style;

  @override
  State<ArtistAutocompleteField> createState() =>
      _ArtistAutocompleteFieldState();
}

class _ArtistAutocompleteFieldState extends State<ArtistAutocompleteField> {
  Timer? _debounce;
  List<ArtistViewData> _suggestions = const [];
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onChanged?.call(value);
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    final query = activeArtistQuery(value, multiple: widget.multiple);
    if (query.isEmpty) {
      _setSuggestions(const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _search(query, generation),
    );
  }

  Future<void> _search(String query, int generation) async {
    List<ArtistViewData> results;
    try {
      results = await widget.searchArtists(query, limit: 8);
    } catch (_) {
      results = const [];
    }
    if (!mounted || generation != _searchGeneration) return;
    final currentQuery = activeArtistQuery(
      widget.controller.text,
      multiple: widget.multiple,
    );
    if (currentQuery != query) return;
    _setSuggestions(
      filterArtistSuggestions(
        results,
        widget.controller.text,
        multiple: widget.multiple,
      ),
    );
  }

  void _setSuggestions(List<ArtistViewData> suggestions) {
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
  }

  void _select(ArtistViewData artist) {
    final value = applyArtistSuggestion(
      widget.controller.text,
      artist.name,
      multiple: widget.multiple,
    );
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _debounce?.cancel();
    _searchGeneration++;
    _setSuggestions(const []);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: widget.style,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
        ),
        onChanged: _onChanged,
      ),
      if (_suggestions.isNotEmpty) _suggestionList(),
    ],
  );

  Widget _suggestionList() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 160),
    child: ListView.builder(
      shrinkWrap: true,
      itemCount: _suggestions.length,
      itemBuilder: (_, index) {
        final artist = _suggestions[index];
        return ListTile(
          dense: true,
          title: Text(artist.name),
          onTap: () => _select(artist),
        );
      },
    ),
  );
}

String activeArtistQuery(String raw, {required bool multiple}) {
  if (!multiple) return raw.trim();
  return raw.split(',').last.trim();
}

String applyArtistSuggestion(
  String raw,
  String artist, {
  required bool multiple,
}) {
  if (!multiple) return artist;
  final separator = raw.lastIndexOf(',');
  if (separator < 0) return artist;
  final prefix = raw.substring(0, separator + 1);
  return '$prefix $artist';
}

List<ArtistViewData> filterArtistSuggestions(
  List<ArtistViewData> suggestions,
  String raw, {
  required bool multiple,
}) {
  final values = multiple ? raw.split(',') : [raw];
  final selected = values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  return suggestions
      .where((artist) => !selected.contains(artist.name.toLowerCase()))
      .toList(growable: false);
}
