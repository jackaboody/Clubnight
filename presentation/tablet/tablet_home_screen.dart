// presentation/tablet/tablet_home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/presentation/providers/providers.dart';
import 'package:squash_social/presentation/tablet/widgets/court_card.dart';
import 'package:squash_social/presentation/tablet/widgets/stats_bar.dart';
import 'package:squash_social/presentation/tablet/widgets/admin_panel.dart';
import 'package:squash_social/presentation/tablet/widgets/add_player_dialog.dart';
import 'package:squash_social/presentation/controllers/scheduling_controller.dart';

class TabletHomeScreen extends ConsumerWidget {
  const TabletHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courtsAsync = ref.watch(courtsStreamProvider);
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      appBar: AppBar(
        title: const Text('Squash Social Night'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add player',
            onPressed: () => _showAddPlayer(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Admin',
            onPressed: () => _showAdminPanel(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          statsAsync.when(
            data: (stats) => StatsBar(stats: stats),
            loading: () => const SizedBox(height: 56),
            error: (_, __) => const SizedBox(height: 56),
          ),

          // Court grid
          Expanded(
            child: courtsAsync.when(
              data: (courts) => Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: courts.length,
                  itemBuilder: (_, i) => CourtCard(court: courts[i]),
                ),
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error loading courts: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPlayer(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AddPlayerDialog(
        onAdded: () => ref.read(schedulingControllerProvider.notifier).onPlayerJoined(),
      ),
    );
  }

  void _showAdminPanel(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AdminPanel(),
    );
  }
}
