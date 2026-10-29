import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/barangay_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/barangay_provider.dart';
import '../../services/emergency_contacts_service.dart';
import '../../utils/constants.dart';

/// Why a number cannot be saved, or null when it can.
///
/// Strict on purpose: this number is shown to someone who needs help right now,
/// so a typo (a letter, a missing digit) must be caught when it is typed, not
/// discovered by a frightened resident whose call does not connect.
String? validateContactNumber(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 'Enter a phone number';
  if (!RegExp(r'^[0-9+()\-\s]+$').hasMatch(text)) {
    return 'Use digits only (spaces, + ( ) and - are fine)';
  }
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 3) return 'That number is too short';
  if (digits.length > 15) return 'That number is too long';
  if (text.indexOf('+') > 0 || '+'.allMatches(text).length > 1) {
    return 'A + may only start the number';
  }
  return null;
}

/// Where an admin keeps the numbers a resident is shown when nobody has
/// answered their report ("last resort").
///
/// An admin edits their own barangay's list. The SuperAdmin also edits the
/// city-level list, which residents see when their barangay has none of its own
/// (and after that, 911). The database enforces the same limits — an admin
/// cannot change another barangay's or the city's numbers even by calling the
/// API directly — this screen just does not offer what would be refused.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key, this.service, this.barangays});

  final EmergencyContactsService? service;

  /// Barangays a SuperAdmin can choose from (tests); otherwise read from the
  /// app's barangay list.
  final List<BarangayModel>? barangays;

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late final EmergencyContactsService _service =
      widget.service ?? EmergencyContactsService();

  /// Whose list is on screen: a barangay id, or null for the city-level list.
  String? _scope;
  bool _scopeReady = false;

  List<EmergencyContact> _contacts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      if (user == null) return;
      // An admin works on their own barangay; a superadmin starts at city level.
      _scope = user.isSuperAdmin ? null : user.barangayId;
      _scopeReady = true;
      if (user.isSuperAdmin && widget.barangays == null) {
        context.read<BarangayProvider>().loadBarangays();
      }
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.manageList(_scope);
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the numbers. Check the connection and try again.';
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _edit([EmergencyContact? existing]) async {
    final result = await showDialog<_ContactForm>(
      context: context,
      builder: (_) => _ContactDialog(existing: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await _run(
        () => _service.add(
          barangayId: _scope,
          label: result.label,
          category: result.category,
          phoneNumber: result.phone,
          sortOrder: _contacts.isEmpty ? 1 : _contacts.last.sortOrder + 1,
        ),
        'Could not add the number.',
      );
    } else {
      await _run(
        () => _service.update(existing.copyWith(
          label: result.label,
          category: result.category,
          phoneNumber: result.phone,
        )),
        'Could not save the change.',
      );
    }
  }

  Future<void> _toggle(EmergencyContact c, bool active) => _run(
        () => _service.update(c.copyWith(isActive: active)),
        'Could not change that number.',
      );

  Future<void> _delete(EmergencyContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this number?'),
        content: Text('${c.label} (${c.phoneNumber}) will no longer be shown to residents.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _service.delete(c.id), 'Could not remove that number.');
    }
  }

  /// Swaps the order of two neighbours — the order residents see them in.
  Future<void> _move(int index, int by) async {
    final j = index + by;
    if (j < 0 || j >= _contacts.length) return;
    final a = _contacts[index];
    final b = _contacts[j];
    // Equal sort orders would make a swap a no-op, so spread them first.
    final aOrder = a.sortOrder == b.sortOrder ? index + 1 : a.sortOrder;
    final bOrder = a.sortOrder == b.sortOrder ? j + 1 : b.sortOrder;
    await _run(() async {
      await _service.update(a.copyWith(sortOrder: bOrder));
      await _service.update(b.copyWith(sortOrder: aOrder));
    }, 'Could not reorder.');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isSuper = user?.isSuperAdmin ?? false;
    // Only a superadmin picks between barangays, so only then is the list needed.
    final barangays = widget.barangays ??
        (isSuper
            ? context.watch<BarangayProvider>().barangays
            : const <BarangayModel>[]);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _scopeReady
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_call),
              label: const Text('Add a number'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emergency numbers', style: AppTextStyles.heading3),
                const SizedBox(height: 4),
                Text(
                  'Shown to a resident when nobody has answered their report for '
                  '15 minutes, each as a big tap-to-call button. If a barangay has '
                  'no numbers of its own, residents see the city numbers; if there '
                  'are none of those, 911.',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (isSuper)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String?>(
                key: ValueKey('scope-$_scope'),
                initialValue: _scope,
                decoration: const InputDecoration(
                  labelText: 'Whose numbers',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('City-level (used when a barangay has none)'),
                  ),
                  for (final b in barangays)
                    DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) {
                  _scope = v;
                  _load();
                },
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Center(
              child: Column(children: [
                Text(_error!),
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ]),
            )
          else if (_contacts.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  const Icon(Icons.phone_disabled_rounded, size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: 8),
                  Text(
                    _scope == null
                        ? 'No city-level numbers yet. Residents would see 911.'
                        : 'No numbers saved for this barangay. Residents will see the city numbers instead.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body,
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < _contacts.length; i++)
              _ContactTile(
                contact: _contacts[i],
                canMoveUp: i > 0,
                canMoveDown: i < _contacts.length - 1,
                onMoveUp: () => _move(i, -1),
                onMoveDown: () => _move(i, 1),
                onToggle: (v) => _toggle(_contacts[i], v),
                onEdit: () => _edit(_contacts[i]),
                onDelete: () => _delete(_contacts[i]),
              ),
        ],
      ),
    );
  }
}

IconData _iconFor(String category) => switch (category) {
      'police' => Icons.local_police_rounded,
      'hospital' => Icons.local_hospital_rounded,
      'rescue' => Icons.health_and_safety_rounded,
      'fire' => Icons.local_fire_department_rounded,
      _ => Icons.phone_in_talk_rounded,
    };

String _categoryLabel(String c) => switch (c) {
      'police' => 'Police',
      'hospital' => 'Hospital',
      'rescue' => 'Rescue',
      'fire' => 'Fire',
      _ => 'Other',
    };

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final EmergencyContact contact;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dim = !contact.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(contact.category), color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.label,
                      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                  Text('${_categoryLabel(contact.category)} · ${contact.phoneNumber}',
                      style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Move up',
              onPressed: canMoveUp ? onMoveUp : null,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Move down',
              onPressed: canMoveDown ? onMoveDown : null,
              icon: const Icon(Icons.arrow_downward_rounded, size: 20),
            ),
            Tooltip(
              message: contact.isActive ? 'Shown to residents' : 'Hidden from residents',
              child: Switch(value: contact.isActive, onChanged: onToggle),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactForm {
  const _ContactForm(this.label, this.category, this.phone);
  final String label;
  final String category;
  final String phone;
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({this.existing});
  final EmergencyContact? existing;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phoneNumber ?? '');
  late String _category = widget.existing?.category ?? 'police';

  @override
  void dispose() {
    _label.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a number' : 'Edit number'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'e.g. Lipa City Police (PNP)'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name residents will recognise' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final c in kContactCategories)
                    DropdownMenuItem(value: c, child: Text(_categoryLabel(c))),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone number', hintText: 'e.g. +63 917 123 4567'),
                validator: validateContactNumber,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                _ContactForm(_label.text.trim(), _category, _phone.text.trim()),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
