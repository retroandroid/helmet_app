import 'package:flutter/material.dart';

class RideSessionCard extends StatelessWidget {
  final bool isRideActive;
  final String startText;
  final String endText;
  final VoidCallback onStartRide;
  final VoidCallback onEndRide;
  final Color accentColor;
  final Color cardColor;

  const RideSessionCard({
    super.key,
    required this.isRideActive,
    required this.startText,
    required this.endText,
    required this.onStartRide,
    required this.onEndRide,
    required this.accentColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRideActive ? 'Ride in progress' : 'No active ride',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isRideActive ? accentColor : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start: $startText',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'End: $endText',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout = constraints.maxWidth < 360;

              final startButton = FilledButton(
                onPressed: isRideActive ? null : onStartRide,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Start Ride'),
              );

              final endButton = OutlinedButton(
                onPressed: isRideActive ? onEndRide : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('End Ride'),
              );

              if (useVerticalLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    startButton,
                    const SizedBox(height: 10),
                    endButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: startButton),
                  const SizedBox(width: 10),
                  Expanded(child: endButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
