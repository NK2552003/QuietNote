import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_field.dart';
import 'ui_input.dart';

/// Multi-line text field (Textarea). Own component so screens read clearly;
/// the field chrome, focus ring and validation state come from [UiInput].
///
/// Adds: live character counter, label/helper wiring, auto-grow limits,
/// resize hint and an optional toolbar slot (e.g. formatting actions).
class UiTextarea extends StatefulWidget {
  const UiTextarea({
    super.key,
    this.controller,
    this.hintText,
    this.value,
    this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.errorText,
    this.helper,
    this.validation = UiValidationState.none,
    this.variant = UiInputVariant.outline,
    this.density = UiDensity.comfortable,
    this.size = UiSize.md,
    this.rows = 4,
    this.maxRows = 8,
    this.maxLength,
    this.showCounter = true,
    this.autofocus = false,
    this.focusNode,
    this.label,
    this.required = false,
    this.toolbar,
    this.footer,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? value;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool readOnly;
  final bool error;
  final String? errorText;
  final String? helper;
  final UiValidationState validation;
  final UiInputVariant variant;
  final UiDensity density;
  final UiSize size;

  /// Minimum visible rows.
  final int rows;

  /// Growth limit before the field scrolls internally.
  final int maxRows;
  final int? maxLength;
  final bool showCounter;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? label;
  final bool required;

  /// Optional action row rendered above the field (formatting, attachments).
  final Widget? toolbar;

  /// Optional row rendered under the field (submit actions, hints).
  final Widget? footer;

  @override
  State<UiTextarea> createState() => _UiTextareaState();
}

class _UiTextareaState extends State<UiTextarea> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.value ?? '');
    _controller.addListener(_onText);
  }

  void _onText() {
    if (mounted && widget.showCounter) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final int length = _controller.text.characters.length;

    return UiField(
      label: widget.label,
      required: widget.required,
      helper: widget.helper,
      error: widget.errorText,
      enabled: widget.enabled,
      density: widget.density,
      counter: widget.showCounter
          ? (widget.maxLength == null ? '$length' : '$length/${widget.maxLength}')
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.toolbar != null) ...<Widget>[
            widget.toolbar!,
            SizedBox(height: context.sp(theme.spacing.xs)),
          ],
          UiInput.multiline(
            controller: _controller,
            hintText: widget.hintText,
            onChanged: widget.onChanged,
            enabled: widget.enabled,
            readOnly: widget.readOnly,
            error: widget.error || widget.errorText != null,
            validation: widget.validation,
            variant: widget.variant,
            density: widget.density,
            size: widget.size,
            minLines: widget.rows,
            maxLines: widget.maxRows < widget.rows ? widget.rows : widget.maxRows,
            maxLength: widget.maxLength,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
          ),
          if (widget.footer != null) ...<Widget>[
            SizedBox(height: context.sp(theme.spacing.sm)),
            widget.footer!,
          ],
        ],
      ),
    );
  }
}
