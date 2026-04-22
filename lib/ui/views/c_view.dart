import 'package:flutter/material.dart';

/// The abstract base widget. All views must extend this.
abstract class CView extends StatefulWidget {
  final String viewTitle;

  const CView({required this.viewTitle, super.key});

  @override
  State<CView> createState();
}

/// The base state that enforces layout, AppBar style, and stretching.
abstract class CViewState<T extends CView> extends State<T> {
  // Abstract method Children must implement this to provide their specific UI.
  Widget buildViewContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    // Each view provides its OWN Scaffold and AppBar.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.viewTitle), // Uses the specific view's title
        centerTitle: false,
        elevation: 0.0,
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
            width: 1.0,
          ),
        ),
      ),
      // SafeArea + SizedBox.expand ensures content stretches to fill space
      body: SafeArea(child: SizedBox.expand(child: buildViewContent(context))),
    );
  }
}
