import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/helmet_data.dart';
import '../models/ride_stats.dart';
import '../services/bluetooth_service.dart';
import '../services/ride_service.dart';
import '../widgets/connection_card.dart';
import '../widgets/ride_session_card.dart';
import '../widgets/status_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_title.dart';
import 'ride_archive_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final BluetoothService _bluetoothService = BluetoothService();
  final RideService _rideService = RideService();
  final RideStats _rideStats = RideStats();

  List<BluetoothDevice> _pairedDevices = [];
  String? _selectedDeviceAddress;
  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<Position>? _positionSubscription;

  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isConnected = false;

  String _status = 'Not connected';
  String _lastRawLine = '';
  HelmetData? _helmetData;

  bool _isRideActive = false;
  DateTime? _rideStartedAt;
  DateTime? _rideEndedAt;
  int? _currentRideId;

  double? _latitude;
  double? _longitude;
  double? _speedKmh;

  static const Color _accent = Color(0xFFFC4C02);
  static const Color _bg = Color(0xFFF7F7F7);
  static const Color _card = Colors.white;
  static const Color _danger = Color(0xFFD32F2F);
  static const Color _success = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _isLoadingDevices = true;
      _status = 'Loading paired devices...';
    });

    final devices = await _bluetoothService.getPairedDevices();

    final Map<String, BluetoothDevice> uniqueDevices = {};
    for (final device in devices) {
      uniqueDevices[device.address] = device;
    }

    final dedupedDevices = uniqueDevices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;

    setState(() {
      _pairedDevices = dedupedDevices;

      if (_selectedDeviceAddress != null) {
        final stillExists = dedupedDevices.any(
          (device) => device.address == _selectedDeviceAddress,
        );
        if (!stillExists) {
          _selectedDeviceAddress = null;
        }
      }

      _isLoadingDevices = false;
      _status = dedupedDevices.isEmpty
          ? 'No paired Bluetooth devices found'
          : 'Select your device';
    });
  }

  Future<void> _connect() async {
    if (_selectedDeviceAddress == null) {
      setState(() {
        _status = 'Please select a paired device first';
      });
      return;
    }

    final selectedDevice = _pairedDevices.firstWhere(
      (device) => device.address == _selectedDeviceAddress,
    );

    setState(() {
      _isConnecting = true;
      _status =
          'Connecting to ${selectedDevice.name.isNotEmpty ? selectedDevice.name : selectedDevice.address}...';
    });

    final connected = await _bluetoothService.connect(selectedDevice.address);

    if (!mounted) return;

    if (!connected) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _status = 'Connection failed';
      });
      return;
    }

    await _dataSubscription?.cancel();
    _dataSubscription = _bluetoothService.rawLines.listen(
      _handleRawLine,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _status = 'Bluetooth stream error';
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _status = 'Disconnected';
        });
      },
    );

    setState(() {
      _isConnecting = false;
      _isConnected = true;
      _status = 'Connected';
    });
  }

  Future<void> _disconnect() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;

    await _bluetoothService.disconnect();

    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _status = 'Disconnected';
    });
  }

  void _handleRawLine(String line) {
    if (!mounted) return;

    setState(() {
      _lastRawLine = line;
    });

    try {
      final Map<String, dynamic> jsonMap = jsonDecode(line);
      final HelmetData parsed = HelmetData.fromJson(jsonMap);

      setState(() {
        _helmetData = parsed;
        _status = 'Receiving live data';

        if (_isRideActive) {
          _rideStats.addSample(
            speedKmh: _speedKmh,
            bpm: parsed.bpm,
            spo2: parsed.spo2,
            co: parsed.co,
            alcohol: parsed.alcohol,
            temperature: parsed.temperature,
            humidity: parsed.humidity,
            force: parsed.force,
            distance: parsed.distance,
            crash: parsed.crash,
            obstacle: parsed.obstacleWarning,
            coAlert: parsed.coAlert,
            dontDrive: parsed.dontDrive,
          );
        }
      });
    } catch (_) {
      setState(() {
        _status = 'Connected, waiting for valid JSON';
      });
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = 'Location services are disabled';
      });
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        _status = 'Location permission denied';
      });
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status = 'Location permission permanently denied';
      });
      return false;
    }

    return true;
  }

  Future<void> _startLocationTracking() async {
    final allowed = await _ensureLocationPermission();
    if (!allowed) return;

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = current.latitude;
          _longitude = current.longitude;
          _speedKmh = (current.speed.isFinite ? current.speed : 0.0) * 3.6;

          if (_isRideActive) {
            _rideStats.addSample(speedKmh: _speedKmh);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = 'Could not get current location';
        });
      }
    }

    await _positionSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!mounted) return;

            setState(() {
              _latitude = position.latitude;
              _longitude = position.longitude;
              _speedKmh =
                  (position.speed.isFinite ? position.speed : 0.0) * 3.6;

              if (_isRideActive) {
                _rideStats.addSample(speedKmh: _speedKmh);
              }
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _status = 'Location stream error';
            });
          },
        );
  }

  Future<void> _stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _startRide() async {
    final startedAt = DateTime.now();

    setState(() {
      _rideStats.reset();
      _isRideActive = true;
      _rideStartedAt = startedAt;
      _rideEndedAt = null;
      _currentRideId = null;
      _latitude = null;
      _longitude = null;
      _speedKmh = null;
    });

    await _startLocationTracking();

    try {
      final rideId = await _rideService.createRide(
        startedAt: startedAt,
        startLat: _latitude,
        startLng: _longitude,
      );

      if (!mounted) return;

      setState(() {
        _currentRideId = rideId;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _status = 'Failed to create ride in database';
      });
    }
  }

  Future<void> _endRide() async {
    await _stopLocationTracking();

    final endedAt = DateTime.now();
    final rideId = _currentRideId;

    setState(() {
      _isRideActive = false;
      _rideEndedAt = endedAt;
    });

    if (rideId == null) return;

    try {
      await _rideService.endRide(
        rideId: rideId,
        endedAt: endedAt,
        endLat: _latitude,
        endLng: _longitude,
        stats: _rideStats,
      );

      if (!mounted) return;

      setState(() {
        _currentRideId = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _status = 'Failed to end ride in database';
      });
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  String _formatDouble(double? value, [int decimals = 1]) {
    if (value == null) return '--';
    return value.toStringAsFixed(decimals);
  }

  String _formatInt(int? value) {
    if (value == null) return '--';
    return value.toString();
  }

  Color _statusColor() {
    if (_helmetData?.crash == true ||
        _helmetData?.dontDrive == true ||
        _helmetData?.coAlert == true) {
      return _danger;
    }
    if (_isConnected) return _success;
    return Colors.grey.shade700;
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _positionSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _helmetData;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'RideGuard Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RideArchivePage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionCard(
                pairedDevices: _pairedDevices,
                selectedDeviceAddress: _selectedDeviceAddress,
                isConnected: _isConnected,
                isConnecting: _isConnecting,
                isLoadingDevices: _isLoadingDevices,
                onDeviceChanged: (value) {
                  setState(() {
                    _selectedDeviceAddress = value;
                  });
                },
                onConnect: _connect,
                onDisconnect: _disconnect,
                onRefresh: _loadPairedDevices,
                accentColor: _accent,
                cardColor: _card,
              ),
              const SizedBox(height: 18),
              RideSessionCard(
                isRideActive: _isRideActive,
                startText: _formatDateTime(_rideStartedAt),
                endText: _formatDateTime(_rideEndedAt),
                onStartRide: () {
                  _startRide();
                },
                onEndRide: () {
                  _endRide();
                },
                accentColor: _accent,
                cardColor: _card,
              ),
              const SizedBox(height: 18),
              StatusCard(
                statusText: _status,
                statusColor: _statusColor(),
                positionText: data?.position ?? '--',
                crash: data?.crash == true,
                obstacle: data?.obstacleWarning == true,
                coAlert: data?.coAlert == true,
                dontDrive: data?.dontDrive == true,
                dangerColor: _danger,
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Ride Tracking'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  MetricCard(
                    title: 'Latitude',
                    value: _formatDouble(_latitude, 6),
                    icon: Icons.place_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Longitude',
                    value: _formatDouble(_longitude, 6),
                    icon: Icons.map_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Speed (km/h)',
                    value: _formatDouble(_speedKmh, 1),
                    icon: Icons.speed_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Ride Active',
                    value: _isRideActive ? 'YES' : 'NO',
                    icon: Icons.pedal_bike_outlined,
                    valueColor: _isRideActive ? _accent : null,
                    cardColor: _card,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Health'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  MetricCard(
                    title: 'BPM',
                    value: _formatInt(data?.bpm),
                    icon: Icons.favorite_outline,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Avg BPM',
                    value: _formatInt(data?.avgBpm),
                    icon: Icons.monitor_heart_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'SpO2',
                    value: _formatInt(data?.spo2),
                    icon: Icons.bloodtype_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Force (N)',
                    value: _formatDouble(data?.force, 2),
                    icon: Icons.fitness_center_outlined,
                    cardColor: _card,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Environment'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  MetricCard(
                    title: 'Temp (°C)',
                    value: _formatDouble(data?.temperature),
                    icon: Icons.thermostat_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Humidity (%)',
                    value: _formatDouble(data?.humidity),
                    icon: Icons.water_drop_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Distance (cm)',
                    value: _formatDouble(data?.distance),
                    icon: Icons.social_distance_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'CO',
                    value: _formatInt(data?.co),
                    icon: Icons.air_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Alcohol (mg/L)',
                    value: _formatDouble(data?.alcohol, 3),
                    icon: Icons.local_bar_outlined,
                    valueColor: data?.dontDrive == true ? _danger : null,
                    cardColor: _card,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Motion'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  MetricCard(
                    title: 'Pitch',
                    value: _formatDouble(data?.pitch),
                    icon: Icons.screen_rotation_alt_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Roll',
                    value: _formatDouble(data?.roll),
                    icon: Icons.threesixty_outlined,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Obstacle',
                    value: data?.obstacleWarning == true ? 'YES' : 'NO',
                    icon: Icons.warning_amber_rounded,
                    valueColor: data?.obstacleWarning == true
                        ? Colors.orange
                        : null,
                    cardColor: _card,
                  ),
                  MetricCard(
                    title: 'Crash',
                    value: data?.crash == true ? 'YES' : 'NO',
                    icon: Icons.report_problem_outlined,
                    valueColor: data?.crash == true ? _danger : null,
                    cardColor: _card,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Debug'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _lastRawLine.isEmpty ? '--' : _lastRawLine,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
