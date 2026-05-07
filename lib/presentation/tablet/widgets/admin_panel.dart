// lib/presentation/tablet/widgets/admin_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:squash_social/domain/models/court.dart';
import 'package:squash_social/domain/models/player.dart';
import 'package:squash_social/presentation/providers/providers.dart';
import 'package:squash_social/data/repositories/config_repository.dart';
import 'package:squash_social/data/repositories/court_repository.dart';
import 'package:squash_social/data/repositories/player_repository.dart';

class AdminPanel extends ConsumerStatefulWidget {
  const AdminPanel({super.key});

  @override
  ConsumerState<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanel> {
  late TextEditingController _durationController;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider).valueOrNull;
    _durationController = TextEditingController(
      text: '${config?.matchDurationMinutes ?? 20}',
    );
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(configProvider);
    final courtsAsync = ref.watch(courtsStreamProvider);
    final playersAsync = ref.watch(playersStreamProvider);
    final configRepo = ConfigRepository();
    final courtRepo = CourtRepository();
    final playerRepo = PlayerRepository();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Admin controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Match duration
            Text('Match duration (minutes)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    final current =
                        int.tryParse(_durationController.text) ?? 20;
                    if (current > 5) {
                      final next = current - 5;
                      _durationController.text = '$next';
                      configRepo.setMatchDuration(next);
                    }
                  },
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _durationController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    onSubmitted: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed >= 5) {
                        configRepo.setMatchDuration(parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final current =
                        int.tryParse(_durationController.text) ?? 20;
                    final next = current + 5;
                    _durationController.text = '$next';
                    configRepo.setMatchDuration(next);
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Fairness mode toggle
            configAsync.when(
              data: (config) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fairness mode'),
                subtitle: const Text(
                    'Prioritise players with fewer matches played tonight'),
                value: config.fairnessModeEnabled,
                onChanged: (val) => configRepo.setFairnessMode(val),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // Court mode controls
            Text('Court modes',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            courtsAsync.when(
              data: (courts) => Column(
                children: courts
                    .map((court) => _CourtModeRow(
                          court: court,
                          courtRepo: courtRepo,
                        ))
                    .toList(),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error loading courts'),
            ),

            const SizedBox(height: 24),

            // Players
            Text('Players', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            playersAsync.when(
              data: (players) => players.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No players yet',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : Column(
                      children: players
                          .map((p) => _PlayerRow(
                                player: p,
                                playerRepo: playerRepo,
                              ))
                          .toList(),
                    ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Text('Error loading players'),
            ),

            const SizedBox(height: 32),

            // Reset evening
            OutlinedButton.icon(
              onPressed:
                  _resetting ? null : () => _confirmReset(context, ref),
              icon: _resetting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, color: Colors.red),
              label: const Text(
                'Reset evening',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset evening?'),
        content: const Text(
          'This will remove all players and clear all matches. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _resetting = true);
      try {
        await ref.read(matchRepositoryProvider).resetEvening();
      } finally {
        if (mounted) setState(() => _resetting = false);
      }
    }
  }
}

class _CourtModeRow extends StatelessWidget {
  final Court court;
  final CourtRepository courtRepo;

  const _CourtModeRow({required this.court, required this.courtRepo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('Court ${court.number}',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          SegmentedButton<CourtMode>(
            segments: const [
              ButtonSegment(
                  value: CourtMode.singles, label: Text('Singles')),
              ButtonSegment(
                  value: CourtMode.doubles, label: Text('Doubles')),
              ButtonSegment(
                  value: CourtMode.holding, label: Text('Hold')),
            ],
            selected: {court.mode},
            onSelectionChanged: (selection) =>
                courtRepo.setCourtMode(court.id, selection.first),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final Player player;
  final PlayerRepository playerRepo;

  const _PlayerRow({required this.player, required this.playerRepo});

  @override
  Widget build(BuildContext context) {
    final isResting = player.status == PlayerStatus.unavailable;
    final isPlaying = player.status == PlayerStatus.playing;

    final statusColor = isPlaying
        ? Colors.green
        : isResting
            ? Colors.grey
            : Colors.blue;
    final statusLabel = isPlaying ? 'Playing' : isResting ? 'Resting' : 'Waiting';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Level ${player.level.toStringAsFixed(1)} · ${player.matchesPlayed} played',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Rest / Activate toggle (disabled while playing)
          Tooltip(
            message: isResting ? 'Set active' : 'Set resting',
            child: IconButton(
              icon: Icon(
                isResting ? Icons.play_circle_outline : Icons.pause_circle_outline,
                size: 20,
              ),
              onPressed: isPlaying
                  ? null
                  : () => playerRepo.updateStatus(
                        player.id,
                        isResting
                            ? PlayerStatus.waiting
                            : PlayerStatus.unavailable,
                      ),
            ),
          ),
          // Remove player
          Tooltip(
            message: 'Remove player',
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.red,
              onPressed: () => playerRepo.removePlayer(player.id),
            ),
          ),
        ],
      ),
    );
  }
}
