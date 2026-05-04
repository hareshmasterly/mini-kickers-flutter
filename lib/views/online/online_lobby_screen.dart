import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/match_player.dart';
import 'package:mini_kickers/data/models/user_profile.dart';
import 'package:mini_kickers/data/services/user_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/analytics_helper.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';
import 'package:mini_kickers/views/online/matchmaking_screen.dart';
import 'package:mini_kickers/views/online/room_create_screen.dart';
import 'package:mini_kickers/views/online/room_join_screen.dart';
import 'package:mini_kickers/views/online/widget/avatar_chip.dart';
import 'package:mini_kickers/views/online/widget/online_action_button.dart';

/// Hub screen for online 1v1. Three primary actions:
///   • FIND MATCH  — drops the user into the random matchmaking queue.
///                   Pushed onto a [MatchmakingScreen] which polls + waits.
///   • CREATE ROOM — generates a 4-letter friend-pair code on the
///                   [RoomCreateScreen] and waits for someone to join.
///   • JOIN ROOM   — opens [RoomJoinScreen] for code entry.
///
/// All three sub-screens pop with a [String?] match id. When non-null,
/// the lobby pops itself with that match id so the home screen (the
/// caller) can drive the actual game-screen navigation in Pass 4.
///
/// Pre-condition: [UserService.profile] must be non-null. The home
/// screen guarantees this via the welcome-card flow on first launch,
/// so practical access from the home button is always safe. If the
/// profile is somehow null when we reach this screen, we render a
/// "Please restart the app" fallback rather than crashing.
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  @override
  void initState() {
    super.initState();
    Analytics.logOnlineLobbyOpened();
  }

  Future<void> _pushAndPopIfMatched(final Widget screen) async {
    final String? matchId = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        fullscreenDialog: false,
        builder: (final BuildContext _) => screen,
      ),
    );
    if (!mounted) return;
    // Bubble the match id up to the home screen — it owns the
    // game-screen launch flow and will hand the id to the
    // OnlineGameController (Pass 3+4).
    if (matchId != null) {
      Navigator.of(context).pop(matchId);
    }
  }

  void _onFindMatch() => _pushAndPopIfMatched(const MatchmakingScreen());
  void _onCreateRoom() => _pushAndPopIfMatched(const RoomCreateScreen());
  void _onJoinRoom() => _pushAndPopIfMatched(const RoomJoinScreen());

  @override
  Widget build(final BuildContext context) {
    final UserProfile? profile = UserService.instance.profile;
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            child: profile == null
                ? const _ProfileMissingFallback()
                : _LobbyBody(profile: profile, onFindMatch: _onFindMatch,
                    onCreateRoom: _onCreateRoom, onJoinRoom: _onJoinRoom),
          ),
          // Floating back button — top-left, glass style to match the
          // home screen's circle icon buttons.
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _BackPill(
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.profile,
    required this.onFindMatch,
    required this.onCreateRoom,
    required this.onJoinRoom,
  });

  final UserProfile profile;
  final VoidCallback onFindMatch;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;

  @override
  Widget build(final BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final bool isTablet = screen.shortestSide >= 600;
    final bool short = screen.height < 460;
    final double maxBodyWidth = isTablet ? 540 : 420;
    final double avatarSize = short ? 64 : (isTablet ? 96 : 80);

    final MatchPlayer self = MatchPlayer(
      uid: profile.uid,
      handle: profile.handle,
      displayName: profile.displayName,
      avatarId: profile.avatarId,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBodyWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'PLAY ONLINE',
                style: AppFonts.bebasNeue(
                  fontSize: short ? 28 : (isTablet ? 56 : 40),
                  letterSpacing: 6,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(
                      color: AppColors.brandYellow.withValues(alpha: 0.6),
                      blurRadius: 22,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Match up with another player anywhere',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: short ? 11 : 13,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: short ? 18 : 28),
              AvatarChip(player: self, size: avatarSize),
              SizedBox(height: short ? 18 : 28),
              _LobbyOptionCard(
                icon: Icons.travel_explore_rounded,
                label: 'FIND MATCH',
                subtitle: "We'll pair you with someone waiting",
                onTap: onFindMatch,
                accent: AppColors.brandYellow,
              ),
              const SizedBox(height: 12),
              _LobbyOptionCard(
                icon: Icons.add_circle_outline_rounded,
                label: 'CREATE ROOM',
                subtitle: 'Get a code to share with a friend',
                onTap: onCreateRoom,
                accent: AppColors.brandGreen,
              ),
              const SizedBox(height: 12),
              _LobbyOptionCard(
                icon: Icons.login_rounded,
                label: 'JOIN ROOM',
                subtitle: "Got a code from a friend? Tap here",
                onTap: onJoinRoom,
                accent: AppColors.brandRed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LobbyOptionCard extends StatelessWidget {
  const _LobbyOptionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(final BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 1.4,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.22),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppFonts.bebasNeue(
                        fontSize: 20,
                        letterSpacing: 2.4,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.glassWhite,
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

/// Defensive fallback if the welcome-card flow somehow didn't run.
/// Should never appear in normal usage — the home screen blocks the
/// "PLAY ONLINE" button until [UserService.profile] is non-null.
class _ProfileMissingFallback extends StatelessWidget {
  const _ProfileMissingFallback();

  @override
  Widget build(final BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              "We couldn't load your profile.\nPlease restart the app.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            OnlineActionButton(
              label: 'BACK',
              onTap: () => Navigator.of(context).pop(),
              primary: false,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}
