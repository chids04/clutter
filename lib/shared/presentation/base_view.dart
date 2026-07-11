import 'package:flutter/material.dart';

/// the abstract base widget. all views must extend this.
abstract class CView extends StatefulWidget {
  final String viewTitle;

  const CView({required this.viewTitle, super.key});

  @override
  State<CView> createState();
}

/// the base state that enforces layout, appbar style, and stretching.
abstract class CViewState<T extends CView> extends State<T> {
  // abstract method children must implement this to provide their specific ui.
  Widget buildViewContent(BuildContext context);

  @override
  Widget build(BuildContext context) {
    // each view provides its own scaffold and appbar.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.viewTitle), // each subclass supplies its own title
        centerTitle: false,
        elevation: 0.0,
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.transparent,
            width: 1.0,
          ),
        ),
      ),
      // safearea + sizedbox.expand ensures content stretches to fill space
      body: SafeArea(child: SizedBox.expand(child: buildViewContent(context))),
    );
  }
}
