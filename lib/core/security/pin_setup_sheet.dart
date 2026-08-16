import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/security/widgets/pin_dots_indicator.dart';
import 'package:quietnote/core/security/widgets/pin_keypad.dart';

/// Professional 2-step PIN creation & confirmation bottom sheet with frosted glass blur.
class PinSetupSheet extends StatefulWidget {
  const PinSetupSheet({
    super.key,
    this.currentPin = '',
    required this.accentColor,
  });

  final String currentPin;
  final Color accentColor;

  static Future<String?> show(
    BuildContext context, {
    String currentPin = '',
    required Color accentColor,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PinSetupSheet(
        currentPin: currentPin,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<PinSetupSheet> {
  static const int _pinLength = 4;

  int _step = 1; // 1 = Enter new PIN, 2 = Confirm new PIN
  String _firstPin = '';
  String _secondPin = '';
  String? _errorMessage;
  bool _hasError = false;

  void _onDigitPressed(String digit) {
    if (_hasError) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
    }

    if (_step == 1) {
      if (_firstPin.length < _pinLength) {
        setState(() {
          _firstPin += digit;
        });

        if (_firstPin.length == _pinLength) {
          // Transition to Step 2
          Future.delayed(const Duration(milliseconds: 220), () {
            if (!mounted) return;
            setState(() {
              _step = 2;
              _secondPin = '';
              _errorMessage = null;
            });
            HapticFeedback.lightImpact();
          });
        }
      }
    } else {
      if (_secondPin.length < _pinLength) {
        setState(() {
          _secondPin += digit;
        });

        if (_secondPin.length == _pinLength) {
          // Verify confirmation
          if (_firstPin == _secondPin) {
            HapticFeedback.mediumImpact();
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                Navigator.of(context).pop(_firstPin);
              }
            });
          } else {
            // Mismatch
            HapticFeedback.vibrate();
            setState(() {
              _hasError = true;
              _errorMessage = 'PINs did not match. Please try again.';
              _secondPin = '';
              _firstPin = '';
              _step = 1;
            });
          }
        }
      }
    }
  }

  void _onBackspacePressed() {
    if (_step == 1 && _firstPin.isNotEmpty) {
      setState(() {
        _firstPin = _firstPin.substring(0, _firstPin.length - 1);
        _hasError = false;
        _errorMessage = null;
      });
    } else if (_step == 2 && _secondPin.isNotEmpty) {
      setState(() {
        _secondPin = _secondPin.substring(0, _secondPin.length - 1);
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  void _onClearAll() {
    setState(() {
      _firstPin = '';
      _secondPin = '';
      _step = 1;
      _hasError = false;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String activePin = _step == 1 ? _firstPin : _secondPin;

    final String title = widget.currentPin.isEmpty
        ? (_step == 1 ? 'Create Passcode' : 'Confirm Passcode')
        : (_step == 1 ? 'New Passcode' : 'Confirm New Passcode');

    final String subtitle = _step == 1
        ? 'Enter a 4-digit PIN to secure QuietNote'
        : 'Re-enter your 4-digit PIN to confirm';

    final Color sheetBg = isDark
        ? const Color(0xFF1B1A18).withValues(alpha: 0.94)
        : const Color(0xFFFAF8F5).withValues(alpha: 0.95);

    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header Row with Cancel & Remove
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: theme.colors.foregroundMuted,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (widget.currentPin.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(''),
                      child: Text(
                        'Remove PIN',
                        style: TextStyle(
                          color: theme.colors.destructive,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 60),
                ],
              ),

              const SizedBox(height: 8),

              // Animated Title & Subtitle with step transition
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Column(
                  key: ValueKey('step_header_$_step'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.uiText.title.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: context.uiText.caption.copyWith(
                        color: theme.colors.foregroundMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // PIN Dots Indicator
              PinDotsIndicator(
                pinLength: _pinLength,
                enteredLength: activePin.length,
                accentColor: widget.accentColor,
                hasError: _hasError,
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: context.uiText.caption.copyWith(
                    color: theme.colors.destructive,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 28),
              ],

              // Tactile Keypad
              PinKeypad(
                onDigitPressed: _onDigitPressed,
                onBackspacePressed: _onBackspacePressed,
                onBackspaceLongPressed: _onClearAll,
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
