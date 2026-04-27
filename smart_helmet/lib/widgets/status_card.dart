import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final String statusText;
  final Color statusColor;
  final bool crash;
  final bool obstacle;
  final bool coAlert;
  final bool dontDrive;
  final Color dangerColor;

  const StatusCard({
    super.key,
    required this.statusText,
    required this.statusColor,
    required this.crash,
    required this.obstacle,
    required this.coAlert,
    required this.dontDrive,
    required this.dangerColor,
  });

  Widget _alertChip(String label, bool active, {Color? activeColor}) {
    final color = activeColor ?? dangerColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: active ? color : Colors.grey.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
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
            statusText,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _alertChip(crash ? 'Crash detected' : 'No crash', crash),
              _alertChip(
                obstacle ? 'Obstacle ahead' : 'Path clear',
                obstacle,
                activeColor: Colors.orange,
              ),
              _alertChip(coAlert ? 'CO alert' : 'CO normal', coAlert),
              _alertChip(dontDrive ? 'Do not drive' : 'Drive OK', dontDrive),
            ],
          ),
        ],
      ),
    );
  }
}
