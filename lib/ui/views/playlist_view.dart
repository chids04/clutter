import 'package:flutter/material.dart';
import 'package:clutter/ui/views/c_view.dart';

class SearchView extends CView {
  const SearchView({super.key}) : super(viewTitle: 'playlists');

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends CViewState<SearchView> {
  @override
  Widget buildViewContent(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const <Widget>[
        Text("Welcome to the search screen"),
        Text("This is the second line"),
      ],
    );
  }
}
