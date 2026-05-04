import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mini_kickers/data/models/match_player.dart';

/// A friend-pairing room. One player creates a room (gets a 4-char
/// code), shares the code, the second player joins, both clients
/// listen on the same `rooms/{code}` doc and pick up the
/// auto-generated match id when it appears.
///
/// Schema (Firestore `rooms/{code}`):
///   • created_by               — MatchPlayer object of the host
///   • match_id                 — null until the second player joins
///                                (then set atomically by the join op)
///   • status                   — `'open' | 'matched' | 'expired'`
///   • created_at / ttl         — auto-delete after 24h via TTL policy
///
/// Doc id IS the user-visible code (uppercase, e.g. `K7M3`). We keep
/// the alphabet narrow on purpose — no `0/O`, no `1/I/L`, no `B/8` —
/// so verbal sharing ("K seven M three") works without confusion.
class RoomCode {
  const RoomCode({
    required this.code,
    required this.createdBy,
    required this.status,
    this.matchId,
    this.createdAt,
  });

  final String code;
  final MatchPlayer createdBy;
  final RoomStatus status;
  /// Set the moment the second player joins; both clients listen for
  /// this field appearing and navigate to the match.
  final String? matchId;
  final Timestamp? createdAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'created_by': createdBy.toMap(),
        'status': status.wireValue,
        if (matchId != null) 'match_id': matchId,
      };

  factory RoomCode.fromMap(
    final String code,
    final Map<String, dynamic> data,
  ) {
    final Map<String, dynamic> creator = ((data['created_by']
                as Map<dynamic, dynamic>?) ??
            const <String, dynamic>{})
        .cast<String, dynamic>();
    return RoomCode(
      code: code,
      createdBy: MatchPlayer.fromMap(creator),
      status: RoomStatusX.fromWire(data['status'] as String?),
      matchId: data['match_id'] as String?,
      createdAt: data['created_at'] as Timestamp?,
    );
  }
}

enum RoomStatus { open, matched, expired }

extension RoomStatusX on RoomStatus {
  String get wireValue {
    switch (this) {
      case RoomStatus.open:
        return 'open';
      case RoomStatus.matched:
        return 'matched';
      case RoomStatus.expired:
        return 'expired';
    }
  }

  static RoomStatus fromWire(final String? raw) {
    switch (raw) {
      case 'matched':
        return RoomStatus.matched;
      case 'expired':
        return RoomStatus.expired;
      default:
        return RoomStatus.open;
    }
  }
}
