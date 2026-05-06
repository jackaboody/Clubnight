// presentation/tablet/widgets/add_player_dialog.dart

import 'package:flutter/material.dart';
import 'package:squash_social/data/repositories/player_repository.dart';

class AddPlayerDialog extends StatefulWidget {
  final VoidCallback onAdded;

  const AddPlayerDialog({super.key, required this.onAdded});

  @override
  State<AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<AddPlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  double _level = 3.0;
  bool _prefersDoubles = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add player'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 20),
            Text(
              'Skill level: ${_level.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: _level,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              label: _level.toStringAsFixed(1),
              onChanged: (v) => setState(() => _level = v),
            ),
            Row(
              children: [
                const Text('1  Beginner'),
                const Spacer(),
                const Text('5  Advanced'),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prefers doubles'),
              value: _prefersDoubles,
              onChanged: (v) => setState(() => _prefersDoubles = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await PlayerRepository().addPlayer(
        name: _nameController.text.trim(),
        level: _level,
        prefersDoubles: _prefersDoubles,
      );
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
