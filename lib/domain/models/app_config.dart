// lib/domain/models/app_config.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class AppConfig {
  final int matchDurationMinutes;
  final int maxDoubleCourts;
  final bool fairnessModeEnabled;

  const AppConfig({
    this.matchDurationMinutes = 20,
    this.maxDoubleCourts = 2,
    this.fairnessModeEnabled = true,
  });

  factory AppConfig.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return const AppConfig();
    final d = doc.data() as Map<String, dynamic>;
    return AppConfig(
      matchDurationMinutes: d['matchDurationMinutes'] as int? ?? 20,
      maxDoubleCourts: d['maxDoubleCourts'] as int? ?? 2,
      fairnessModeEnabled: d['fairnessModeEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'matchDurationMinutes': matchDurationMinutes,
        'maxDoubleCourts': maxDoubleCourts,
        'fairnessModeEnabled': fairnessModeEnabled,
      };

  AppConfig copyWith({
    int? matchDurationMinutes,
    int? maxDoubleCourts,
    bool? fairnessModeEnabled,
  }) =>
      AppConfig(
        matchDurationMinutes: matchDurationMinutes ?? this.matchDurationMinutes,
        maxDoubleCourts: maxDoubleCourts ?? this.maxDoubleCourts,
        fairnessModeEnabled: fairnessModeEnabled ?? this.fairnessModeEnabled,
      );
}
