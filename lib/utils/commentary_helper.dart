import 'dart:math';

import 'package:mini_kickers/data/models/game_models.dart';
import 'package:mini_kickers/data/services/settings_service.dart';

class CommentaryHelper {
  CommentaryHelper._();

  static final Random _rng = Random();

  static const List<String> rolling = <String>[
    'Here comes the roll...',
    'The dice is in the air!',
    'Tension is building...',
    'Eyes on the dice!',
    'What will fate decide?',
    'The crowd holds its breath...',
  ];

  static const List<String> highRoll = <String>[
    'A {d}! What a roll! Plenty of ground to cover!',
    'Rolling a {d} — the pitch opens up!',
    '{d}! This could be a game-changer!',
    'A big {d}! Red alert for the opposition!',
  ];

  static const List<String> lowRoll = <String>[
    'Just a {d}... sometimes less is more.',
    'A {d}. Tight but tactical!',
    'Only {d} steps — precision play needed!',
    'A {d}! Small roll, big brain required.',
  ];

  static const List<String> midRoll = <String>[
    'A solid {d}! Good options here.',
    "Rolled a {d} — let's see what {team} does with it.",
    "{d}! Right in the middle, keep 'em guessing!",
    'A {d} for {team}. Not bad at all!',
  ];

  static const List<String> noMoves = <String>[
    'Nowhere to go! Turn passes to {other}.',
    'Blocked out! {other} takes advantage.',
    'No valid moves — {other} must be loving this!',
    'Stuck! The dice taketh away...',
  ];

  static const List<String> selectToken = <String>[
    'Pick your player, {team}!',
    '{team} — choose your warrior wisely!',
    'Which token makes the move?',
    'Select your piece and make it count!',
  ];

  static const List<String> tokenMoved = <String>[
    'Nice positioning by {team}!',
    '{team} repositions — the pressure is on!',
    'Smart movement from {team}!',
    'Good footwork! {team} finds some space.',
    '{team} on the march!',
  ];

  static const List<String> ballControl = <String>[
    'BALL CONTROL! {team} has possession!',
    '{team} picks up the ball — danger!',
    'Possession is 9/10ths of the law! {team} has it!',
    'The ball falls to {team} — what a moment!',
    '{team} takes control! The crowd erupts!',
  ];

  static const List<String> ballMoved = <String>[
    'The ball is moving! Things are heating up!',
    'Clever pass by {team}!',
    '{team} advances the ball up the pitch!',
    'Good ball movement from {team}!',
    "The ball is in play — who'll get to it next?",
  ];

  static const List<String> goal = <String>[
    'GOOOOAL! {team} finds the back of the net!',
    "IT'S IN! {team} scores a beauty!",
    'WHAT A GOAL! {team} is on the board!',
    'THE CROWD GOES WILD! {team} scores!',
    'UNSTOPPABLE! {team} makes it count!',
  ];

  static const List<String> gameStart = <String>[
    "Welcome to Mini Kickers! Let's play!",
    'Kick-off time! {team} goes first. Good luck both teams!',
    'The whistle blows! {team} starts things off!',
    'Game on, {team}! May the best team win!',
  ];

  static const List<String> gameEnd = <String>[
    'Full time! What a match!',
    "The final whistle blows! It's all over!",
    "Time's up! The scoreboard tells the story!",
  ];

  static const List<String> winRed = <String>[
    'RED WINS! A dominant performance!',
    'Victory for Red! Deserved champions today!',
    'Red takes the trophy! Magnificent!',
  ];

  static const List<String> winBlue = <String>[
    'BLUE WINS! Outstanding display!',
    'Blue lifts the cup! Brilliant football!',
    'Blue are the champions! What a game!',
  ];

  static const List<String> draw = <String>[
    "IT'S A DRAW! Both teams share the spoils!",
    'All square! A fair result on the day!',
    'Level at the final whistle! Honours even!',
  ];

  static const List<String> resetBoard = <String>[
    'Resetting the board — both sides back to positions!',
    'Back to the centre — can {other} respond?',
    'Kick-off again! {other} looking to hit back!',
  ];

  static String pick(
    final List<String> arr, {
    final Map<String, String>? vars,
  }) {
    String str = arr[_rng.nextInt(arr.length)];
    if (vars != null) {
      vars.forEach((final String k, final String v) {
        str = str.replaceAll('{$k}', v);
      });
    }
    return str;
  }

  static String teamLabel(final Team t) {
    final String name = t == Team.red
        ? SettingsService.instance.redName
        : SettingsService.instance.blueName;
    return t == Team.red ? '🔴 $name' : '🔵 $name';
  }

  static String otherLabel(final Team t) =>
      t == Team.red ? teamLabel(Team.blue) : teamLabel(Team.red);
}
