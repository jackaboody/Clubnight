// presentation/tablet/widgets/stats_bar.dart

import 'package:flutter/material.dart';
import 'package:squash_social/presentation/providers/providers.dart';

class StatsBar extends StatelessWidget {
  final OrganizerStats stats;

  const StatsBar({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final fairnessColor = stats.fairnessScore < 1.0
        ? Colors.green
        : stats.fairnessScore < 2.0
            ? Colors.orange
            : Colors.red;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _StatChip(
            label: 'Total',
            value: '${stats.totalPlayers}',
            icon: Icons.people_outline,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Waiting',
            value: '${stats.waiting}',
            icon: Icons.hourglass_empty,
            valueColor: Colors.orange,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Playing',
            value: '${stats.playing}',
            icon: Icons.sports_tennis,
            valueColor: Colors.green,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Singles',
            value: '${stats.activeSingles}',
            icon: Icons.person,
          ),
          const SizedBox(width: 12),
          _StatChip(
            label: 'Doubles',
            value: '${stats.activeDoubles}',
            icon: Icons.people,
          ),
          const Spacer(),
          // Fairness indicator
          Row(
            children: [
              Icon(Icons.balance, size: 16, color: fairnessColor),
              const SizedBox(width: 4),
              Text(
                'Fairness σ: ${stats.fairnessScore.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: fairnessColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message:
                    'Standard deviation of matches played.\nLower = more even distribution.',
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
