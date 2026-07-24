import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:clutter/features/remote_sources/application/sftp_controller.dart';
import 'package:clutter/src/rust/api/models.dart';

Future<void> showSftpProfileDialog(
  BuildContext context, {
  SftpProfileData? profile,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<SftpController>(),
      child: _SftpProfileDialog(profile: profile),
    ),
  );
}

class _SftpProfileDialog extends StatefulWidget {
  final SftpProfileData? profile;

  const _SftpProfileDialog({this.profile});

  @override
  State<_SftpProfileDialog> createState() => _SftpProfileDialogState();
}

class _SftpProfileDialogState extends State<_SftpProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _root;
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? 'home');
    _host = TextEditingController(text: profile?.host ?? '');
    _port = TextEditingController(text: '${profile?.port ?? 22}');
    _username = TextEditingController(text: profile?.username ?? '');
    _root = TextEditingController(text: profile?.rootPath ?? '/');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _root.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.profile == null ? 'add sftp server' : 'edit sftp server',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'name'),
                _field(_host, 'tailscale ip or hostname'),
                _field(_port, 'port', numeric: true),
                _field(_username, 'username'),
                _field(_root, 'music root'),
                TextFormField(
                  controller: _password,
                  obscureText: false,
                  decoration: const InputDecoration(labelText: 'password'),
                  validator: _required,
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _probeAndSave,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('connect'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool numeric = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: _required,
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'required' : null;

  Future<void> _probeAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    final port = int.tryParse(_port.text);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'port must be between 1 and 65535');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final controller = context.read<SftpController>();
      final fingerprint = await controller.probeFingerprint(_host.text, port);
      if (!mounted || !await _confirmFingerprint(fingerprint)) return;
      await controller.saveProfile(
        profile: SftpProfileData(
          id: widget.profile?.id ?? '',
          name: _name.text.trim(),
          host: _host.text.trim(),
          port: port,
          username: _username.text.trim(),
          rootPath: _normaliseRoot(_root.text),
          hostKeyFingerprint: fingerprint,
          isSelected: true,
        ),
        password: _password.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmFingerprint(String fingerprint) async {
    final unchanged = widget.profile?.hostKeyFingerprint == fingerprint;
    if (unchanged) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('trust this server?'),
            content: SelectableText(
              'check this fingerprint against your server before continuing:\n\n$fingerprint',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('trust and connect'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _normaliseRoot(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('/')) return trimmed;
    return '/$trimmed';
  }
}
