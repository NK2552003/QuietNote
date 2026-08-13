import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

import 'capture_parser.dart';
import 'capture_actions.dart';
import 'capture_review_sheet.dart';
import 'local_ai_engine.dart';
import 'ai_voice_service.dart';

const List<String> _examplePrompts = [
  'Call mom tomorrow at 6pm',
  'Buy groceries after work',
  'Team sync every Monday at 10am',
  'Today I felt grateful for my friends',
  'Read 20 pages every night',
  'Save \$500 by December',
];

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _captureCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<CaptureSaveResult> _recent = [];

  late final AnimationController _pulseController;
  bool _isProcessing = false;
  CaptureDraft? _draft;
  bool _quickSaving = false;
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  bool _isAnswering = false;
  String? _answer;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _captureCtrl.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final text = _captureCtrl.text.trim();
    if (text.isEmpty || _isProcessing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isProcessing = true;
      _draft = null;
    });

    // A short, deliberate delay keeps the "thinking" animation legible and
    // gives room for on-device model enrichment when one is installed —
    // parsing itself is instant and never blocks on the model being ready.
    final aiState = ref.read(aiEngineProvider);
    await Future.delayed(const Duration(milliseconds: 550));

    final draft = CaptureParser.parse(text);
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    // Honour the user’s chosen default when the parser is genuinely unsure,
    // while preserving confident interpretations such as explicit dates.
    if (draft.confidence < 0.60) {
      draft.type = _captureTypeFor(settings.captureDefaultTarget);
    }

    if (aiState == AiEngineState.ready) {
      try {
        // Enrichment layer: when a FunctionGemma model is installed, let it
        // refine the free-text into a cleaner title/summary. The heuristic
        // classification (type, dates, mood, priority) is kept either way —
        // the model only touches the text, never the destination guess, so
        // a partial or odd model reply can't misfile the capture.
        final refined = await ref
            .read(aiEngineProvider.notifier)
            .parseAction(text);
        final refinedText = refined['text']?.toString().trim();
        if (refinedText != null && refinedText.isNotEmpty) {
          draft.title = CaptureParser.parse(refinedText).title;
        }
      } catch (_) {
        // Model enrichment is best-effort; the heuristic draft already stands.
      }
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _draft = draft;
    });
    if (settings.captureAutoSave && draft.confidence >= 0.85) {
      await _quickSave();
    }
  }

  Future<void> _askAi() async {
    final text = _captureCtrl.text.trim();
    if (text.isEmpty || _isAnswering) return;
    if (ref.read(aiEngineProvider) != AiEngineState.ready) {
      UiToast.show(
        context,
        title: 'Add a local model first',
        message:
            'AI Capture can still sort your text without a model, but questions need one.',
        intent: UiIntent.info,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isAnswering = true;
      _answer = null;
    });
    try {
      final answer = await ref.read(aiEngineProvider.notifier).answer(text);
      if (mounted) setState(() => _answer = answer);
    } catch (error) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'AI could not respond',
          message: '$error',
          intent: UiIntent.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isAnswering = false);
    }
  }

  Future<void> _toggleSpeech() async {
    if (_speaking) {
      await AiVoiceService.instance.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    if (_answer == null) return;
    setState(() => _speaking = true);
    try {
      await AiVoiceService.instance.speak(_answer!);
    } catch (_) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Speech output unavailable',
          message:
              'Install or enable a device text-to-speech voice and try again.',
          intent: UiIntent.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  CaptureType _captureTypeFor(String value) => switch (value) {
    'note' => CaptureType.note,
    'journal' => CaptureType.journal,
    'event' => CaptureType.event,
    'routine' => CaptureType.routine,
    _ => CaptureType.todo,
  };

  Future<void> _toggleVoiceInput() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _listening = false);
          UiToast.show(
            context,
            title: 'Voice input unavailable',
            message: 'Check microphone and speech recognition permissions.',
            intent: UiIntent.warning,
          );
        }
      },
    );
    if (!available) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'Voice input unavailable',
          message:
              'Enable microphone and speech recognition access to use voice capture.',
          intent: UiIntent.warning,
        );
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        _captureCtrl.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
        );
        setState(() => _listening = _speech.isListening);
      },
    );
  }

  void _discardDraft() {
    setState(() => _draft = null);
  }

  void _reclassify(CaptureType type) {
    if (_draft == null) return;
    setState(() => _draft!.type = type);
  }

  void _onSaved(CaptureSaveResult result) {
    _captureCtrl.clear();
    setState(() => _draft = null);
    _recent.insert(0, result);
    _listKey.currentState?.insertItem(
      0,
      duration: const Duration(milliseconds: 320),
    );
    if (_recent.length > 12) {
      _recent.removeLast();
    }
    if (!mounted) return;
    UiToast.show(
      context,
      title: 'Saved as ${result.type.shortLabel}',
      message: result.title,
      intent: UiIntent.success,
      icon: Icons.check_circle_outline,
    );
  }

  Future<void> _openReview() async {
    if (_draft == null) return;
    final result = await UiDialog.show<CaptureSaveResult>(
      context,
      child: CaptureReviewSheet(initial: _draft!),
    );
    if (result != null) _onSaved(result);
  }

  Future<void> _quickSave() async {
    if (_draft == null || _quickSaving) return;
    setState(() => _quickSaving = true);
    try {
      final result = await saveCaptureDraft(ref, _draft!);
      if (!mounted) return;
      setState(() => _quickSaving = false);
      _onSaved(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _quickSaving = false);
      UiToast.show(
        context,
        title: 'Could not save capture',
        message: '$e',
        intent: UiIntent.danger,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiEngineProvider);
    final c = context.uiColors;

    return UiPage(
      header: UiHeader(
        title: 'AI Capture',
        subtitle: 'Intelligent AI assistant to organize your life effortlessly.',
        actions: [
          UiIconButton(
            icon: Icons.tune_outlined,
            tooltip: 'Model settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModelStatusBanner(state: aiState),
          const SizedBox(height: 16),
          _Composer(
            controller: _captureCtrl,
            focusNode: _focusNode,
            isProcessing: _isProcessing,
            pulseController: _pulseController,
            onCapture: _capture,
            listening: _listening,
            onVoiceInput: _toggleVoiceInput,
            onAsk: _askAi,
            canAsk: aiState == AiEngineState.ready,
            answering: _isAnswering,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _isAnswering
                ? const UiCard(
                    key: ValueKey('answering'),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Thinking on this device…'),
                      ],
                    ),
                  )
                : _answer == null
                ? const SizedBox.shrink(key: ValueKey('no-answer'))
                : UiCard(
                    key: const ValueKey('answer'),
                    accentColor: context.uiColors.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 17,
                              color: context.uiColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI response',
                              style: context.uiText.bodyStrong,
                            ),
                            const Spacer(),
                            UiIconButton(
                              icon: _speaking
                                  ? Icons.stop_circle_outlined
                                  : Icons.volume_up_outlined,
                              tooltip: _speaking
                                  ? 'Stop speaking'
                                  : 'Read response aloud',
                              onPressed: _toggleSpeech,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(_answer!, style: context.uiText.body),
                      ],
                    ),
                  ),
          ),
          if (_answer != null || _isAnswering) const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in _examplePrompts)
                _SuggestionChip(
                  label: prompt,
                  onTap: _isProcessing
                      ? null
                      : () {
                          _captureCtrl.text = prompt;
                          _captureCtrl.selection = TextSelection.collapsed(
                            offset: prompt.length,
                          );
                          _focusNode.requestFocus();
                        },
                ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, child: child),
            ),
            child: _draft == null
                ? const SizedBox.shrink(key: ValueKey('no-draft'))
                : _DraftPreview(
                    key: ValueKey(_draft.hashCode),
                    draft: _draft!,
                    saving: _quickSaving,
                    onDiscard: _discardDraft,
                    onReclassify: _reclassify,
                    onAdjust: _openReview,
                    onQuickSave: _quickSave,
                  ),
          ),
          if (_draft != null) const SizedBox(height: 24),
          Row(
            children: [
              Icon(Icons.history, size: 16, color: c.foregroundMuted),
              const SizedBox(width: 6),
              Text('Recently captured', style: context.uiText.bodyStrong),
            ],
          ),
          const SizedBox(height: 10),
          if (_recent.isEmpty)
            const UiEmptyState(
              title: 'Nothing captured yet',
              message: 'Whatever you capture this session shows up here.',
              icon: Icons.auto_awesome,
            )
          else
            SizedBox(
              height: _recent.length.clamp(1, 5) * 72.0,
              child: AnimatedList(
                key: _listKey,
                initialItemCount: _recent.length,
                itemBuilder: (context, index, animation) {
                  if (index >= _recent.length) return const SizedBox.shrink();
                  final item = _recent[index];
                  return SizeTransition(
                    sizeFactor: animation,
                    child: FadeTransition(
                      opacity: animation,
                      child: _RecentCaptureTile(result: item),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({required this.state});
  final AiEngineState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case AiEngineState.ready:
        return const UiCallout(
          intent: UiIntent.success,
          icon: Icons.memory,
          title: 'On-device model active',
          message:
              'FunctionGemma is installed — captures are enriched locally, nothing leaves this device.',
        );
      case AiEngineState.importing:
        return const UiCallout(
          intent: UiIntent.info,
          icon: Icons.downloading_outlined,
          title: 'Importing model…',
          message:
              'Capture still works with the built-in parser while this finishes.',
        );
      case AiEngineState.failed:
        return UiCallout(
          intent: UiIntent.warning,
          icon: Icons.warning_amber_rounded,
          title: 'Model failed to load',
          message:
              'Falling back to the built-in parser. You can retry the import from Settings.',
          action: UiButton(
            label: 'Open Settings',
            variant: UiVariant.soft,
            size: UiSize.sm,
            expandOnMobile: false,
            onPressed: () => context.push('/settings'),
          ),
        );
      case AiEngineState.missingModel:
        return UiCallout(
          intent: UiIntent.info,
          icon: Icons.bolt_outlined,
          title: 'Running the built-in parser',
          message:
              'Add a local FunctionGemma model in Settings for smarter, on-device phrasing.',
          action: UiButton(
            label: 'Add model',
            variant: UiVariant.soft,
            size: UiSize.sm,
            expandOnMobile: false,
            onPressed: () => context.push('/settings'),
          ),
        );
    }
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isProcessing,
    required this.pulseController,
    required this.onCapture,
    required this.listening,
    required this.onVoiceInput,
    required this.onAsk,
    required this.canAsk,
    required this.answering,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isProcessing;
  final AnimationController pulseController;
  final VoidCallback onCapture;
  final bool listening;
  final VoidCallback onVoiceInput;
  final VoidCallback onAsk;
  final bool canAsk;
  final bool answering;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return UiCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ThinkingAvatar(
                controller: pulseController,
                active: isProcessing,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UiInput.multiline(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: 'Type anything — a task, an idea, how today went…',
                  enabled: !isProcessing,
                  maxLines: 4,
                  minLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: c.foregroundSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Parsed entirely on this device.',
                  style: context.uiText.caption.copyWith(
                    color: c.foregroundSubtle,
                  ),
                ),
              ),
              UiButton(
                label: isProcessing ? 'Thinking…' : 'Capture',
                leadingIcon: isProcessing ? null : Icons.auto_awesome,
                loading: isProcessing,
                expandOnMobile: false,
                onPressed: isProcessing ? null : onCapture,
              ),
              const SizedBox(width: 8),
              UiIconButton(
                icon: Icons.chat_bubble_outline,
                variant: UiVariant.secondary,
                tooltip: canAsk ? 'Ask local AI' : 'Add a model to ask AI',
                onPressed: isProcessing || answering || !canAsk ? null : onAsk,
              ),
              const SizedBox(width: 8),
              UiIconButton(
                icon: listening
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none_rounded,
                variant: listening ? UiVariant.primary : UiVariant.secondary,
                tooltip: listening ? 'Stop listening' : 'Speak your capture',
                onPressed: isProcessing ? null : onVoiceInput,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small pulsing sparkle avatar shown next to the composer while a capture
/// is being classified — the screen's signature "thinking" animation.
class _ThinkingAvatar extends StatelessWidget {
  const _ThinkingAvatar({required this.controller, required this.active});
  final AnimationController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = active ? controller.value : 0.0;
        final scale = 1.0 + (active ? t * 0.18 : 0.0);
        final glow = active ? 0.10 + t * 0.18 : 0.10;
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.primary.withValues(alpha: glow),
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            child: Icon(Icons.auto_awesome, size: 20, color: c.primary),
          ),
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
        ),
        child: Text(
          label,
          style: context.uiText.caption.copyWith(color: c.foregroundMuted),
        ),
      ),
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({
    super.key,
    required this.draft,
    required this.saving,
    required this.onDiscard,
    required this.onReclassify,
    required this.onAdjust,
    required this.onQuickSave,
  });

  final CaptureDraft draft;
  final bool saving;
  final VoidCallback onDiscard;
  final ValueChanged<CaptureType> onReclassify;
  final VoidCallback onAdjust;
  final VoidCallback onQuickSave;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final pct = (draft.confidence * 100).round();

    return UiCard(
      accentColor: c.primary,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(draft.type.icon, size: 18, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(draft.title, style: context.uiText.bodyStrong),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        UiBadge(
                          label: draft.type.label,
                          intent: UiIntent.primary,
                          size: UiSize.sm,
                        ),
                        UiBadge(
                          label: '$pct% confidence',
                          intent: UiIntent.neutral,
                          size: UiSize.sm,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              UiIconButton(
                icon: Icons.close,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                onPressed: onDiscard,
              ),
            ],
          ),
          if (draft.alternates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Not quite right?',
              style: context.uiText.caption.copyWith(color: c.foregroundMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final alt in draft.alternates)
                  GestureDetector(
                    onTap: () => onReclassify(alt.type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            alt.type.icon,
                            size: 13,
                            color: c.foregroundMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Make it ${alt.type.shortLabel}',
                            style: context.uiText.caption.copyWith(
                              color: c.foregroundMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  label: 'Adjust & Save',
                  variant: UiVariant.secondary,
                  leadingIcon: Icons.tune_outlined,
                  onPressed: onAdjust,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: UiButton(
                  label: 'Quick Save',
                  leadingIcon: Icons.check,
                  loading: saving,
                  onPressed: onQuickSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentCaptureTile extends StatelessWidget {
  const _RecentCaptureTile({required this.result});
  final CaptureSaveResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: UiCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(result.type.icon, size: 16, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.uiText.body,
              ),
            ),
            UiBadge(
              label: result.type.shortLabel,
              intent: UiIntent.neutral,
              size: UiSize.sm,
            ),
          ],
        ),
      ),
    );
  }
}
