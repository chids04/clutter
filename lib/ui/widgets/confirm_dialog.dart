import 'package:flutter/material.dart';

/// Reusable destructive-action confirmation. Returns `true` iff the user tapped
/// the action button; `false` on cancel or dismiss.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text("cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            actionLabel,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
