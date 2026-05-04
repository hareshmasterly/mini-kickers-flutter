import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/services/match_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/online/widget/online_action_button.dart';

/// Joiner-side room screen.
///
/// Lifecycle:
///   1. Big 4-cell input strip — tap any cell to focus the underlying
///      hidden text field. The user types the code their friend
///      shared (auto-uppercases, auto-strips invalid chars).
///   2. JOIN! button enables when 4 chars are entered. Calls
///      [MatchService.joinRoom] which validates the code, creates the
///      `matches/{id}` doc, and stamps the room.
///   3. On success → pop with the new match id.
///   4. On failure → surface [RoomJoinError.reason] inline (the error
///      copy is already kid-friendly), let them try again.
///
/// Why a hidden TextField + 4 visual cells (instead of a single
/// styled field): on Android, customising a TextField's per-character
/// rendering is fragile — cursor placement, autofill, and accessibility
/// all break. Decoupling input from display gives us a perfect typed
/// look while preserving the OS keyboard behaviour parents expect.
class RoomJoinScreen extends StatefulWidget {
  const RoomJoinScreen({super.key});

  @override
  State<RoomJoinScreen> createState() => _RoomJoinScreenState();
}

class _RoomJoinScreenState extends State<RoomJoinScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  String? _inlineError;
  bool _busy = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus = FocusNode();
    // Auto-focus on entry so the keyboard pops up immediately. Kids
    // shouldn't have to tap an extra time before they can type.
    WidgetsBinding.instance.addPostFrameCallback((final _) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged(final String value) {
    // Same alphabet as MatchService._roomCodeAlphabet — keep it in
    // sync. We DON'T import that constant directly because making it
    // public would tempt callers to construct codes by hand. Instead
    // we mirror it here as a tight allowlist.
    const String allowed = 'ACDEFGHJKMNPQRTUVWXYZ23456789';
    final String cleaned = value
        .toUpperCase()
        .split('')
        .where((final String c) => allowed.contains(c))
        .take(4)
        .join();
    if (cleaned != value) {
      _controller.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    if (_inlineError != null) {
      setState(() => _inlineError = null);
    } else {
      setState(() {});
    }
  }

  bool get _canSubmit => _controller.text.length == 4 && !_busy;

  Future<void> _onJoin() async {
    if (!_canSubmit) return;
    AudioHelper.select();
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final String matchId =
          await MatchService.instance.joinRoom(_controller.text);
      if (_disposed || !mounted) return;
      Analytics.logOnlineRoomJoined(success: true);
      Analytics.logOnlineMatchPaired(via: 'code');
      Navigator.of(context).pop(matchId);
    } on RoomJoinError catch (err) {
      if (_disposed) return;
      Analytics.logOnlineRoomJoined(success: false);
      setState(() {
        _busy = false;
        _inlineError = err.reason;
      });
    } catch (e) {
      if (_disposed) return;
      Analytics.logOnlineRoomJoined(success: false);
      setState(() {
        _busy = false;
        _inlineError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _onCancel() {
    if (_disposed) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        'JOIN A ROOM',
                        textAlign: TextAlign.center,
                        style: AppFonts.bebasNeue(
                          fontSize: 30,
                          letterSpacing: 5,
                          color: Colors.white,
                          shadows: <Shadow>[
                            Shadow(
                              color:
                                  AppColors.brandRed.withValues(alpha: 0.55),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Type the 4-letter code your friend shared.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _CodeInputRow(
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: _onTextChanged,
                        hasError: _inlineError != null,
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _inlineError == null
                            ? const SizedBox(height: 18)
                            : Padding(
                                key: const ValueKey<String>('err'),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  _inlineError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.brandRed,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      OnlineActionButton(
                        label: _busy ? 'JOINING…' : 'JOIN MATCH',
                        icon: Icons.sports_soccer_rounded,
                        busy: _busy,
                        onTap: _canSubmit ? _onJoin : null,
                      ),
                      const SizedBox(height: 12),
                      OnlineActionButton(
                        label: 'CANCEL',
                        icon: Icons.close_rounded,
                        primary: false,
                        onTap: _onCancel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 big visual cells + a hidden text field driving them. Tapping any
/// cell focuses the field, so the OS keyboard rises immediately. The
/// field's text is rendered char-by-char into the cells.
class _CodeInputRow extends StatelessWidget {
  const _CodeInputRow({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hasError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool hasError;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      // Catch taps anywhere in the row to refocus — even if the user
      // taps between cells, the keyboard comes back.
      behavior: HitTestBehavior.opaque,
      onTap: () => focusNode.requestFocus(),
      child: Stack(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(4, (final int i) {
              final String char = i < controller.text.length
                  ? controller.text[i]
                  : '';
              final bool isCurrent = i == controller.text.length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _CodeCell(
                  char: char,
                  isCurrent: isCurrent,
                  hasError: hasError,
                ),
              );
            }),
          ),
          // Invisible TextField stretched across the row to pick up
          // both keyboard input and tap-to-focus. We use opacity 0
          // (not Visibility.invisible) so it remains hit-testable
          // and doesn't get pruned by the build phase.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                maxLength: 4,
                showCursor: false,
                style: const TextStyle(color: Colors.transparent),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[a-zA-Z0-9]'),
                  ),
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({
    required this.char,
    required this.isCurrent,
    required this.hasError,
  });

  final String char;
  final bool isCurrent;
  final bool hasError;

  @override
  Widget build(final BuildContext context) {
    final Color border = hasError
        ? AppColors.brandRed
        : (isCurrent
            ? AppColors.goldBright
            : Colors.white.withValues(alpha: 0.25));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: isCurrent ? 2.4 : 1.6),
        boxShadow: isCurrent
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.goldBright.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          char,
          style: AppFonts.bebasNeue(
            fontSize: 38,
            letterSpacing: 1,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
