// lib/presentation/mobile/player_home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/presentation/providers/providers.dart';
import 'package:squash_social/presentation/mobile/widgets/player_status_card.dart';

class PlayerHomeScreen extends ConsumerWidget {
  final String playerId;

  const PlayerHomeScreen({super.key, required this.playerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAsync = ref.watch(playerMatchViewProvider(playerId));

    return Scaffold(
      appBar: AppBar(
        title: viewAsync.when(
          data: (view) => Text(view.player.name),
          loading: () => const Text('Loading…'),
          error: (_, __) => const Text('Player'),
        ),
        centerTitle: true,
      ),
      body: viewAsync.when(
        data: (view) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(playerMatchViewProvider(playerId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PlayerStatusCard(playerId: playerId),
              const SizedBox(height: 16),
              _MatchHistorySection(matchesPlayed: view.player.matchesPlayed),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _MatchHistorySection extends StatelessWidget {
  final int matchesPlayed;
  const _MatchHistorySection({required this.matchesPlayed});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.bar_chart_outlined, size: 20),
            const SizedBox(width: 12),
            Text(
              'Matches played tonight: $matchesPlayed',
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
