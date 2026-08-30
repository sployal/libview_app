import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/client_service.dart';

class ClientEditorResult {
  const ClientEditorResult({
    required this.name,
    required this.email,
    required this.storageLimitBytes,
  });

  final String name;
  final String email;
  final int storageLimitBytes;
}

Future<ClientEditorResult?> showClientEditorDialog({
  required BuildContext context,
  ClientWorkspace? client,
}) {
  return showDialog<ClientEditorResult>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (context) => _ClientEditorDialog(client: client),
  );
}

class _ClientEditorDialog extends StatefulWidget {
  const _ClientEditorDialog({this.client});

  final ClientWorkspace? client;

  @override
  State<_ClientEditorDialog> createState() => _ClientEditorDialogState();
}

class _ClientEditorDialogState extends State<_ClientEditorDialog> {
  static const _presets = <int>[
    250 * 1024 * 1024,
    500 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024,
  ];

  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _customAmount;
  late int _limitBytes;
  bool _custom = false;
  String? _error;

  bool get _editing => widget.client != null;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    _name = TextEditingController(text: client?.name ?? '');
    _email = TextEditingController(text: client?.inviteEmail ?? '');
    final limit = client?.storageLimitBytes ??
        ClientWorkspace.defaultStorageLimitBytes;
    _limitBytes = limit;
    _custom = !_presets.contains(limit);
    final customMb = (limit / (1024 * 1024)).round();
    _customAmount = TextEditingController(
      text: customMb > 0 ? '$customMb' : '1024',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _customAmount.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    var limit = _limitBytes;
    if (_custom) {
      final amount = int.tryParse(_customAmount.text.trim()) ?? 0;
      if (amount < 50) {
        setState(() => _error = 'Enter at least 50 MB');
        return;
      }
      limit = amount * 1024 * 1024;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Enter the client name');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    Navigator.pop(
      context,
      ClientEditorResult(
        name: name,
        email: email,
        storageLimitBytes: limit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF111827) : Colors.white;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final field = isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: sheet,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _editing
                            ? Icons.tune_rounded
                            : Icons.person_add_alt_1_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _editing ? 'Edit client' : 'New client',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _editing
                          ? 'Update details and the storage cap for this workspace.'
                          : 'Create a workspace and invite them by email.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        controller: _name,
                        label: 'Client name',
                        hint: 'Company or person',
                        icon: Icons.badge_outlined,
                        fill: field,
                        muted: muted,
                        title: title,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _email,
                        label: 'Email address',
                        hint: 'name@company.com',
                        icon: Icons.mail_outline_rounded,
                        fill: field,
                        muted: muted,
                        title: title,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Storage limit',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: title,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uploads stop when this workspace reaches the cap.',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _presets)
                            _chip(
                              label: ClientWorkspace.formatStorage(preset),
                              selected: !_custom && _limitBytes == preset,
                              onTap: () {
                                setState(() {
                                  _custom = false;
                                  _limitBytes = preset;
                                  _error = null;
                                });
                              },
                            ),
                          _chip(
                            label: 'Custom',
                            selected: _custom,
                            onTap: () {
                              setState(() {
                                _custom = true;
                                _error = null;
                              });
                            },
                          ),
                        ],
                      ),
                      if (_custom) ...[
                        const SizedBox(height: 12),
                        _field(
                          controller: _customAmount,
                          label: 'Custom limit (MB)',
                          hint: '1024',
                          icon: Icons.sd_storage_outlined,
                          fill: field,
                          muted: muted,
                          title: title,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: muted,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _editing ? 'Save changes' : 'Create client',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF0EA5E9),
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected ? const Color(0xFF0EA5E9) : const Color(0xFFCBD5E1),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color fill,
    required Color muted,
    required Color title,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autocorrect: keyboardType == TextInputType.emailAddress ? false : true,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none
          : TextCapitalization.words,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: TextStyle(color: title, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: muted, size: 20),
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF0EA5E9), width: 1.4),
        ),
      ),
    );
  }
}
