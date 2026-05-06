// data/repositories/player_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/player.dart';

class PlayerRepository {
  final FirebaseFirestore _db;

  PlayerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  Stream<List<Player>> watchAllPlayers() {
    return _db
        .collection('players')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(Player.fromFirestore).toList());
  }

  Stream<Player?> watchPlayer(String playerId) {
    return _db
        .collection('players')
        .doc(playerId)
        .snapshots()
        .map((doc) => doc.exists ? Player.fromFirestore(doc) : null);
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<String> addPlayer({
    required String name,
    required double level,
    required bool prefersDoubles,
  }) async {
    final ref = await _db.collection('players').add({
      'name': name,
      'level': level,
      'status': PlayerStatus.waiting.name,
      'prefersDoubles': prefersDoubles,
      'matchesPlayed': 0,
      'lastPlayedAt': null,
      'currentMatchId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'recentOpponents': [],
    });
    return ref.id;
  }

  Future<void> updateStatus(String playerId, PlayerStatus status) {
    return _db.collection('players').doc(playerId).update({
      'status': status.name,
    });
  }

  Future<void> updateDoublesPreference(String playerId, bool prefersDoubles) {
    return _db.collection('players').doc(playerId).update({
      'prefersDoubles': prefersDoubles,
    });
  }

  Future<void> removePlayer(String playerId) {
    return _db.collection('players').doc(playerId).delete();
  }
}
