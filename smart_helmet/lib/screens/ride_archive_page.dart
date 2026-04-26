import 'package:flutter/material.dart';

import '../services/ride_service.dart';

class RideArchivePage extends StatefulWidget {
  const RideArchivePage({super.key});

  @override
  State<RideArchivePage> createState() => _RideArchivePageState();
}

class _RideArchivePageState extends State<RideArchivePage> {
  final RideService _rideService = RideService();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rides = [];

  @override
  void initState() {
    super.initState();
    _loadRides();
  }

  Future<void> _loadRides() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rides = await _rideService.fetchRides();

      if (!mounted) return;

      setState(() {
        _rides = rides;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--';

    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '--';

    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  String _formatNum(dynamic value, [int decimals = 1]) {
    if (value == null) return '--';
    if (value is num) return value.toStringAsFixed(decimals);
    return value.toString();
  }

  String _formatInt(dynamic value) {
    if (value == null) return '--';
    if (value is num) return value.round().toString();
    return value.toString();
  }

  Widget _buildFlag(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? Colors.red.withValues(alpha: 0.10)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: active ? Colors.red.shade700 : Colors.grey.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Archive')),
      body: RefreshIndicator(
        onRefresh: _loadRides,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $_error'),
                  ),
                ],
              )
            : _rides.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No rides found yet.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _rides.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final ride = _rides[index];

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateTime(ride['started_at'] as String?),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start: ${_formatDateTime(ride['started_at'] as String?)}',
                        ),
                        Text(
                          'End: ${_formatDateTime(ride['ended_at'] as String?)}',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFlag('Crash', ride['had_crash'] == true),
                            _buildFlag(
                              'Obstacle',
                              ride['had_obstacle_alert'] == true,
                            ),
                            _buildFlag(
                              'CO Alert',
                              ride['had_co_alert'] == true,
                            ),
                            _buildFlag(
                              'Dont Drive',
                              ride['had_dont_drive_alert'] == true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Max speed: ${_formatNum(ride['max_speed_kmh'])} km/h',
                        ),
                        Text(
                          'Avg speed: ${_formatNum(ride['avg_speed_kmh'])} km/h',
                        ),
                        Text('Max BPM: ${_formatInt(ride['max_bpm'])}'),
                        Text('Avg BPM: ${_formatInt(ride['avg_bpm'])}'),
                        Text('Min SpO2: ${_formatInt(ride['min_spo2'])}'),
                        Text('Max CO: ${_formatInt(ride['max_co'])}'),
                        Text(
                          'Max alcohol: ${_formatNum(ride['max_alcohol'], 3)} mg/L',
                        ),
                        Text(
                          'Avg temp: ${_formatNum(ride['avg_temperature'])} °C',
                        ),
                        Text(
                          'Avg humidity: ${_formatNum(ride['avg_humidity'])} %',
                        ),
                        Text(
                          'Max force: ${_formatNum(ride['max_force'], 2)} N',
                        ),
                        Text(
                          'Min distance: ${_formatNum(ride['min_distance'])} cm',
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
