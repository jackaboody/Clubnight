// lib/core/constants.dart

class AppConstants {
  AppConstants._();

  // Firestore collection paths
  static const String playersCollection = 'players';
  static const String courtsCollection = 'courts';
  static const String matchesCollection = 'matches';
  static const String configDoc = 'config/settings';

  // Court IDs — must match seeded documents
  static int courtCount = 6;
  static String courtId(int n) => 'court_$n';

  // Matchmaking defaults (also stored in Firestore config)
  static const int defaultMatchDurationMinutes = 20;
  static const int defaultMaxDoubleCourts = 2;
  static const bool defaultFairnessModeEnabled = true;

  // Recent pairing history window (entries kept per player)
  static const int recentOpponentHistorySize = 12;

  // Matchmaking weights
  static const double waitWeight = 2.0;
  static const double fairnessWeight = 1.5;
  static const double skillWeight = 1.0;
  static const double skillTolerance = 1.0;
  static const double doublesBonus = 0.92;
  static const int pairingDecayMatches = 3;
}
