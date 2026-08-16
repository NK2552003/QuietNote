import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/database.dart';

import 'capture_parser.dart';
import 'capture_actions.dart';
import 'ai_conversation_engine.dart';
import 'ai_question_model.dart';
import 'local_ai_engine.dart';
import 'cloud_ai_providers.dart';
import 'ai_voice_service.dart';
import 'ai_waveform_visualizer.dart';
import 'ai_typewriter_text.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

// ---------------------------------------------------------------------------
// Screen modes
// ---------------------------------------------------------------------------

enum _AiMode { compose, conversation, review, answer }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen>
    with SingleTickerProviderStateMixin {
  // ── Compose state ─────────────────────────────────────────────────────────
  final TextEditingController _composeCtrl = TextEditingController();
  final FocusNode _composeFocus = FocusNode();
  late final AnimationController _pulseController;
  bool _isProcessing = false;
  CaptureDraft? _livePrediction;

  // ── Conversation state ────────────────────────────────────────────────────
  AiConversationSession? _session;
  final TextEditingController _answerTextCtrl = TextEditingController();
  bool _isSaving = false;

  // ── Answer/Q&A mode ───────────────────────────────────────────────────────
  bool _isAnswering = false;
  String? _aiAnswer;
  bool _speaking = false;
  bool _savingAnswer = false;
  final List<AiChatTurn> _chatHistory = [];

  // ── Voice input ───────────────────────────────────────────────────────────
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  // ── Recent saves ──────────────────────────────────────────────────────────
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<CaptureSaveResult> _recent = [];

  // ── Current mode ─────────────────────────────────────────────────────────
  _AiMode _mode = _AiMode.compose;

  // ── Async loading (AI flashcard generation etc.) ──────────────────────────
  bool _enriching = false;

  // ── AI Write state (AI writing field content in conversation steps) ────────
  bool _aiWriting = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _composeCtrl.addListener(_onComposeChanged);
  }

  void _onComposeChanged() {
    final text = _composeCtrl.text.trim();
    if (text.length < 3) {
      if (_livePrediction != null) {
        setState(() => _livePrediction = null);
      }
      return;
    }
    final pred = CaptureParser.parse(text);
    if (_livePrediction?.type != pred.type ||
        (_livePrediction?.confidence != pred.confidence)) {
      setState(() => _livePrediction = pred);
    }
  }

  @override
  void dispose() {
    _composeCtrl.removeListener(_onComposeChanged);
    _composeCtrl.dispose();
    _composeFocus.dispose();
    _pulseController.dispose();
    _answerTextCtrl.dispose();
    super.dispose();
  }

  // ── Capture → start conversation ─────────────────────────────────────────

  Future<void> _startCapture() async {
    final text = _composeCtrl.text.trim();
    if (text.isEmpty || _isProcessing) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final notifier = ref.read(aiEngineProvider.notifier);

    CaptureDraft draft;
    try {
      draft = await notifier.buildDraft(
        text,
        fallbackType: _captureTypeFor(settings.captureDefaultTarget),
      );
    } catch (_) {
      draft = CaptureParser.parse(text);
      if (draft.confidence < 0.60) {
        draft.type = _captureTypeFor(settings.captureDefaultTarget);
      }
    }

    if (!mounted) return;

    // Polish title in background (non-blocking)
    notifier.polishTitle(draft.title, draft.type).then((polished) {
      if (mounted && _session != null && polished != draft.title) {
        setState(() {
          _session = _session!.copyWith(
            draft: _session!.draft..title = polished,
          );
        });
      }
    });

    // Build conversation session
    final session = AiConversationEngine.start(draft.type, draft);
    _answerTextCtrl.clear();

    setState(() {
      _isProcessing = false;
      _session = session;
      _mode = _AiMode.conversation;
    });

    // For flashcards: trigger async AI generation
    if (draft.type == CaptureType.flashcard) {
      _generateFlashcards(draft.title);
    }
    // For goals: suggest milestones in background
    if (draft.type == CaptureType.goal && notifier.canGenerate) {
      _suggestMilestones(draft.title, draft.goalTarget, draft.goalUnit);
    }
  }

  Future<void> _generateFlashcards(String topic) async {
    if (!mounted) return;
    setState(() => _enriching = true);
    try {
      final notifier = ref.read(aiEngineProvider.notifier);
      final pairs = await notifier.generateFlashcards(topic, count: 5);
      if (!mounted) return;
      if (pairs.isNotEmpty && _session != null) {
        final newPairs = pairs
            .map((p) => AiFlashcardPair(front: p.front, back: p.back))
            .toList();
        setState(() {
          _session = _session!.copyWith(
            draft: _session!.draft..flashcardPairs = newPairs,
          );
        });
      }
    } catch (_) {
      // Silently fail — user can add cards manually
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _suggestMilestones(String title, double target, String unit) async {
    try {
      final notifier = ref.read(aiEngineProvider.notifier);
      final milestones = await notifier.suggestGoalMilestones(
        title, target, unit: unit.isEmpty ? null : unit,
      );
      if (!mounted || milestones.isEmpty || _session == null) return;
      setState(() {
        _session = _session!.copyWith(
          draft: _session!.draft..milestones = milestones,
        );
      });
    } catch (_) {
      // Silently fail
    }
  }

  Future<void> _enrichSubtasks() async {
    if (_session == null || _enriching) return;
    setState(() => _enriching = true);
    HapticFeedback.lightImpact();
    try {
      final notifier = ref.read(aiEngineProvider.notifier);
      final subtasks = await notifier.generateSubtasks(_session!.draft.title);
      if (mounted && subtasks.isNotEmpty) {
        setState(() {
          _session = _session!.copyWith(
            draft: _session!.draft..subtasks = subtasks,
          );
        });
        UiToast.show(
          context,
          title: 'Subtasks generated',
          message: 'Added ${subtasks.length} actionable subtasks',
          intent: UiIntent.success,
        );
      }
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _enrichMilestones() async {
    if (_session == null || _enriching) return;
    setState(() => _enriching = true);
    HapticFeedback.lightImpact();
    try {
      final notifier = ref.read(aiEngineProvider.notifier);
      final milestones = await notifier.suggestGoalMilestones(
        _session!.draft.title,
        _session!.draft.goalTarget,
        unit: _session!.draft.goalUnit,
      );
      if (mounted && milestones.isNotEmpty) {
        setState(() {
          _session = _session!.copyWith(
            draft: _session!.draft..milestones = milestones,
          );
        });
        UiToast.show(
          context,
          title: 'Milestones generated',
          message: 'Added ${milestones.length} milestones',
          intent: UiIntent.success,
        );
      }
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _enrichPolishTitle() async {
    if (_session == null || _enriching) return;
    setState(() => _enriching = true);
    HapticFeedback.lightImpact();
    try {
      final notifier = ref.read(aiEngineProvider.notifier);
      final polished = await notifier.polishTitle(
        _session!.draft.title,
        _session!.draft.type,
      );
      if (mounted && polished != _session!.draft.title) {
        setState(() {
          _session = _session!.copyWith(
            draft: _session!.draft..title = polished,
          );
        });
        UiToast.show(
          context,
          title: 'Title polished',
          message: polished,
          intent: UiIntent.success,
        );
      }
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  // ── AI Write content for conversation step ────────────────────────────

  Future<void> _aiWriteContent() async {
    if (_session == null || _aiWriting) return;
    final step = _session!.currentStep;
    if (step == null || step.answerType != AiAnswerType.multilineText) return;

    final notifier = ref.read(aiEngineProvider.notifier);
    if (!notifier.canGenerate) {
      UiToast.show(
        context,
        title: 'Set up AI first',
        message: 'Import an on-device model or paste an API key in Settings › AI to use AI Write.',
        intent: UiIntent.info,
        actionLabel: 'Settings',
        onAction: () => context.push('/settings/ai'),
        duration: const Duration(seconds: 5),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _aiWriting = true);
    try {
      final content = await notifier.generateFieldContent(
        title: _session!.draft.title.isNotEmpty
            ? _session!.draft.title
            : _answerTextCtrl.text.trim(),
        type: _session!.type,
        field: step.field,
        userHint: _answerTextCtrl.text.trim().isNotEmpty
            ? _answerTextCtrl.text.trim()
            : null,
      );
      if (!mounted || content.isEmpty) return;
      _answerTextCtrl.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
      UiToast.show(
        context,
        title: 'AI Generated',
        message: 'Review and edit before submitting.',
        intent: UiIntent.success,
      );
    } catch (e) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'AI Write failed',
          message: e.toString(),
          intent: UiIntent.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _aiWriting = false);
    }
  }

  // ── Conversation navigation ───────────────────────────────────────────────

  void _submitAnswer(dynamic value) {
    if (_session == null) return;
    HapticFeedback.selectionClick();
    final next = AiConversationEngine.answer(_session!, value);
    _answerTextCtrl.clear();
    if (next.isComplete) {
      setState(() {
        _session = next;
        _mode = _AiMode.review;
      });
    } else {
      setState(() => _session = next);
    }
  }

  void _skipStep() {
    if (_session == null) return;
    final next = AiConversationEngine.skip(_session!);
    _answerTextCtrl.clear();
    if (next.isComplete) {
      setState(() {
        _session = next;
        _mode = _AiMode.review;
      });
    } else {
      setState(() => _session = next);
    }
  }

  void _goBack() {
    if (_session == null) return;
    if (_session!.completedAnswers.isEmpty) {
      // Back to compose
      setState(() {
        _session = null;
        _mode = _AiMode.compose;
      });
      return;
    }
    final prev = AiConversationEngine.back(_session!);
    _answerTextCtrl.clear();
    setState(() {
      _session = prev;
      _mode = _AiMode.conversation;
    });
  }

  void _switchType(CaptureType type) {
    if (_session == null) return;
    final newDraft = _session!.draft.copy();
    newDraft.type = type;
    final newSession = AiConversationEngine.start(type, newDraft);
    _answerTextCtrl.clear();
    setState(() {
      _session = newSession;
      _mode = _AiMode.conversation;
    });
    if (type == CaptureType.flashcard) {
      _generateFlashcards(newDraft.title);
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_session == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final result = await saveCaptureDraft(ref, _session!.draft);
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _session = null;
        _mode = _AiMode.compose;
        _composeCtrl.clear();
      });
      _recent.insert(0, result);
      _listKey.currentState?.insertItem(0,
          duration: const Duration(milliseconds: 320));
      if (_recent.length > 12) _recent.removeLast();

      if (result.kind == CaptureSaveResultKind.navigate &&
          result.navigationPath != null) {
        context.push(result.navigationPath!);
      } else {
        UiToast.show(
          context,
          title: 'Saved as ${result.type.shortLabel}',
          message: result.title,
          intent: UiIntent.success,
          icon: Icons.check_circle_outline,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      UiToast.show(
        context,
        title: 'Could not save',
        message: '$e',
        intent: UiIntent.danger,
      );
    }
  }

  void _resetToCompose() {
    setState(() {
      _session = null;
      _mode = _AiMode.compose;
    });
  }

  // ── Ask AI (Q&A mode) ─────────────────────────────────────────────────────

  Future<void> _askAi() async {
    final text = _composeCtrl.text.trim();
    if (text.isEmpty || _isAnswering) return;
    final notifier = ref.read(aiEngineProvider.notifier);
    if (!notifier.canGenerate) {
      UiToast.show(
        context,
        title: 'Set up AI first',
        message:
            'For questions, import an on-device model or paste your API key in Settings › AI.',
        intent: UiIntent.info,
        actionLabel: 'Settings',
        onAction: () => context.push('/settings/ai'),
        duration: const Duration(seconds: 5),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isAnswering = true;
      _aiAnswer = null;
      _mode = _AiMode.answer;
    });
    try {
      final answer = await notifier.answer(
        text,
        history: List<AiChatTurn>.unmodifiable(_chatHistory),
      );
      if (!mounted) return;
      setState(() {
        _aiAnswer = answer;
        _chatHistory
          ..add(AiChatTurn.user(text))
          ..add(AiChatTurn.assistant(answer));
        while (_chatHistory.length > 8) {
          _chatHistory.removeAt(0);
        }
      });
    } catch (error) {
      if (mounted) {
        UiToast.show(
          context,
          title: 'AI could not respond',
          message: '$error',
          intent: UiIntent.warning,
        );
        setState(() => _mode = _AiMode.compose);
      }
    } finally {
      if (mounted) setState(() => _isAnswering = false);
    }
  }

  Future<void> _saveAnswerAsNote() async {
    final answer = _aiAnswer;
    if (answer == null || _savingAnswer) return;
    setState(() => _savingAnswer = true);
    final source = _composeCtrl.text.trim();
    final draft = CaptureDraft(
      type: CaptureType.note,
      title: source.isEmpty
          ? 'AI answer'
          : (source.length > 70 ? '${source.substring(0, 70)}…' : source),
      details: answer,
      confidence: 1,
      sourceText: source,
    );
    try {
      final result = await saveCaptureDraft(ref, draft);
      if (!mounted) return;
      setState(() {
        _savingAnswer = false;
        _aiAnswer = null;
        _mode = _AiMode.compose;
      });
      _recent.insert(0, result);
      _listKey.currentState?.insertItem(0,
          duration: const Duration(milliseconds: 320));
      if (_recent.length > 12) _recent.removeLast();
      UiToast.show(
        context,
        title: 'Saved as note',
        message: result.title,
        intent: UiIntent.success,
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAnswer = false);
      UiToast.show(
        context,
        title: 'Could not save answer',
        message: '$e',
        intent: UiIntent.danger,
      );
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (s) {
        if (mounted && (s == 'done' || s == 'notListening')) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available || !mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        _composeCtrl.value = TextEditingValue(
          text: result.recognizedWords,
          selection:
              TextSelection.collapsed(offset: result.recognizedWords.length),
        );
        setState(() => _listening = _speech.isListening);
      },
    );
  }

  Future<void> _toggleSpeak() async {
    if (_speaking) {
      await AiVoiceService.instance.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    if (_aiAnswer == null) return;
    setState(() => _speaking = true);
    try {
      await AiVoiceService.instance.speak(_aiAnswer!);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  CaptureType _captureTypeFor(String v) => switch (v) {
        'note' => CaptureType.note,
        'journal' => CaptureType.journal,
        'event' => CaptureType.event,
        'routine' => CaptureType.routine,
        _ => CaptureType.todo,
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiEngineProvider);
    final aiDetail = ref.watch(aiEngineDetailProvider);

    return UiPage(
      header: UiHeader(
        title: 'AI Capture',
        leading: _mode == _AiMode.conversation || _mode == _AiMode.review
            ? UiIconButton(
                icon: Icons.arrow_back,
                variant: UiVariant.ghost,
                tooltip: 'Back',
                onPressed: _mode == _AiMode.review ? _resetToCompose : _goBack,
              )
            : const QuietNoteMark(size: 38),
        subtitle: _mode == _AiMode.compose
            ? 'Your intelligent capture assistant'
            : null,
        actions: [
          UiIconButton(
            icon: Icons.tune_outlined,
            tooltip: 'AI settings',
            onPressed: () => context.push('/settings/ai'),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: switch (_mode) {
          _AiMode.compose => _ComposeView(
              key: const ValueKey('compose'),
              ctrl: _composeCtrl,
              focusNode: _composeFocus,
              isProcessing: _isProcessing,
              pulseController: _pulseController,
              listening: _listening,
              livePrediction: _livePrediction,
              aiDetail: aiDetail,
              aiState: aiState,
              onCapture: _startCapture,
              onAsk: _askAi,
              onVoice: _toggleVoice,
              recent: _recent,
              listKey: _listKey,
              onTypeChip: (type) {
                HapticFeedback.lightImpact();
                _composeCtrl.clear();
                // Pre-fill with empty draft of chosen type
                final draft = CaptureDraft(
                  type: type,
                  title: '',
                  sourceText: '',
                );
                final session = AiConversationEngine.start(type, draft);
                setState(() {
                  _session = session;
                  _mode = _AiMode.conversation;
                });
                if (type == CaptureType.flashcard) {
                  _generateFlashcards('');
                }
              },
            ),
          _AiMode.conversation => _ConversationView(
              key: const ValueKey('conversation'),
              session: _session!,
              answerCtrl: _answerTextCtrl,
              enriching: _enriching,
              aiWriting: _aiWriting,
              onSubmit: _submitAnswer,
              onSkip: _skipStep,
              onBack: _goBack,
              onSwitchType: _switchType,
              onAiWrite: _aiWriteContent,
            ),
          _AiMode.review => _ReviewView(
              key: const ValueKey('review'),
              session: _session!,
              saving: _isSaving,
              enriching: _enriching,
              onSave: _save,
              onEdit: _goBack,
              onDiscard: _resetToCompose,
              onEnrichSubtasks: _enrichSubtasks,
              onEnrichMilestones: _enrichMilestones,
              onEnrichPolishTitle: _enrichPolishTitle,
              onEnrichFlashcards: () =>
                  _generateFlashcards(_session!.draft.title),
            ),
          _AiMode.answer => _AnswerView(
              key: const ValueKey('answer'),
              answer: _aiAnswer,
              answering: _isAnswering,
              speaking: _speaking,
              savingAnswer: _savingAnswer,
              aiDetail: aiDetail,
              onSaveAsNote: _saveAnswerAsNote,
              onSpeak: _toggleSpeak,
              onNewQuestion: () {
                setState(() {
                  _aiAnswer = null;
                  _mode = _AiMode.compose;
                });
              },
            ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compose view — initial state
// ---------------------------------------------------------------------------

class _ComposeView extends StatelessWidget {
  const _ComposeView({
    super.key,
    required this.ctrl,
    required this.focusNode,
    required this.isProcessing,
    required this.pulseController,
    required this.listening,
    required this.livePrediction,
    required this.aiDetail,
    required this.aiState,
    required this.onCapture,
    required this.onAsk,
    required this.onVoice,
    required this.recent,
    required this.listKey,
    required this.onTypeChip,
  });

  final TextEditingController ctrl;
  final FocusNode focusNode;
  final bool isProcessing;
  final AnimationController pulseController;
  final bool listening;
  final CaptureDraft? livePrediction;
  final AiEngineDetail aiDetail;
  final AiEngineState aiState;
  final VoidCallback onCapture;
  final VoidCallback onAsk;
  final VoidCallback onVoice;
  final List<CaptureSaveResult> recent;
  final GlobalKey<AnimatedListState> listKey;
  final ValueChanged<CaptureType> onTypeChip;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;

    // Grouped quick-start categories
    const studyTypes = [
      CaptureType.flashcard,
      CaptureType.course,
      CaptureType.note,
      CaptureType.focusSession,
    ];
    const planTypes = [
      CaptureType.todo,
      CaptureType.event,
      CaptureType.goal,
      CaptureType.habit,
    ];
    const reflectTypes = [
      CaptureType.journal,
      CaptureType.routine,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Time-aware greeting & contextual prompt ─────────────────────────
        const _TimeAwareGreeting(),
        const SizedBox(height: 12),

        // ── AI status banner ───────────────────────────────────────────────
        _ModelStatusBanner(state: aiState, detail: aiDetail),
        const SizedBox(height: 16),

        // ── Composer card ──────────────────────────────────────────────────
        UiCard(
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
                      controller: ctrl,
                      focusNode: focusNode,
                      hintText:
                          'Type anything — a task, study topic, how today went…',
                      enabled: !isProcessing,
                      maxLines: 4,
                      minLines: 2,
                    ),
                  ),
                ],
              ),
              if (listening) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const AiWaveformVisualizer(active: true, height: 18),
                      const SizedBox(width: 10),
                      Text(
                        'Listening… speak your capture',
                        style: context.uiText.caption
                            .copyWith(color: c.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    aiDetail.backend == AiBackend.api
                        ? Icons.cloud_outlined
                        : Icons.lock_outline,
                    size: 14,
                    color: c.foregroundSubtle,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      aiDetail.backend == AiBackend.api
                          ? 'Sent to your own provider with your key.'
                          : 'Processed entirely on this device.',
                      style: context.uiText.caption
                          .copyWith(color: c.foregroundSubtle),
                    ),
                  ),
                  UiButton(
                    label: isProcessing ? 'Thinking…' : 'Capture',
                    leadingIcon: isProcessing ? null : Icons.auto_awesome,
                    loading: isProcessing,
                    expandOnMobile: false,
                    onPressed: isProcessing ? null : () {
                      HapticFeedback.lightImpact();
                      onCapture();
                    },
                  ),
                  const SizedBox(width: 8),
                  UiIconButton(
                    icon: Icons.chat_bubble_outline,
                    variant: UiVariant.secondary,
                    tooltip: 'Ask AI a question',
                    onPressed: isProcessing ? null : () {
                      HapticFeedback.lightImpact();
                      onAsk();
                    },
                  ),
                  const SizedBox(width: 8),
                  UiIconButton(
                    icon: listening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    variant:
                        listening ? UiVariant.primary : UiVariant.secondary,
                    tooltip:
                        listening ? 'Stop listening' : 'Speak your capture',
                    onPressed: isProcessing ? null : () {
                      HapticFeedback.lightImpact();
                      onVoice();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Real-time live prediction pill ─────────────────────────────────
        if (livePrediction != null) ...[
          _LiveIntentPill(
            draft: livePrediction!,
            onTap: () {
              HapticFeedback.lightImpact();
              onCapture();
            },
            onSwitchType: (t) {
              HapticFeedback.lightImpact();
              onTypeChip(t);
            },
          ),
        ],
        const SizedBox(height: 20),

        // ── Quick-start chips ──────────────────────────────────────────────
        _QuickStartSection(
          label: 'Study',
          types: studyTypes,
          onTap: (t) {
            HapticFeedback.lightImpact();
            onTypeChip(t);
          },
        ),
        const SizedBox(height: 12),
        _QuickStartSection(
          label: 'Plan',
          types: planTypes,
          onTap: (t) {
            HapticFeedback.lightImpact();
            onTypeChip(t);
          },
        ),
        const SizedBox(height: 12),
        _QuickStartSection(
          label: 'Reflect',
          types: reflectTypes,
          onTap: (t) {
            HapticFeedback.lightImpact();
            onTypeChip(t);
          },
        ),
        const SizedBox(height: 24),

        // ── Recent saves ───────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.history, size: 16, color: c.foregroundMuted),
            const SizedBox(width: 6),
            Text('Recently captured', style: context.uiText.bodyStrong),
          ],
        ),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          const UiEmptyState(
            title: 'Nothing captured yet',
            message: 'Whatever you capture this session shows up here.',
            icon: Icons.auto_awesome,
          )
        else
          AnimatedList(
            key: listKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            initialItemCount: recent.length,
            itemBuilder: (context, index, animation) {
              if (index >= recent.length) return const SizedBox.shrink();
              return SizeTransition(
                sizeFactor: animation,
                child: FadeTransition(
                  opacity: animation,
                  child: _RecentCaptureTile(result: recent[index]),
                ),
              );
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-start section
// ---------------------------------------------------------------------------

class _QuickStartSection extends StatelessWidget {
  const _QuickStartSection({
    required this.label,
    required this.types,
    required this.onTap,
  });

  final String label;
  final List<CaptureType> types;
  final ValueChanged<CaptureType> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.uiText.caption.copyWith(color: c.foregroundMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types
              .map((t) => _TypeChip(type: t, onTap: () => onTap(t)))
              .toList(),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.onTap});
  final CaptureType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 15, color: c.foregroundMuted),
            const SizedBox(width: 6),
            Text(
              type.shortLabel,
              style:
                  context.uiText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Time-aware greeting widget
// ---------------------------------------------------------------------------

class _TimeAwareGreeting extends StatelessWidget {
  const _TimeAwareGreeting();

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final hour = DateTime.now().hour;
    final String greeting;
    final String prompt;
    final IconData icon;

    if (hour >= 5 && hour < 12) {
      greeting = 'Good morning';
      prompt = 'Ready to set your top priorities today?';
      icon = Icons.wb_sunny_outlined;
    } else if (hour >= 12 && hour < 17) {
      greeting = 'Good afternoon';
      prompt = 'Capture study notes, quick tasks, or a focus sprint.';
      icon = Icons.light_mode_outlined;
    } else if (hour >= 17 && hour < 22) {
      greeting = 'Good evening';
      prompt = 'Reflect on today or prep for tomorrow.';
      icon = Icons.wb_twilight_outlined;
    } else {
      greeting = 'Late night';
      prompt = 'Jot down a quick thought or wind down.';
      icon = Icons.bedtime_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: context.uiText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.primary,
                  ),
                ),
                Text(
                  prompt,
                  style: context.uiText.caption
                      .copyWith(color: c.foregroundMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Real-time live prediction pill
// ---------------------------------------------------------------------------

class _LiveIntentPill extends StatelessWidget {
  const _LiveIntentPill({
    required this.draft,
    required this.onTap,
    required this.onSwitchType,
  });

  final CaptureDraft draft;
  final VoidCallback onTap;
  final ValueChanged<CaptureType> onSwitchType;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final pct = (draft.confidence * 100).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(draft.type.icon, size: 16, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Text(
                  'Looks like a ${draft.type.label}',
                  style: context.uiText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '($pct% match)',
                  style: context.uiText.caption
                      .copyWith(color: c.foregroundMuted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Start',
                    style: context.uiText.caption.copyWith(
                      color: c.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward, size: 12, color: c.onPrimary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation view — interactive Q&A
// ---------------------------------------------------------------------------

class _ConversationView extends ConsumerStatefulWidget {
  const _ConversationView({
    super.key,
    required this.session,
    required this.answerCtrl,
    required this.enriching,
    required this.onSubmit,
    required this.onSkip,
    required this.onBack,
    required this.onSwitchType,
    this.onAiWrite,
    this.aiWriting = false,
  });

  final AiConversationSession session;
  final TextEditingController answerCtrl;
  final bool enriching;
  final bool aiWriting;
  final ValueChanged<dynamic> onSubmit;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final ValueChanged<CaptureType> onSwitchType;
  /// Called when user taps ✨ AI Write on a content step.
  final VoidCallback? onAiWrite;

  @override
  ConsumerState<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends ConsumerState<_ConversationView> {
  dynamic _radioValue;
  List<int> _multiSelectValues = [];
  DateTime? _pickedDateTime;

  @override
  void didUpdateWidget(_ConversationView old) {
    super.didUpdateWidget(old);
    if (old.session.currentStepIndex != widget.session.currentStepIndex) {
      _radioValue = widget.session.currentStep?.defaultValue;
      _multiSelectValues = [];
      _pickedDateTime = widget.session.currentStep?.defaultValue is DateTime
          ? widget.session.currentStep!.defaultValue as DateTime
          : null;
      widget.answerCtrl.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    _radioValue = widget.session.currentStep?.defaultValue;
  }

  void _submitCurrent() {
    final step = widget.session.currentStep;
    if (step == null) return;

    switch (step.answerType) {
      case AiAnswerType.radioChips:
        if (_radioValue != null) widget.onSubmit(_radioValue);
      case AiAnswerType.text:
      case AiAnswerType.multilineText:
        final text = widget.answerCtrl.text.trim();
        if (text.isNotEmpty) {
          widget.onSubmit(text);
        } else if (step.optional) {
          widget.onSkip();
        }
      case AiAnswerType.number:
        final val = double.tryParse(widget.answerCtrl.text.trim());
        if (val != null) {
          widget.onSubmit(val);
        } else if (step.optional) {
          widget.onSkip();
        }
      case AiAnswerType.dateTime:
      case AiAnswerType.dateOnly:
        if (_pickedDateTime != null) {
          widget.onSubmit(_pickedDateTime);
        } else if (step.optional) {
          widget.onSkip();
        }
      case AiAnswerType.yesNo:
        if (_radioValue != null) widget.onSubmit(_radioValue);
      case AiAnswerType.multiSelect:
        widget.onSubmit(_multiSelectValues);
      case AiAnswerType.preview:
        // Preview step: always advance
        widget.onSubmit(widget.session.draft.flashcardPairs);
    }
  }

  Future<void> _pickDate(bool withTime) async {
    final initial = _pickedDateTime ??
        widget.session.currentStep?.defaultValue as DateTime? ??
        DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;

    if (!withTime) {
      setState(() => _pickedDateTime = date);
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    setState(() {
      _pickedDateTime = DateTime(
        date.year, date.month, date.day,
        time?.hour ?? initial.hour,
        time?.minute ?? initial.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final step = session.currentStep;
    final courses =
        ref.watch(coursesStreamProvider).valueOrNull ?? const <Course>[];

    // Inject course options for the steps that need them
    AiConversationStep? effectiveStep = step;
    if (step != null &&
        (step.field == 'courseId' || step.field == 'focusLinkedCourseId') &&
        courses.isNotEmpty) {
      effectiveStep = AiConversationStep(
        field: step.field,
        question: step.question,
        subtitle: step.subtitle,
        answerType: step.answerType,
        optional: step.optional,
        options: [
          const AiRadioOption(value: '', label: 'No course'),
          for (final c in courses) AiRadioOption(value: c.id, label: c.name),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Type + step progress header ────────────────────────────────────
        _ConversationHeader(
          session: session,
          onSwitchType: widget.onSwitchType,
        ),
        const SizedBox(height: 16),

        // ── Chat bubbles ───────────────────────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Previous Q&A bubbles
            for (final answered in session.completedAnswers) ...[
              _AiBubble(text: answered.step.question),
              const SizedBox(height: 6),
              _UserBubble(text: answered.displayValue),
              const SizedBox(height: 12),
            ],
            // Current AI question
            if (effectiveStep != null) ...[
              _AiBubble(
                text: effectiveStep.question,
                subtitle: effectiveStep.subtitle,
                loading: widget.enriching &&
                    effectiveStep.answerType == AiAnswerType.preview,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),

        // ── Answer input ───────────────────────────────────────────────────
        if (effectiveStep != null) ...[
          _AnswerWidget(
            step: effectiveStep,
            textCtrl: widget.answerCtrl,
            radioValue: _radioValue,
            multiSelectValues: _multiSelectValues,
            pickedDateTime: _pickedDateTime,
            draft: session.draft,
            enriching: widget.enriching,
            onRadioChanged: (v) => setState(() => _radioValue = v),
            onMultiSelectChanged: (v) => setState(() => _multiSelectValues = v),
            onPickDate: (withTime) => _pickDate(withTime),
            onSubmit: _submitCurrent,
          ),
          const SizedBox(height: 16),

          // ── Action row ─────────────────────────────────────────────────
          Row(
            children: [
              if (session.completedAnswers.isNotEmpty)
                UiButton(
                  label: '← Back',
                  variant: UiVariant.ghost,
                  size: UiSize.sm,
                  onPressed: widget.onBack,
                ),
              const Spacer(),
              // AI Write button — only for text content steps
              if (effectiveStep.answerType == AiAnswerType.multilineText &&
                  widget.onAiWrite != null &&
                  !widget.aiWriting)
                UiButton(
                  label: 'AI Write',
                  leadingIcon: Icons.auto_awesome_rounded,
                  variant: UiVariant.secondary,
                  size: UiSize.sm,
                  onPressed: widget.onAiWrite,
                ),
              if (widget.aiWriting)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Writing…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              if (effectiveStep.optional)
                UiButton(
                  label: 'Skip',
                  variant: UiVariant.ghost,
                  size: UiSize.sm,
                  onPressed: widget.onSkip,
                ),
              const SizedBox(width: 8),
              if (effectiveStep.answerType != AiAnswerType.radioChips &&
                  effectiveStep.answerType != AiAnswerType.yesNo)
                UiButton(
                  label: 'Next →',
                  size: UiSize.sm,
                  onPressed: _submitCurrent,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation header — type badge + progress
// ---------------------------------------------------------------------------

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.session,
    required this.onSwitchType,
  });
  final AiConversationSession session;
  final ValueChanged<CaptureType> onSwitchType;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final pct = (session.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(session.type.icon, size: 15, color: c.primary),
                  const SizedBox(width: 6),
                  Text(
                    session.type.label,
                    style: context.uiText.caption.copyWith(
                      color: c.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Step ${session.answeredCount + 1} of ${session.totalSteps}',
                style:
                    context.uiText.caption.copyWith(color: c.foregroundMuted),
              ),
            ),
            Text(
              '$pct%',
              style: context.uiText.caption.copyWith(
                color: c.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: session.progress,
            backgroundColor: c.surfaceMuted,
            color: c.primary,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 12),
        // Type switch chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Not right?',
              style:
                  context.uiText.caption.copyWith(color: c.foregroundMuted),
            ),
            for (final t in CaptureType.values)
              if (t != session.type)
                GestureDetector(
                  onTap: () => onSwitchType(t),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 13, color: c.foregroundMuted),
                        const SizedBox(width: 4),
                        Text(
                          t.shortLabel,
                          style: context.uiText.caption
                              .copyWith(color: c.foregroundMuted),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chat bubbles
// ---------------------------------------------------------------------------

class _AiBubble extends StatelessWidget {
  const _AiBubble({required this.text, this.subtitle, this.loading = false});
  final String text;
  final String? subtitle;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.primary.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.auto_awesome, size: 14, color: c.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: loading
                ? Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Generating…',
                          style: context.uiText.body
                              .copyWith(color: c.foregroundMuted)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TypewriterText(text: text, style: context.uiText.body),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: context.uiText.caption
                              .copyWith(color: c.foregroundMuted),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
            child: Text(
              text,
              style:
                  context.uiText.body.copyWith(color: c.onPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Answer widget — renders the correct input for each step's answerType
// ---------------------------------------------------------------------------

class _AnswerWidget extends StatelessWidget {
  const _AnswerWidget({
    required this.step,
    required this.textCtrl,
    required this.radioValue,
    required this.multiSelectValues,
    required this.pickedDateTime,
    required this.draft,
    required this.enriching,
    required this.onRadioChanged,
    required this.onMultiSelectChanged,
    required this.onPickDate,
    required this.onSubmit,
  });

  final AiConversationStep step;
  final TextEditingController textCtrl;
  final dynamic radioValue;
  final List<int> multiSelectValues;
  final DateTime? pickedDateTime;
  final CaptureDraft draft;
  final bool enriching;
  final ValueChanged<dynamic> onRadioChanged;
  final ValueChanged<List<int>> onMultiSelectChanged;
  final ValueChanged<bool> onPickDate;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;

    switch (step.answerType) {
      case AiAnswerType.radioChips:
        final options = step.options ?? [];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              GestureDetector(
                onTap: () {
                  onRadioChanged(option.value);
                  onSubmit();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: radioValue == option.value
                        ? c.primary
                        : c.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: radioValue == option.value
                          ? c.primary
                          : c.border,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (option.icon != null) ...[
                        Icon(
                          option.icon,
                          size: 15,
                          color: radioValue == option.value
                              ? c.onPrimary
                              : c.foregroundMuted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        option.label,
                        style: context.uiText.body.copyWith(
                          color: radioValue == option.value
                              ? c.onPrimary
                              : c.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );

      case AiAnswerType.text:
        return UiInput(
          controller: textCtrl,
          hintText: step.hintText ?? 'Your answer…',
          keyboardType: step.keyboardType ?? TextInputType.text,
          autofocus: true,
        );

      case AiAnswerType.multilineText:
        return UiInput.multiline(
          controller: textCtrl,
          hintText: step.hintText ?? 'Write here…',
          maxLines: 5,
          minLines: 3,
          autofocus: true,
        );

      case AiAnswerType.number:
        return UiInput(
          controller: textCtrl,
          hintText: step.hintText ?? '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        );

      case AiAnswerType.dateTime:
        return GestureDetector(
          onTap: () => onPickDate(true),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 18, color: c.foregroundMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickedDateTime != null
                        ? DateFormat('EEE, d MMM yyyy — HH:mm')
                            .format(pickedDateTime!)
                        : (step.hintText ?? 'Tap to pick date & time'),
                    style: context.uiText.body.copyWith(
                      color: pickedDateTime != null
                          ? c.foreground
                          : c.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case AiAnswerType.dateOnly:
        return GestureDetector(
          onTap: () => onPickDate(false),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 18, color: c.foregroundMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickedDateTime != null
                        ? DateFormat('EEE, d MMM yyyy')
                            .format(pickedDateTime!)
                        : (step.hintText ?? 'Tap to pick a date'),
                    style: context.uiText.body.copyWith(
                      color: pickedDateTime != null
                          ? c.foreground
                          : c.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case AiAnswerType.yesNo:
        return Row(
          children: [
            Expanded(
              child: _YesNoChip(
                label: 'Yes',
                selected: radioValue == true,
                onTap: () {
                  onRadioChanged(true);
                  onSubmit();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _YesNoChip(
                label: 'No',
                selected: radioValue == false,
                onTap: () {
                  onRadioChanged(false);
                  onSubmit();
                },
              ),
            ),
          ],
        );

      case AiAnswerType.multiSelect:
        const weekdays = [
          'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < weekdays.length; i++)
              GestureDetector(
                onTap: () {
                  final next = List<int>.from(multiSelectValues);
                  if (next.contains(i)) {
                    next.remove(i);
                  } else {
                    next.add(i);
                  }
                  onMultiSelectChanged(next);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: multiSelectValues.contains(i)
                        ? c.primary
                        : c.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: multiSelectValues.contains(i)
                          ? c.primary
                          : c.border,
                    ),
                  ),
                  child: Text(
                    weekdays[i],
                    style: context.uiText.body.copyWith(
                      color: multiSelectValues.contains(i)
                          ? c.onPrimary
                          : c.foreground,
                    ),
                  ),
                ),
              ),
          ],
        );

      case AiAnswerType.preview:
        // Flashcard pairs preview
        final pairs = draft.flashcardPairs;
        if (enriching) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (pairs.isEmpty) {
          return const UiCallout(
            intent: UiIntent.info,
            icon: Icons.info_outline,
            title: 'No cards generated yet',
            message:
                'Set up an AI backend in Settings › AI to auto-generate cards, or add them manually after saving the deck.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < pairs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FlashcardPreviewTile(
                  pair: pairs[i],
                  index: i,
                ),
              ),
          ],
        );
    }
  }
}

class _YesNoChip extends StatelessWidget {
  const _YesNoChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? c.primary : c.border, width: 1.5),
        ),
        child: Text(
          label,
          style: context.uiText.body.copyWith(
            color: selected ? c.onPrimary : c.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FlashcardPreviewTile extends StatelessWidget {
  const _FlashcardPreviewTile({required this.pair, required this.index});
  final AiFlashcardPair pair;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return UiCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Card ${index + 1}',
                style: context.uiText.caption
                    .copyWith(color: c.foregroundMuted),
              ),
              const Spacer(),
              Icon(Icons.style_outlined, size: 14, color: c.foregroundMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text('Q: ${pair.front}', style: context.uiText.bodyStrong),
          const SizedBox(height: 4),
          Text('A: ${pair.back}',
              style:
                  context.uiText.body.copyWith(color: c.foregroundMuted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review view — final confirmation before save
// ---------------------------------------------------------------------------

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    super.key,
    required this.session,
    required this.saving,
    required this.enriching,
    required this.onSave,
    required this.onEdit,
    required this.onDiscard,
    required this.onEnrichSubtasks,
    required this.onEnrichMilestones,
    required this.onEnrichPolishTitle,
    required this.onEnrichFlashcards,
  });

  final AiConversationSession session;
  final bool saving;
  final bool enriching;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback onDiscard;
  final VoidCallback onEnrichSubtasks;
  final VoidCallback onEnrichMilestones;
  final VoidCallback onEnrichPolishTitle;
  final VoidCallback onEnrichFlashcards;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final draft = session.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(draft.type.icon, size: 22, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ready to save',
                      style: context.uiText.caption
                          .copyWith(color: c.foregroundMuted)),
                  Text(
                    draft.title.isEmpty ? 'Untitled' : draft.title,
                    style: context.uiText.heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            UiBadge(
              label: draft.type.label,
              intent: UiIntent.primary,
              size: UiSize.sm,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Field summary ─────────────────────────────────────────────────
        UiCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final answer in session.completedAnswers)
                if (answer.value != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            _fieldLabel(answer.step.field),
                            style: context.uiText.caption
                                .copyWith(color: c.foregroundMuted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            answer.displayValue,
                            style: context.uiText.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                ],
              if (draft.subtasks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Subtasks:', style: context.uiText.caption.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final st in draft.subtasks)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 3),
                    child: Row(
                      children: [
                        Icon(Icons.check_box_outline_blank, size: 13, color: c.foregroundMuted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(st, style: context.uiText.body)),
                      ],
                    ),
                  ),
              ],
              if (draft.milestones.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Milestones:', style: context.uiText.caption.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final ms in draft.milestones)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 3),
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 13, color: c.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(ms, style: context.uiText.body)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),

        // Flashcard pairs if present
        if (draft.flashcardPairs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${draft.flashcardPairs.length} flashcard${draft.flashcardPairs.length == 1 ? '' : 's'} ready',
            style:
                context.uiText.caption.copyWith(color: c.foregroundMuted),
          ),
        ],
        const SizedBox(height: 16),

        // ── Magic AI Enhancers ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: c.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Magic AI Enhancers',
                    style: context.uiText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.primary,
                    ),
                  ),
                  if (enriching) ...[
                    const Spacer(),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.primary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (draft.type == CaptureType.todo)
                    UiButton(
                      label: 'Auto-generate subtasks',
                      leadingIcon: Icons.checklist_rtl_outlined,
                      variant: UiVariant.secondary,
                      size: UiSize.sm,
                      loading: enriching,
                      onPressed: enriching ? null : onEnrichSubtasks,
                    ),
                  if (draft.type == CaptureType.goal)
                    UiButton(
                      label: 'Suggest 3 milestones',
                      leadingIcon: Icons.flag_outlined,
                      variant: UiVariant.secondary,
                      size: UiSize.sm,
                      loading: enriching,
                      onPressed: enriching ? null : onEnrichMilestones,
                    ),
                  if (draft.type == CaptureType.flashcard)
                    UiButton(
                      label: 'Regenerate cards',
                      leadingIcon: Icons.refresh_outlined,
                      variant: UiVariant.secondary,
                      size: UiSize.sm,
                      loading: enriching,
                      onPressed: enriching ? null : onEnrichFlashcards,
                    ),
                  UiButton(
                    label: 'Polish title',
                    leadingIcon: Icons.auto_fix_high_outlined,
                    variant: UiVariant.secondary,
                    size: UiSize.sm,
                    loading: enriching,
                    onPressed: enriching ? null : onEnrichPolishTitle,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Actions ───────────────────────────────────────────────────────
        Row(
          children: [
            UiButton(
              label: 'Discard',
              variant: UiVariant.ghost,
              leadingIcon: Icons.delete_outline,
              onPressed: onDiscard,
            ),
            const SizedBox(width: 8),
            UiButton(
              label: 'Edit',
              variant: UiVariant.secondary,
              leadingIcon: Icons.edit_outlined,
              onPressed: onEdit,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: UiButton(
                label: draft.type == CaptureType.focusSession
                    ? '▶ Start Session'
                    : 'Save',
                leadingIcon: draft.type == CaptureType.focusSession
                    ? null
                    : Icons.check,
                loading: saving,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onSave();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fieldLabel(String field) {
    const labels = <String, String>{
      'title': 'Title',
      'details': 'Details',
      'priority': 'Priority',
      'category': 'Category',
      'mood': 'Mood',
      'dueDate': 'Due date',
      'startTime': 'Start',
      'endTime': 'End',
      'courseId': 'Course',
      'tags': 'Tags',
      'frequencyType': 'Frequency',
      'habitNotes': 'Notes',
      'habitGoalTarget': 'Target',
      'habitGoalUnit': 'Unit',
      'goalTarget': 'Target',
      'goalUnit': 'Unit',
      'flashcardTitle': 'Deck title',
      'flashcardSubjects': 'Subjects',
      'courseName': 'Name',
      'courseCode': 'Code',
      'courseInstructor': 'Instructor',
      'courseRoom': 'Room',
      'courseTerm': 'Term',
      'courseTargetGrade': 'Target grade',
      'focusPresetId': 'Preset',
      'focusLinkedCourseId': 'Course',
      'subtasks': 'Subtasks',
    };
    return labels[field] ?? field;
  }
}

// ---------------------------------------------------------------------------
// Answer view — for the "Ask AI" path
// ---------------------------------------------------------------------------

class _AnswerView extends StatelessWidget {
  const _AnswerView({
    super.key,
    required this.answer,
    required this.answering,
    required this.speaking,
    required this.savingAnswer,
    required this.aiDetail,
    required this.onSaveAsNote,
    required this.onSpeak,
    required this.onNewQuestion,
  });

  final String? answer;
  final bool answering;
  final bool speaking;
  final bool savingAnswer;
  final AiEngineDetail aiDetail;
  final VoidCallback onSaveAsNote;
  final VoidCallback onSpeak;
  final VoidCallback onNewQuestion;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;

    if (answering || answer == null) {
      return UiCard(
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
            ),
            const SizedBox(width: 10),
            Text(
              aiDetail.backend == AiBackend.api
                  ? 'Thinking with your API model…'
                  : 'Thinking on this device…',
              style: context.uiText.body,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiCard(
          accentColor: c.primary,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 17, color: c.primary),
                  const SizedBox(width: 8),
                  Text('AI Response', style: context.uiText.bodyStrong),
                  const SizedBox(width: 8),
                  UiBadge(
                    label: aiDetail.backend == AiBackend.api ? 'API' : 'On-device',
                    size: UiSize.sm,
                    intent: UiIntent.neutral,
                  ),
                  const Spacer(),
                  UiIconButton(
                    icon: speaking
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    tooltip: speaking ? 'Stop' : 'Read aloud',
                    onPressed: onSpeak,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(answer!, style: context.uiText.body),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: UiButton(
                      label: 'Save as note',
                      variant: UiVariant.secondary,
                      size: UiSize.sm,
                      leadingIcon: Icons.notes_outlined,
                      loading: savingAnswer,
                      onPressed: onSaveAsNote,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: UiButton(
                      label: 'New question',
                      variant: UiVariant.ghost,
                      size: UiSize.sm,
                      leadingIcon: Icons.refresh,
                      onPressed: onNewQuestion,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({required this.state, required this.detail});
  final AiEngineState state;
  final AiEngineDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.isBusy) {
      final progress = detail.progress;
      return UiCallout(
        intent: UiIntent.info,
        icon: Icons.downloading_outlined,
        title: detail.busyLabel!,
        message: progress == null
            ? 'Capture still works while this finishes.'
            : '${(progress * 100).round()}% — keep the app open.',
      );
    }

    if (detail.localReady || detail.apiReady) {
      final onDevice = detail.backend == AiBackend.local;
      return UiCallout(
        intent: UiIntent.success,
        icon: onDevice ? Icons.memory : Icons.cloud_done_outlined,
        title:
            onDevice ? 'On-device model active' : 'Your API model is active',
        message: onDevice
            ? 'Everything stays on this device.'
            : 'Requests go straight to your provider with your key.',
        action: UiButton(
          label: 'Change',
          variant: UiVariant.soft,
          size: UiSize.sm,
          expandOnMobile: false,
          onPressed: () => context.push('/settings/ai'),
        ),
      );
    }

    return UiCallout(
      intent:
          state == AiEngineState.failed ? UiIntent.warning : UiIntent.info,
      icon: state == AiEngineState.failed
          ? Icons.warning_amber_rounded
          : Icons.bolt_outlined,
      title: state == AiEngineState.failed
          ? 'AI could not start'
          : 'Smart capture active',
      message: detail.error ??
          'Capture works now. For even smarter AI, add an on-device model or your API key.',
      action: UiButton(
        label: 'Set up AI',
        variant: UiVariant.soft,
        size: UiSize.sm,
        expandOnMobile: false,
        onPressed: () => context.push('/settings/ai'),
      ),
    );
  }
}

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
