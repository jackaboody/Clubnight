// domain/models/player.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum PlayerStatus { waiting, playing, unavailable }

class Player {
  final String id;
  final String name;
  final double level;
  final PlayerStatus status;
  final bool prefersDoubles;
  final int matchesPlayed;
  final DateTime? lastPlayedAt;
  final String? currentMatchId;
  final DateTime createdAt;
  final List<String> recentOpponents;

  const Player({
    required this.id,
    required this.name,
    required this.level,
    required this.status,
    required this.prefersDoubles,
    required this.matchesPlayed,
    required this.createdAt,
    this.lastPlayedAt,
    this.currentMatchId,
    this.recentOpponents = const [],
  });

  factory Player.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Player(
      id: doc.id,
      name: d['name'] as String,
      level: (d['level'] as num).toDouble(),
      status: PlayerStatus.values.byName(d['status'] as String? ?? 'waiting'),
      prefersDoubles: d['prefersDoubles'] as bool? ?? false,
      matchesPlayed: d['matchesPlayed'] as int? ?? 0,
      lastPlayedAt: (d['lastPlayedAt'] as Timestamp?)?.toDate(),
      currentMatchId: d['currentMatchId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recentOpponents:
          List<String>.from(d['recentOpponents'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'level': level,
        'status': status.name,
        'prefersDoubles': prefersDoubles,
        'matchesPlayed': matchesPlayed,
        'lastPlayedAt':
            lastPlayedAt != null ? Timestamp.fromDate(lastPlayedAt!) : null,
        'currentMatchId': currentMatchId,
        'createdAt': Timestamp.fromDate(createdAt),
        'recentOpponents': recentOpponents,
      };

  Player copyWith({
    String? name,
    double? level,
    PlayerStatus? status,
    bool? prefersDoubles,
    int? matchesPlayed,
    DateTime? lastPlayedAt,
    String? currentMatchId,
    List<String>? recentOpponents,
  }) =>
      Player(
        id: id,
        name: name ?? this.name,
        level: level ?? this.level,
        status: status ?? this.status,
        prefersDoubles: prefersDoubles ?? this.prefersDoubles,
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        currentMatchId: currentMatchId ?? this.currentMatchId,
        createdAt: createdAt,
        recentOpponents: recentOpponents ?? this.recentOpponents,
      );
}
