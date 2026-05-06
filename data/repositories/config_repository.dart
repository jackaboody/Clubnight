// data/repositories/config_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:squash_social/domain/models/app_config.dart';

class ConfigRepository {
  final FirebaseFirestore _db;
  static const _docPath = 'config/settings';

  ConfigRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  Stream<AppConfig> watchConfig() {
    return _db
        .doc(_docPath)
        .snapshots()
        .map(AppConfig.fromFirestore);
  }

  Future<void> setMatchDuration(int minutes) {
    return _db.doc(_docPath).set(
          {'matchDurationMinutes': minutes},
          SetOptions(merge: true),
        );
  }

  Future<void> setMaxDoubleCourts(int max) {
    return _db.doc(_docPath).set(
          {'maxDoubleCourts': max},
          SetOptions(merge: true),
        );
  }

  Future<void> setFairnessMode(bool enabled) {
    return _db.doc(_docPath).set(
          {'fairnessModeEnabled': enabled},
          SetOptions(merge: true),
        );
  }

  /// Seeds default config if the document doesn't exist.
  Future<void> seedDefaults() {
    return _db.doc(_docPath).set(
          const AppConfig().toFirestore(),
          SetOptions(merge: true),
        );
  }
}
