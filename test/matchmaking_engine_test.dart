// test/matchmaking_engine_test.dart
//
// Pure Dart tests — no Flutter, no Firebase, no mocks needed.
// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:squash_social/domain/matchmaking/matchmaking_engine.dart';
import 'package:squash_social/domain/models/match.dart' show MatchType;
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/domain/models/app_config.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Player makePlayer({
  required String id,
  required String name,
  double level = 3.0,
  PlayerStatus status = PlayerStatus.waiting,
  bool prefersDoubles = false,
  int matchesPlayed = 0,
  DateTime? lastPlayedAt,
  DateTime? createdAt,
}) =>
    Player(
      id: id,
      name: name,
      level: level,
      status: status,
      prefersDoubles: prefersDoubles,
      matchesPlayed: matchesPlayed,
      lastPlayedAt: lastPlayedAt,
      createdAt: createdAt ??
          DateTime.now().subtract(const Duration(hours: 1)),
    );

const defaultConfig = AppConfig(
  matchDurationMinutes: 20,
  maxDoubleCourts: 2,
  fairnessModeEnabled: true,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  const engine = MatchmakingEngine();

  group('basic singles matching', () {
    test('returns null when fewer than 2 waiting players', () {
      final result = engine.findBestMatch(
        waitingPlayers: [makePlayer(id: 'a', name: 'Alice')],
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNull);
    });

    test('returns a singles match for 2 players', () {
      final players = [
        makePlayer(id: 'a', name: 'Alice'),
        makePlayer(id: 'b', name: 'Bob'),
      ];
      final result = engine.findBestMatch(
        waitingPlayers: players,
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNotNull);
      expect(result!.type, MatchType.singles);
      expect(result.players.length, 2);
    });

    test('prefers the longest-waiting player', () {
      final longWaiter = makePlayer(
        id: 'long',
        name: 'Long',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      final shortWaiter = makePlayer(
        id: 'short',
        name: 'Short',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final opponent = makePlayer(
        id: 'opp',
        name: 'Opp',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final result = engine.findBestMatch(
        waitingPlayers: [longWaiter, shortWaiter, opponent],
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );

      expect(result, isNotNull);
      // Long waiter should be in the winning group.
      expect(result!.players.any((p) => p.id == 'long'), isTrue);
    });
  });

  group('fairness mode', () {
    test('fairness ON prefers player with fewer matches played', () {
      final fresh = makePlayer(id: 'fresh', name: 'Fresh', matchesPlayed: 0);
      final veteran =
          makePlayer(id: 'vet', name: 'Veteran', matchesPlayed: 10);
      final opponent =
          makePlayer(id: 'opp', name: 'Opp', matchesPlayed: 1);

      final result = engine.findBestMatch(
        waitingPlayers: [fresh, veteran, opponent],
        config: const AppConfig(fairnessModeEnabled: true),
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      // Group containing 'fresh' should beat group containing 'veteran'.
      expect(result, isNotNull);
      expect(result!.players.any((p) => p.id == 'fresh'), isTrue);
    });

    test('fairness OFF does not penalise high match counts', () {
      final fresh = makePlayer(
        id: 'fresh',
        name: 'Fresh',
        matchesPlayed: 0,
        // Fresh player just arrived — short wait.
        createdAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      final veteran = makePlayer(
        id: 'vet',
        name: 'Veteran',
        matchesPlayed: 20,
        // Veteran has been waiting a long time.
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
        lastPlayedAt: DateTime.now().subtract(const Duration(minutes: 40)),
      );
      final opponent = makePlayer(
        id: 'opp',
        name: 'Opp',
        matchesPlayed: 5,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      // With fairness OFF, wait time dominates — veteran should be selected.
      final result = engine.findBestMatch(
        waitingPlayers: [fresh, veteran, opponent],
        config: const AppConfig(fairnessModeEnabled: false),
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNotNull);
      expect(result!.players.any((p) => p.id == 'vet'), isTrue);
    });
  });

  group('skill matching', () {
    test('prefers groups with similar skill levels', () {
      final low1 = makePlayer(id: 'l1', name: 'Low1', level: 1.5);
      final low2 = makePlayer(id: 'l2', name: 'Low2', level: 1.5);
      final high = makePlayer(id: 'h1', name: 'High', level: 5.0);

      // low1 vs low2 should be preferred over low1 vs high.
      final result = engine.findBestMatch(
        waitingPlayers: [low1, low2, high],
        config: const AppConfig(fairnessModeEnabled: false),
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNotNull);
      expect(result!.players.map((p) => p.id).toSet(),
          containsAll(['l1', 'l2']));
    });
  });

  group('doubles matching', () {
    test('does not create doubles if no players prefer it', () {
      final players = List.generate(
        6,
        (i) => makePlayer(
            id: 'p$i', name: 'Player $i', prefersDoubles: false),
      );
      final result = engine.findBestMatch(
        waitingPlayers: players,
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNotNull);
      expect(result!.type, MatchType.singles);
    });

    test(
        'creates doubles when enough players prefer it and capacity allows',
        () {
      final players = List.generate(
        4,
        (i) => makePlayer(
            id: 'p$i', name: 'Player $i', prefersDoubles: true),
      );
      final result = engine.findBestMatch(
        waitingPlayers: players,
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      expect(result, isNotNull);
      expect(result!.type, MatchType.doubles);
      expect(result.players.length, 4);
    });

    test('respects maxDoubleCourts limit', () {
      final players = List.generate(
        6,
        (i) => makePlayer(
            id: 'p$i', name: 'Player $i', prefersDoubles: true),
      );
      // Already at the limit.
      final result = engine.findBestMatch(
        waitingPlayers: players,
        config: const AppConfig(maxDoubleCourts: 1),
        activeDoubleCourts: 1, // already one doubles court active
        recentPairings: {},
      );
      expect(result, isNotNull);
      // Should fall back to singles.
      expect(result!.type, MatchType.singles);
    });
  });

  group('recent pairing penalty', () {
    test('avoids re-pairing players who just played together', () {
      final a = makePlayer(id: 'a', name: 'Alice');
      final b = makePlayer(id: 'b', name: 'Bob');
      final c = makePlayer(id: 'c', name: 'Carol');

      // Alice and Bob just played together.
      final recentPairings = {
        'a': ['b'],
        'b': ['a'],
      };

      final result = engine.findBestMatch(
        waitingPlayers: [a, b, c],
        config: const AppConfig(fairnessModeEnabled: false),
        activeDoubleCourts: 0,
        recentPairings: recentPairings,
      );
      expect(result, isNotNull);
      // Should prefer a+c or b+c over a+b.
      final ids = result!.players.map((p) => p.id).toSet();
      expect(ids.contains('a') && ids.contains('b'), isFalse);
    });
  });

  group('scale test', () {
    test('handles 30 waiting players without error and within 100ms', () {
      final players = List.generate(
        30,
        (i) => makePlayer(
          id: 'p$i',
          name: 'Player $i',
          level: 1.0 + (i % 5) * 0.8,
          prefersDoubles: i % 3 == 0,
          matchesPlayed: i % 6,
        ),
      );
      final stopwatch = Stopwatch()..start();
      final result = engine.findBestMatch(
        waitingPlayers: players,
        config: defaultConfig,
        activeDoubleCourts: 0,
        recentPairings: {},
      );
      stopwatch.stop();

      expect(result, isNotNull);
      // Should complete in well under 100ms even at scale.
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
