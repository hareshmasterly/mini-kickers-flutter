import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mini_kickers/data/models/remote_avatar.dart';
import 'package:mini_kickers/data/services/avatar_service.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/utils/handle_generator.dart';
import 'package:mini_kickers/utils/profanity_filter.dart';

/// First-launch welcome dialog. Shown automatically by [HomeScreen]
/// when [UserService.isFirstLaunch] is true. Non-dismissible (no
/// barrier-tap, no Android back) — the user MUST commit to a handle
/// to proceed, otherwise we'd have a "phantom" install with no
/// profile sitting in Firebase Auth.
///
/// UX:
///   • Big avatar emoji
///   • "YOU'LL PLAY AS" → animated handle text
///   • [ THAT'S ME! ]  primary CTA
///   • [ 🔄 PICK ANOTHER ]  re-roll
///
/// On THAT'S ME → calls [UserService.confirmProfile], persists, pops.
/// On PICK ANOTHER → calls [UserService.reroll], the next pending
/// handle slides in.
Future<void> showWelcomeCard(final BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (final BuildContext ctx) => const _WelcomeCard(),
  );
}

class _WelcomeCard extends StatefulWidget {
  const _WelcomeCard();

  @override
  State<_WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends State<_WelcomeCard>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _avatarBounce;
  late final TextEditingController _nameController;
  Timer? _nameDebounce;
  bool _saving = false;
  bool _nameProfane = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _avatarBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _entry.dispose();
    _avatarBounce.dispose();
    _nameDebounce?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  /// Debounced name handler — regenerates the pending handle from
  /// the typed name 250 ms after the user stops typing. Empty / all-
  /// non-letter input falls back to the original random handle so
  /// the user is never left with a blank pending state.
  void _onNameChanged(final String raw) {
    _nameDebounce?.cancel();
    final String trimmed = raw.trim();

    // Profanity check is instant — no debounce — so the warning
    // appears the moment the user types a banned word.
    final bool profane =
        trimmed.isNotEmpty && ProfanityFilter.isBlocked(trimmed);
    if (profane != _nameProfane) {
      setState(() => _nameProfane = profane);
    }
    if (profane) return;

    _nameDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (trimmed.isEmpty) {
        // Restore a random handle (fully decoupled — adjective + role,
        // not animal-coupled).
        UserService.instance.reroll();
      } else {
        UserService.instance.setPendingFromName(trimmed);
      }
    });
  }

  Future<void> _onConfirm() async {
    if (_saving) return;
    AudioHelper.select();
    setState(() => _saving = true);
    final bool ok = await UserService.instance.confirmProfile();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      // Extreme edge case — 5 collisions in a row. Just re-roll and
      // let them try again (they'll get a fresh handle).
      setState(() => _saving = false);
      UserService.instance.reroll();
    }
  }

  void _onReroll() {
    if (_saving) return;
    AudioHelper.select();
    // If the user has typed a name, just refresh the number suffix —
    // they keep their name + avatar but get a different "Aarav847" →
    // "Aarav231". If the field is empty, a full random reroll fires.
    final String trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && !_nameProfane) {
      UserService.instance.rerollNumber();
    } else {
      UserService.instance.reroll();
    }
  }

  @override
  Widget build(final BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final bool isTablet = screen.shortestSide >= 600;
    // Compact = small landscape phones (h < 460). Without this third
    // tier the same dimensions used on a 6.7" phone get applied to a
    // 5.4" landscape phone and the card overflows by ~24 px.
    final bool compact = !isTablet && screen.height < 460;
    final double maxWidth = isTablet ? 520 : (compact ? 360 : 380);
    final EdgeInsets cardPad = isTablet
        ? const EdgeInsets.fromLTRB(36, 32, 36, 26)
        : compact
            ? const EdgeInsets.fromLTRB(22, 16, 22, 14)
            : const EdgeInsets.fromLTRB(26, 24, 26, 20);
    final double avatarSize = isTablet ? 96 : (compact ? 56 : 72);
    final double headlineFont = isTablet ? 16 : (compact ? 11 : 13);
    final double handleFont = isTablet ? 38 : (compact ? 22 : 28);
    final double subtitleFont = isTablet ? 14 : (compact ? 10 : 12);
    final double btnVPad = isTablet ? 16 : (compact ? 10 : 13);
    final double primaryBtnFont = isTablet ? 17 : (compact ? 13 : 14);
    final double secondaryFont = isTablet ? 13 : (compact ? 10 : 11);
    // Inter-element gaps. Trim aggressively on compact so the card
    // fits on iPhone SE landscape (h=375).
    final double gapAfterAvatar = compact ? 8 : 16;
    final double gapAfterHeadline = compact ? 4 : 6;
    final double gapAfterHandle = compact ? 8 : 12;
    final double gapAfterPicker = compact ? 4 : 8;
    final double gapBeforeButton = compact ? 12 : 18;
    final double gapBeforeReroll = compact ? 2 : 6;

    return PopScope<dynamic>(
      // Force user to commit — no back-button escape. Welcome card is
      // a one-time mandatory step.
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _entry,
          builder: (final BuildContext context, final Widget? child) {
            final double t = Curves.easeOutCubic.transform(_entry.value);
            final double scale = Curves.elasticOut.transform(
              _entry.value.clamp(0.0, 1.0),
            );
            return Center(
              child: Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.7 + scale * 0.3,
                  child: child,
                ),
              ),
            );
          },
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: cardPad,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color(0xFF101F10),
                            Color(0xFF0A150A),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.brandYellow.withValues(alpha: 0.55),
                          width: 2,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: AppColors.brandYellow.withValues(
                              alpha: 0.42,
                            ),
                            blurRadius: 50,
                            spreadRadius: 2,
                          ),
                          const BoxShadow(
                            color: Colors.black87,
                            blurRadius: 30,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      // ListenableBuilder makes the inner Column rebuild
                      // whenever UserService notifies (handle re-rolled,
                      // avatar tapped) so the big avatar + handle text +
                      // selected picker tile all stay in sync.
                      //
                      // SingleChildScrollView wraps the Column so any
                      // remaining overflow on extreme aspect ratios
                      // (very short landscape phones) scrolls instead
                      // of throwing a RenderFlex error. The Column
                      // still uses mainAxisSize.min so the card sizes
                      // to its content when it fits.
                      child: ListenableBuilder(
                        listenable: UserService.instance,
                        builder:
                            (final BuildContext context, final Widget? _) {
                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                _buildAvatar(avatarSize),
                                SizedBox(height: gapAfterAvatar),
                                _buildNameInput(
                                  compact: compact,
                                  isTablet: isTablet,
                                ),
                                SizedBox(height: gapAfterHeadline),
                                Text(
                                  "👋 YOU'LL PLAY AS",
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.65),
                                    fontSize: headlineFont,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(height: gapAfterHeadline),
                                _buildHandleText(handleFont),
                                SizedBox(height: gapAfterHandle),
                                _buildAvatarPicker(isTablet: isTablet),
                                SizedBox(height: gapAfterPicker),
                                Text(
                                  'You can change this later in Settings.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.55),
                                    fontSize: subtitleFont,
                                  ),
                                ),
                                SizedBox(height: gapBeforeButton),
                                _buildPrimaryButton(
                                  primaryBtnFont,
                                  btnVPad,
                                ),
                                SizedBox(height: gapBeforeReroll),
                                TextButton.icon(
                                  onPressed: _saving ? null : _onReroll,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Colors.white.withValues(alpha: 0.7),
                                  ),
                                  label: Text(
                                    'PICK ANOTHER NAME',
                                    style: TextStyle(
                                      fontSize: secondaryFont,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Gently bouncing avatar circle. Subtle motion makes the welcome
  /// card feel alive without being distracting.
  Widget _buildAvatar(final double size) {
    final GeneratedHandle? pending = UserService.instance.pendingHandle;
    final String emoji =
        pending != null ? HandleGenerator.emojiFor(pending.avatarId) : '⚽';
    return AnimatedBuilder(
      animation: _avatarBounce,
      builder: (final BuildContext context, final Widget? _) {
        final double bounce = sin(_avatarBounce.value * pi);
        return Transform.translate(
          offset: Offset(0, -bounce * 6),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  AppColors.brandYellow.withValues(alpha: 0.35),
                  AppColors.brandYellow.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: AppColors.brandYellow.withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.brandYellow.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                emoji,
                style: TextStyle(fontSize: size * 0.55),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Optional first-name input. Typing here drives the live handle
  /// preview (debounced) — empty input falls back to a random
  /// adjective+role handle. Filtered to letters only so the handle
  /// generator never has to defend against weird input.
  Widget _buildNameInput({
    required final bool compact,
    required final bool isTablet,
  }) {
    final double labelFont = compact ? 10 : (isTablet ? 13 : 11);
    final double fieldFont = compact ? 14 : (isTablet ? 17 : 15);
    final double helperFont = compact ? 9 : (isTablet ? 11 : 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'TYPE YOUR NAME (OPTIONAL)',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: labelFont,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          maxLength: 12,
          inputFormatters: <TextInputFormatter>[
            // Letters only — no spaces, no digits, no emojis. Keeps
            // the generated handle clean ("Aarav847" not "AaravX!42").
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
            LengthLimitingTextInputFormatter(12),
          ],
          onChanged: _onNameChanged,
          onTapOutside: (final _) => FocusScope.of(context).unfocus(),
          style: TextStyle(
            color: Colors.white,
            fontSize: fieldFont,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
          cursorColor: AppColors.brandYellow,
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            hintText: 'e.g. Aarav',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _nameProfane
                    ? AppColors.brandRed.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.18),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: _nameProfane
                    ? AppColors.brandRed
                    : AppColors.brandYellow.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
          ),
        ),
        if (_nameProfane) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Try a different name',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.brandRed.withValues(alpha: 0.85),
              fontSize: helperFont,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  /// Animated handle text — slides in fresh on each re-roll so the
  /// user can see the change.
  Widget _buildHandleText(final double fontSize) {
    final GeneratedHandle? pending = UserService.instance.pendingHandle;
    final String displayName = pending?.displayName ?? '';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (final Widget child, final Animation<double> a) {
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        );
      },
      child: ShaderMask(
        key: ValueKey<String>(displayName),
        shaderCallback: (final Rect bounds) => const LinearGradient(
          colors: <Color>[
            AppColors.goldDeep,
            AppColors.goldShine,
            AppColors.goldDeep,
          ],
        ).createShader(bounds),
        child: Text(
          displayName.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppFonts.bebasNeue(
            fontSize: fontSize,
            color: Colors.white,
            letterSpacing: 1.6,
            shadows: <Shadow>[
              Shadow(
                color: AppColors.brandYellow.withValues(alpha: 0.55),
                blurRadius: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal scrollable row of every available avatar. Selected
  /// avatar (matching the current pending one) gets a glowing yellow
  /// ring + slight scale-up. Tap → [UserService.setPendingAvatar]
  /// updates only the avatar (handle stays).
  Widget _buildAvatarPicker({required final bool isTablet}) {
    final List<RemoteAvatar> avatars = AvatarService.instance.all;
    if (avatars.isEmpty) return const SizedBox.shrink();
    final String? selectedId =
        UserService.instance.pendingHandle?.avatarId;
    final double tileSize = isTablet ? 52 : 44;
    return SizedBox(
      height: tileSize + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: avatars.length,
        separatorBuilder: (final _, final _) => const SizedBox(width: 8),
        itemBuilder: (final BuildContext context, final int i) {
          final RemoteAvatar a = avatars[i];
          final bool isSelected = a.id == selectedId;
          return _AvatarTile(
            avatar: a,
            size: tileSize,
            isSelected: isSelected,
            onTap: _saving
                ? null
                : () {
                    AudioHelper.select();
                    UserService.instance.setPendingAvatar(a.id);
                  },
          );
        },
      ),
    );
  }

  Widget _buildPrimaryButton(final double fontSize, final double vPad) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saving ? null : _onConfirm,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: vPad),
          backgroundColor: AppColors.brandYellow,
          foregroundColor: Colors.black,
          disabledBackgroundColor:
              AppColors.brandYellow.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _saving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.black,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.check_circle_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "THAT'S ME!",
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Single tappable avatar tile in the welcome-card picker. Selected
/// state is animated (border brightens, ring glows, slight scale-up)
/// so the user gets clear visual confirmation of their choice.
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.avatar,
    required this.size,
    required this.isSelected,
    required this.onTap,
  });

  final RemoteAvatar avatar;
  final double size;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? AppColors.brandYellow.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: isSelected
                ? AppColors.brandYellow
                : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.brandYellow.withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            avatar.emoji,
            style: TextStyle(fontSize: size * 0.55),
          ),
        ),
      ),
    );
  }
}
