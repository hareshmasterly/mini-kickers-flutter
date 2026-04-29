import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mini_kickers/data/models/faq.dart';
import 'package:mini_kickers/data/services/faq_service.dart';
import 'package:mini_kickers/data/services/settings_service.dart';
import 'package:mini_kickers/theme/app_colors.dart';
import 'package:mini_kickers/theme/app_fonts.dart';
import 'package:mini_kickers/utils/audio_helper.dart';
import 'package:mini_kickers/views/ads/banner_ad_widget.dart';
import 'package:mini_kickers/views/guide/widget/contact_tile.dart';
import 'package:mini_kickers/views/guide/widget/faq_item.dart';
import 'package:mini_kickers/views/guide/widget/guide_section.dart';
import 'package:mini_kickers/views/home/widget/buy_amazon_button.dart';
import 'package:mini_kickers/views/home/widget/stadium_background.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.stadiumDeep,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const StadiumBackground(),
          SafeArea(
            bottom: MediaQuery.of(context).padding.bottom > 0 ? false : true,
            child: Column(
              children: <Widget>[
                _Header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const <Widget>[
                        _OverviewSection(),
                        _HowToPlaySection(),
                        _SetupAndRulesSection(),
                        _FeaturesSection(),
                        _FaqSection(),
                        _ContactSection(),
                        _CtaSection(),
                      ],
                    ),
                  ),
                ),
                // Bottom banner ad — gated remotely by `show_ads` +
                // `show_guide_banner`. Wrapped in a ListenableBuilder
                // so a remote flip during the session takes effect
                // without leaving the screen.
                ListenableBuilder(
                  listenable: SettingsService.instance,
                  builder: (final BuildContext context, final Widget? _) {
                    final SettingsService s = SettingsService.instance;
                    if (!s.showAds || !s.showGuideBanner) {
                      return const SizedBox.shrink();
                    }
                    return const Center(child: BannerAdWidget());
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// HEADER
// ═════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () {
              AudioHelper.select();
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            },
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'GAME GUIDE',
            style: AppFonts.bebasNeue(
              fontSize: 32,
              letterSpacing: 6,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: AppColors.accent.withValues(alpha: 0.45),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// OVERVIEW
// ═════════════════════════════════════════════════════════════════════════

class _OverviewSection extends StatelessWidget {
  const _OverviewSection();

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const GuideSectionHeader(
          icon: Icons.sports_soccer_rounded,
          title: 'WELCOME TO MINI KICKERS',
          subtitle: "India's #1 Indoor Football Board Game",
          color: AppColors.accent,
        ),
        GuideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "A two-player strategy football board game where you roll the dice, move your tokens, and chase the ball into the opponent's goal.",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _InfoChip(icon: '👥', text: '2 Players'),
                  _InfoChip(icon: '⏱️', text: '15 Min'),
                  _InfoChip(icon: '🎯', text: 'Ages 5+'),
                  _InfoChip(icon: '🏆', text: 'Most Goals Win'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(final BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// HOW TO PLAY
// ═════════════════════════════════════════════════════════════════════════

class _HowToPlaySection extends StatelessWidget {
  const _HowToPlaySection();

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const GuideSectionHeader(
          icon: Icons.play_circle_fill_rounded,
          title: 'HOW TO PLAY',
          subtitle: 'Roll · Move · Score — in 4 simple steps',
          color: AppColors.brandYellow,
        ),
        const GuideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GuideBullet(
                icon: '🪙',
                title: '1. Coin toss',
                body:
                    'Flip the coin to decide who kicks off. The winner rolls first.',
              ),
              Divider(color: Colors.white12, height: 18),
              GuideBullet(
                icon: '🎲',
                title: '2. Roll the dice',
                body:
                    'On your turn, tap ROLL DICE. Move one of your tokens exactly that many spaces — horizontal or vertical only, no diagonals. You can change direction as many times as you like.',
              ),
              Divider(color: Colors.white12, height: 18),
              GuideBullet(
                icon: '⚽',
                title: '3. Reach the football',
                body:
                    'Land directly on the football to take possession. You then roll again and move the ball that many spaces.',
              ),
              Divider(color: Colors.white12, height: 18),
              GuideBullet(
                icon: '🥅',
                title: '4. Score a goal',
                body:
                    "Push the football into the opponent's goal to score 1 point. After a goal, the conceded team kicks off the next play.",
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// SETUP & RULES
// ═════════════════════════════════════════════════════════════════════════

class _SetupAndRulesSection extends StatelessWidget {
  const _SetupAndRulesSection();

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const GuideSectionHeader(
          icon: Icons.rule_rounded,
          title: 'SETUP & RULES',
          subtitle: 'Pitch layout and movement rules',
          color: AppColors.blue,
        ),
        const GuideCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RuleHeading(text: 'PITCH SETUP'),
              SizedBox(height: 6),
              GuideBullet(
                icon: '📐',
                title: '11 × 7 grid',
                body:
                    'Two goal mouths face each other on the left and right edges, each 3 cells tall.',
              ),
              GuideBullet(
                icon: '👫',
                title: '3 tokens each',
                body:
                    "Red tokens start on the left, Blue tokens on the right. The football starts at the centre spot.",
              ),
              Divider(color: Colors.white12, height: 22),
              _RuleHeading(text: 'MOVEMENT RULES'),
              SizedBox(height: 6),
              GuideBullet(
                icon: '➡️',
                title: 'Exact-step movement',
                body:
                    'Tokens must move exactly the dice value, no more, no less. You can\'t end on an occupied cell.',
              ),
              GuideBullet(
                icon: '🚫',
                title: 'No diagonals',
                body:
                    'Only horizontal and vertical moves are allowed. Tokens can\'t enter goal cells (only the ball can).',
              ),
              GuideBullet(
                icon: '🛑',
                title: 'No valid move?',
                body:
                    'If you have no legal move on this roll, your turn ends and the opponent rolls.',
              ),
              Divider(color: Colors.white12, height: 22),
              _RuleHeading(text: 'BALL RULES'),
              SizedBox(height: 6),
              GuideBullet(
                icon: '🎯',
                title: 'Possession unlocks bonus roll',
                body:
                    'Land on the ball → roll the dice again → move the ball exactly that many cells.',
              ),
              GuideBullet(
                icon: '🛡️',
                title: 'No own-goals',
                body:
                    "You can't push the ball into your own goal — the cell will simply not be available as a destination.",
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleHeading extends StatelessWidget {
  const _RuleHeading({required this.text});

  final String text;

  @override
  Widget build(final BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.accent.withValues(alpha: 0.9),
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// FEATURES
// ═════════════════════════════════════════════════════════════════════════

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  static const List<
    ({IconData icon, String title, String tagline, Color color})
  >
  _features = <({IconData icon, String title, String tagline, Color color})>[
    (
      icon: Icons.palette_rounded,
      title: 'VIBRANT',
      tagline: 'Bright kid-\nfriendly design',
      color: AppColors.brandRed,
    ),
    (
      icon: Icons.people_alt_rounded,
      title: '2-PLAYER',
      tagline: 'Quick 15-min\nfamily matches',
      color: AppColors.blue,
    ),
    (
      icon: Icons.card_giftcard_rounded,
      title: 'GIFT-READY',
      tagline: 'Birthdays &\nparty favourite',
      color: AppColors.brandYellow,
    ),
    (
      icon: Icons.flight_takeoff_rounded,
      title: 'PORTABLE',
      tagline: 'Battery-free\nplay anywhere',
      color: AppColors.limeBright,
    ),
  ];

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const GuideSectionHeader(
          icon: Icons.auto_awesome_rounded,
          title: 'FEATURES',
          subtitle: 'Why kids and families love Mini Kickers',
          color: AppColors.brandRed,
        ),
        GuideCard(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
          child: LayoutBuilder(
            builder: (final BuildContext ctx, final BoxConstraints cons) {
              // Single row on tablet/landscape, 2x2 on phones
              final bool oneRow = cons.maxWidth >= 460;
              if (oneRow) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _features
                      .asMap()
                      .entries
                      .map<Widget>(
                        (
                          final MapEntry<
                            int,
                            ({
                              IconData icon,
                              String title,
                              String tagline,
                              Color color,
                            })
                          >
                          e,
                        ) => Expanded(
                          child: _FeatureBadge(item: e.value, index: e.key),
                        ),
                      )
                      .toList(),
                );
              }
              return Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _FeatureBadge(item: _features[0], index: 0),
                      ),
                      Expanded(
                        child: _FeatureBadge(item: _features[1], index: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _FeatureBadge(item: _features[2], index: 2),
                      ),
                      Expanded(
                        child: _FeatureBadge(item: _features[3], index: 3),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeatureBadge extends StatefulWidget {
  const _FeatureBadge({required this.item, required this.index});

  final ({IconData icon, String title, String tagline, Color color}) item;
  final int index;

  @override
  State<_FeatureBadge> createState() => _FeatureBadgeState();
}

class _FeatureBadgeState extends State<_FeatureBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    Future<void>.delayed(Duration(milliseconds: 350 + widget.index * 220), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final Color c = widget.item.color;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (final BuildContext context, final Widget? child) {
        final double pulse = (1 - (_ctrl.value - 0.5).abs() * 2);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Iconic gradient circle with pulsing glow
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.4),
                    colors: <Color>[
                      Color.lerp(c, Colors.white, 0.45)!,
                      c,
                      Color.lerp(c, Colors.black, 0.25)!,
                    ],
                    stops: const <double>[0.0, 0.55, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2.5,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: c.withValues(alpha: 0.55 + pulse * 0.35),
                      blurRadius: 14 + pulse * 10,
                      spreadRadius: 1 + pulse * 2,
                    ),
                    const BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  widget.item.icon,
                  size: 30,
                  color: Colors.white,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black38, blurRadius: 4),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Bold title in team color
              Text(
                widget.item.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color.lerp(c, Colors.white, 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  shadows: <Shadow>[
                    Shadow(color: c.withValues(alpha: 0.55), blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Two-line tagline
              Text(
                widget.item.tagline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// FAQ
// ═════════════════════════════════════════════════════════════════════════

class _FaqSection extends StatelessWidget {
  const _FaqSection();

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const GuideSectionHeader(
          icon: Icons.help_outline_rounded,
          title: 'FAQ',
          subtitle: 'Quick answers to common questions',
          color: AppColors.blueLight,
        ),
        ListenableBuilder(
          listenable: FaqService.instance,
          builder: (final BuildContext context, final Widget? _) {
            // First-time loading on a brand-new install with no cache —
            // brief skeleton until Firestore responds (or the timeout
            // fires and falls back to the hardcoded list).
            if (FaqService.instance.isLoadingFirstTime) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.blueLight,
                    strokeWidth: 2.4,
                  ),
                ),
              );
            }
            final List<Faq> items = FaqService.instance.faqs;
            return Column(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 8),
                  FaqItem(question: items[i].question, answer: items[i].answer),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// CONTACT
// ═════════════════════════════════════════════════════════════════════════

class _ContactSection extends StatelessWidget {
  const _ContactSection();

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const <Widget>[
        GuideSectionHeader(
          icon: Icons.support_agent_rounded,
          title: 'CONTACT US',
          subtitle: 'Get in touch — we\'d love to hear from you',
          color: AppColors.brandGreen,
        ),
        ContactTile(
          icon: Icons.phone_rounded,
          label: 'CALL',
          value: '+91 93273 58462',
          color: AppColors.brandGreen,
          launchUrl: 'tel:+919327358462',
          copyValue: '+919327358462',
        ),
        SizedBox(height: 8),
        ContactTile(
          icon: Icons.email_rounded,
          label: 'EMAIL',
          value: 'contact@minikickers.in',
          color: AppColors.brandRed,
          launchUrl: 'mailto:contact@minikickers.in',
          copyValue: 'contact@minikickers.in',
        ),
        SizedBox(height: 8),
        ContactTile(
          icon: Icons.public_rounded,
          label: 'WEBSITE',
          value: 'minikickers.in',
          color: AppColors.blue,
          launchUrl: 'https://www.minikickers.in',
          copyValue: 'https://www.minikickers.in',
        ),
        SizedBox(height: 8),
        ContactTile(
          icon: Icons.location_on_rounded,
          label: 'OFFICE',
          value:
              'PNTC Tower, F-906, Radio Mirchi Rd, Vejalpur, Ahmedabad 380015',
          color: AppColors.brandYellow,
          launchUrl: 'https://maps.apple.com/?q=PNTC+Tower+Vejalpur+Ahmedabad',
          copyValue:
              'PNTC Tower, F-906, Radio Mirchi Road, Vejalpur, Ahmedabad, Gujarat 380015',
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// CTA — buy the board game
// ═════════════════════════════════════════════════════════════════════════

class _CtaSection extends StatelessWidget {
  const _CtaSection();

  @override
  Widget build(final BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Column(
        children: <Widget>[
          Text(
            "ENJOYING THE GAME?",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'GET THE PHYSICAL BOARD',
            style: AppFonts.bebasNeue(
              fontSize: 24,
              letterSpacing: 3,
              color: Colors.white,
              shadows: <Shadow>[
                Shadow(
                  color: AppColors.brandYellow.withValues(alpha: 0.55),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const BuyAmazonButton(),
          const SizedBox(height: 18),
          Text(
            'Bringing the thrill of football to your home — one game at a time!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
