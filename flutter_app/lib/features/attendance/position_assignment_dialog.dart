import 'package:flutter/material.dart';

import '../../app_theme/app_theme.dart';

Future<String?> showPositionAssignmentDialog({
  required BuildContext context,
  required String memberName,
  required List<String> options,
}) {
  return showDialog<String?>(
    context: context,
    builder: (context) => _PositionAssignmentDialog(
      memberName: memberName,
      options: options,
    ),
  );
}

class _PositionAssignmentDialog extends StatefulWidget {
  const _PositionAssignmentDialog({
    required this.memberName,
    required this.options,
  });

  final String memberName;
  final List<String> options;

  @override
  State<_PositionAssignmentDialog> createState() =>
      _PositionAssignmentDialogState();
}

class _PositionAssignmentDialogState extends State<_PositionAssignmentDialog> {
  late final TextEditingController _controller;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(String label) {
    setState(() {
      _selected = label;
      _controller.text = label;
      _controller.selection = TextSelection.collapsed(offset: label.length);
    });
  }

  void _save() {
    final value = _controller.text.trim().toUpperCase();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options.take(18).toList();

    return AlertDialog(
      title: const Text('Assign Position'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.memberName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 14),
            if (options.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    ChoiceChip(
                      label: Text(
                        option,
                        style: TextStyle(
                          color: _selected == option
                              ? Colors.white
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: AppTheme.surface,
                      selectedColor: AppTheme.primary,
                      side: BorderSide(
                        color: _selected == option
                            ? AppTheme.primary
                            : AppTheme.slate200,
                      ),
                      selected: _selected == option,
                      onSelected: (_) => _choose(option),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Position',
                hintText: 'A1, A5, B3...',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              onChanged: (value) {
                final normalized = value.trim().toUpperCase();
                if (_selected != normalized) {
                  setState(() => _selected = null);
                }
              },
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
