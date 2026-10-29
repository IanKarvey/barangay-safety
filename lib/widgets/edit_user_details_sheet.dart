import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/audit_service.dart';
import '../services/user_management_service.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import '../widgets/app_text.dart';

/// Correct another account's name, phone or address.
///
/// The address field is why this exists: it is what a responder navigates to,
/// and until now a resident who mistyped it at signup was the only person who
/// could fix it — an official looking at a wrong address could see the problem
/// and do nothing about it.
///
/// Shared by the barangay roster and the city-wide roster so the two cannot
/// drift into editing different fields or logging differently.
///
/// Returns `true` if something was saved, so the caller knows to reload.
Future<bool> showEditUserDetailsSheet(
  BuildContext context,
  UserModel user,
) async {
  final official = context.read<AuthProvider>().user;
  if (official == null) return false;

  final nameCtrl = TextEditingController(text: user.fullName);
  final phoneCtrl = TextEditingController(text: user.phone);
  final addressCtrl = TextEditingController(text: user.address ?? '');
  final formKey = GlobalKey<FormState>();

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(ctx.s.editDetails, style: AppTextStyles.heading3),
              const SizedBox(height: 4),
              AppText(user.email, style: AppTextStyles.bodySmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: ctx.s.fullName),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? ctx.s.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: ctx.s.phoneNumber),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? ctx.s.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: addressCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: ctx.s.address),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: AppText(ctx.s.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: AppText(ctx.s.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Read the controllers before disposing them — the sheet is gone by now, so
  // this is the last moment the typed text exists.
  final newName = nameCtrl.text.trim();
  final newPhone = phoneCtrl.text.trim();
  final newAddress = addressCtrl.text.trim();
  nameCtrl.dispose();
  phoneCtrl.dispose();
  addressCtrl.dispose();

  if (confirmed != true || !context.mounted) return false;

  try {
    await UserManagementService().updateUserDetails(
      userId: user.id,
      fullName: newName,
      phone: newPhone,
      address: newAddress.isEmpty ? null : newAddress,
    );

    // Named field by field. "Edited a profile" in the log tells a reviewer
    // nothing about whether the edit was legitimate.
    final changes = <String>[
      if (newName != user.fullName) 'name',
      if (newPhone != user.phone) 'phone',
      if (newAddress != (user.address ?? '')) 'address',
    ];
    await AuditService().logAction(
      userId: official.id,
      action: 'user_details_edited',
      details: changes.isEmpty
          ? 'Opened ${user.fullName} for editing, changed nothing'
          : 'Edited ${changes.join(", ")} for ${user.fullName}',
    );

    if (context.mounted) {
      showSuccessSnackbar(context, context.s.detailsUpdated);
    }
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnackbar(context, 'Could not save: $e');
    return false;
  }
}
