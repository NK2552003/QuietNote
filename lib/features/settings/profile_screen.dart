import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _loaded = false, _saving = false;
  String _imagePath = '';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _load(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _name.text = s.displayName == 'Student' ? '' : s.displayName;
    _email.text = s.profileEmail;
    _imagePath = s.profileImagePath;
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final image = await File(
      picked.path,
    ).copy('${dir.path}/profile_avatar.jpg');
    if (mounted) setState(() => _imagePath = image.path);
  }

  Future<void> _save() async {
    final name = _name.text.trim(), email = _email.text.trim();
    if (name.isEmpty) {
      UiToast.show(
        context,
        title: 'Add your name',
        message: 'A display name is required.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      UiToast.show(
        context,
        title: 'Check your email',
        message: 'Enter a valid email address or leave it blank.',
        intent: UiIntent.warning,
      );
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            displayName: name,
            profileEmail: email,
            profileImagePath: _imagePath,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    UiToast.show(
      context,
      title: 'Profile saved',
      message: 'Your changes stay on this device.',
      intent: UiIntent.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    _load(settings);
    final image = _imagePath.isNotEmpty && File(_imagePath).existsSync()
        ? FileImage(File(_imagePath))
        : null;
    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: 'Profile',
        subtitle: 'Stored only on this device.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(48),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: context.uiColors.primary.withValues(
                  alpha: .14,
                ),
                backgroundImage: image,
                child: image == null
                    ? Icon(
                        Icons.person_outline,
                        size: 42,
                        color: context.uiColors.primary,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Choose profile photo'),
            ),
          ),
          const SizedBox(height: 16),
          UiField(
            label: 'Name *',
            child: UiInput(controller: _name, hintText: 'Your name'),
          ),
          const SizedBox(height: 16),
          UiField(
            label: 'Email (optional)',
            child: UiInput(
              controller: _email,
              hintText: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          const SizedBox(height: 24),
          UiButton(
            label: 'Save profile',
            leadingIcon: Icons.check,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
