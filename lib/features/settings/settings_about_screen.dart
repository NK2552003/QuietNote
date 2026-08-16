import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/settings/widgets/settings_widgets.dart';

/// App identity, solo developer info, privacy policy, terms of service,
/// and publication compliance.
class SettingsAboutScreen extends ConsumerWidget {
  const SettingsAboutScreen({super.key});

  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '1';
  static const String _supportEmail = 'sid.kr.222003@gmail.com';

  void _showPrivacyPolicyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.ui;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.shield_outlined, color: theme.colors.primary, size: 24),
              const SizedBox(width: 10),
              const Text('Privacy Policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last updated: August 2026',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
                ),
                SizedBox(height: 12),
                _PolicySection(
                  title: '1. Zero Personal Data Collection',
                  body: 'QuietNote does not collect, harvest, monetize, or transmit your personal data. We do not maintain any user accounts or remote database sync servers.',
                ),
                _PolicySection(
                  title: '2. 100% Local Storage',
                  body: 'All your notes, journal entries, tasks, habits, routines, goals, calendar events, courses, flashcards, and focus timers are stored exclusively on your device in a local SQLite database.',
                ),
                _PolicySection(
                  title: '3. AI Capture & On-Device Processing',
                  body: 'When utilizing local AI (Gemma), prompts and inferences are processed entirely on your device without sending text across the internet. If you configure a Cloud API key, requests are routed directly to the selected provider using your credentials.',
                ),
                _PolicySection(
                  title: '4. No Third-Party Trackers or Ads',
                  body: 'QuietNote contains zero third-party advertising SDKs, zero behavioral tracking frameworks, and zero analytics telemetry libraries.',
                ),
                _PolicySection(
                  title: '5. Data Control & Deletion',
                  body: 'You own your data completely. You can export a full JSON/Markdown backup at any time. Clearing the app cache or uninstalling the app permanently erases all local data from your device.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.ui;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.gavel_outlined, color: theme.colors.primary, size: 24),
              const SizedBox(width: 10),
              const Text('Terms of Service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last updated: August 2026',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
                ),
                SizedBox(height: 12),
                _PolicySection(
                  title: '1. Software License',
                  body: 'QuietNote is provided as a personal productivity and study application. You are granted a personal, non-exclusive license to use the app on your personal devices.',
                ),
                _PolicySection(
                  title: '2. User Ownership of Content',
                  body: 'You retain complete ownership and responsibility for all notes, reflections, routines, and materials created or stored inside QuietNote.',
                ),
                _PolicySection(
                  title: '3. Offline Nature & Backups',
                  body: 'Because QuietNote operates without a cloud server, regular backups via the Settings Data Export tool are recommended to protect against physical device damage or loss.',
                ),
                _PolicySection(
                  title: '4. Disclaimer of Warranty',
                  body: 'The software is provided on an "as is" and "as available" basis without warranties of any kind, either express or implied.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showSupportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.ui;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.favorite_rounded, color: theme.colors.primary, size: 24),
              const SizedBox(width: 10),
              const Text('Support Project', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'QuietNote is 100% free, private, and ad-free. Direct financial contributions and coffee tips are coming soon in a future release!',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'In the meantime, the best way to support is sharing feedback, feature requests, or reporting bugs directly:',
                style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline_rounded, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: SelectableText(
                        _supportEmail,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copy email',
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: _supportEmail));
                        Navigator.of(ctx).pop();
                        UiToast.show(
                          context,
                          title: 'Email copied',
                          message: 'Developer email copied to clipboard.',
                          intent: UiIntent.primary,
                          icon: Icons.check_circle_outline,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showBuyMeACoffeeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.ui;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.local_cafe_rounded, color: theme.colors.warning, size: 24),
              const SizedBox(width: 10),
              const Text('Buy Me a Coffee', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Coming Soon',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'QuietNote is completely free, 100% private, and ad-free. Sponsorships and coffee contributions will be supported soon in an upcoming update.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'Thank you for using QuietNote and supporting independent software development!',
                style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showChangelogDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = ctx.ui;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : theme.colors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.history_rounded,
                  color: theme.colors.primary, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'What\'s New · Changelog',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Version $_appVersion (Build $_buildNumber)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colors.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'F-Droid Release',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _ChangelogItem(
                  icon: Icons.shield_rounded,
                  title: '100% Privacy & Biometric Security',
                  body:
                      'Complete offline-first architecture with zero tracking and native fingerprint/face/screen lock.',
                ),
                const _ChangelogItem(
                  icon: Icons.dock_rounded,
                  title: 'Customizable Navigation Dock',
                  body:
                      'Calibrated sizing (Compact, Standard, Spacious) and ergonomic hand positioning (Left, Center, Right).',
                ),
                const _ChangelogItem(
                  icon: Icons.timer_rounded,
                  title: 'Zen Focus & Study Suite',
                  body:
                      'Custom interval focus timers with ambient bells and optional dynamic island edge pill overlay.',
                ),
                const _ChangelogItem(
                  icon: Icons.edit_note_rounded,
                  title: 'Rich Markdown Notes',
                  body:
                      'Distraction-free editor with LaTeX math formulas, 150+ code language syntax highlighting, and PDF export.',
                ),
                const _ChangelogItem(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Tasks, Habits & Routines',
                  body:
                      'Daily task priorities, subtasks, habit streak tracker, and morning/evening structured routines.',
                ),
                const _ChangelogItem(
                  icon: Icons.school_rounded,
                  title: 'Courses, Flashcards & Agendas',
                  body:
                      'Spaced repetition flashcards with active recall ratings, course schedules, and calendar timeline.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.ui;
    return SettingsSubPage(
      title: 'About',
      subtitle: 'Solo developer, privacy promise, and publication details.',
      children: <Widget>[
        // ── Main Identity Card ──
        UiCard(
          variant: UiCardVariant.elevated,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const QuietNoteMark(size: 52),
                  SizedBox(width: context.sp(theme.spacing.md)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('QuietNote', style: context.uiText.title),
                        const SizedBox(height: 2),
                        Text(
                          'Version $_appVersion (Build $_buildNumber)',
                          style: context.uiText.caption
                              .copyWith(color: theme.colors.foregroundMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.sp(theme.spacing.md)),
              Text(
                'A private, offline-first study suite and personal productivity system designed for calm focus, knowledge organization, and structured mastery.',
                style: context.uiText.body.copyWith(height: 1.45),
              ),
              SizedBox(height: context.sp(theme.spacing.md)),
              UiButton(
                label: 'What\'s New in v$_appVersion',
                variant: UiVariant.secondary,
                size: UiSize.sm,
                leadingIcon: Icons.history_rounded,
                onPressed: () => _showChangelogDialog(context),
              ),
            ],
          ),
        ),
        SizedBox(height: context.sp(theme.spacing.xl)),

        // ── Solo Developer Section ──
        SettingsSection(
          title: 'Solo Developer',
          children: <Widget>[
            const SettingsTile(
              icon: Icons.person_outline_rounded,
              title: 'Independent Project',
              description: 'Crafted with care as a solo endeavor focusing on minimalism and user privacy.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Support & Inquiries',
              description: _supportEmail,
              onTap: () => _showSupportDialog(context),
            ),
            SettingsTile(
              icon: Icons.favorite_outline_rounded,
              title: 'Support Project',
              description: 'Financial support coming soon • Reach out with feedback',
              onTap: () => _showSupportDialog(context),
            ),
            SettingsTile(
              icon: Icons.local_cafe_outlined,
              title: 'Buy Me a Coffee',
              description: 'Coming soon',
              onTap: () => _showBuyMeACoffeeDialog(context),
            ),
            SettingsTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Send Feedback & Ideas',
              description: 'Share suggestions to help shape future updates.',
              onTap: () => _showSupportDialog(context),
            ),
          ],
        ),

        // ── Privacy & Trust (Publication Requirements) ──
        SettingsSection(
          title: 'Privacy & Data Protection',
          children: <Widget>[
            SettingsTile(
              icon: Icons.shield_outlined,
              title: 'Privacy Policy',
              description: 'Zero telemetry, zero ads, and no user tracking.',
              onTap: () => _showPrivacyPolicyDialog(context),
            ),
            const SettingsTile(
              icon: Icons.storage_rounded,
              title: '100% Local SQLite Database',
              description: 'Your notes, journals, tasks, and habits never leave this device.',
              showChevron: false,
            ),
            const SettingsTile(
              icon: Icons.memory_rounded,
              title: 'On-Device AI Privacy',
              description: 'Gemma runs locally on hardware with no remote data uploads.',
              showChevron: false,
            ),
            const SettingsTile(
              icon: Icons.wifi_off_rounded,
              title: 'Offline-First Architecture',
              description: 'Full functionality available without an internet connection.',
              showChevron: false,
            ),
          ],
        ),

        // ── Legal & Compliance (Store Requirements) ──
        SettingsSection(
          title: 'Legal & Compliance',
          children: <Widget>[
            SettingsTile(
              icon: Icons.history_edu_rounded,
              title: 'Changelog & Release Notes',
              description: 'See all new features, improvements, and fixes in v$_appVersion.',
              onTap: () => _showChangelogDialog(context),
            ),
            SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Terms of Service',
              description: 'Standard software license and data ownership guidelines.',
              onTap: () => _showTermsDialog(context),
            ),
            SettingsTile(
              icon: Icons.code_rounded,
              title: 'Open Source Licenses',
              description: 'Third-party software libraries and dependencies.',
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'QuietNote',
                  applicationVersion: 'Version $_appVersion (Build $_buildNumber)',
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: QuietNoteMark(size: 48),
                  ),
                  applicationLegalese: 'Copyright 2026 Nitish Kumar. All rights reserved.',
                );
              },
            ),
          ],
        ),

        // ── Technology Stack ──
        const SettingsSection(
          title: 'Architecture & Frameworks',
          children: <Widget>[
            SettingsTile(
              icon: Icons.flutter_dash,
              title: 'Flutter & Dart',
              description: 'High-performance reactive frontend framework.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.alt_route_rounded,
              title: 'Riverpod State Management',
              description: 'Robust, compile-safe reactive state architecture.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.dns_outlined,
              title: 'Drift & SQLite',
              description: 'Typed local persistence engine with automated schema migrations.',
              showChevron: false,
            ),
            SettingsTile(
              icon: Icons.palette_outlined,
              title: 'QuietNote Custom Design System',
              description: 'Handcrafted responsive UI kit adhering to minimal aesthetics.',
              showChevron: false,
            ),
          ],
        ),

        // ── Maintenance & Setup ──
        SettingsSection(
          title: 'Setup & Onboarding',
          children: <Widget>[
            SettingsTile(
              icon: Icons.restart_alt_rounded,
              title: 'Replay Onboarding',
              description: 'Walk through the initial setup and feature overview again.',
              onTap: () async {
                await ref.read(settingsProvider.notifier).update(
                      (AppSettings s) => s.copyWith(onboardingComplete: false),
                    );
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ],
        ),
        SizedBox(height: context.sp(theme.spacing.xxl)),
      ],
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ChangelogItem extends StatelessWidget {
  const _ChangelogItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: theme.colors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


