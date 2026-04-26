import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/helmet_data.dart';
import '../models/ride_stats.dart';
import '../services/bluetooth_service.dart';
import '../services/emergency_contact_service.dart';
import '../services/emergency_profile_service.dart';
import '../services/ride_service.dart';
import '../widgets/connection_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/ride_session_card.dart';
import '../widgets/section_title.dart';
import '../widgets/status_card.dart';
import 'emergency_contact_page.dart';
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
  final EmergencyContactService _emergencyContactService =
      EmergencyContactService();
  final EmergencyProfileService _emergencyProfileService =
      EmergencyProfileService();

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

  int _selectedTabIndex = 0;

  static const Color _accent = Color(0xFFFC4C02);
  static const Color _bg = Color(0xFFF7F7F7);
  static const Color _card = Colors.white;
  static const Color _danger = Color(0xFFD32F2F);
  static const Color _success = Color(0xFF2E7D32);
  static const Color _deep = Color(0xFF161616);

  static const List<_DashboardTab> _tabs = [
    _DashboardTab(
      label: 'Home',
      title: 'RideGuard Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _DashboardTab(
      label: 'Ride',
      title: 'Ride Control',
      icon: Icons.route_outlined,
      selectedIcon: Icons.route_rounded,
    ),
    _DashboardTab(
      label: 'Health',
      title: 'Health Metrics',
      icon: Icons.favorite_outline,
      selectedIcon: Icons.favorite,
    ),
    _DashboardTab(
      label: 'Safety',
      title: 'Safety Details',
      icon: Icons.shield_outlined,
      selectedIcon: Icons.shield_rounded,
    ),
  ];

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

    final uniqueDevices = <String, BluetoothDevice>{};
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
      final jsonMap = jsonDecode(line) as Map<String, dynamic>;
      final parsed = HelmetData.fromJson(jsonMap);

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
          (position) {
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

  Future<_EmergencyDetailsData> _loadEmergencyDetails() async {
    final results = await Future.wait<Map<String, dynamic>?>([
      _emergencyContactService.fetchPrimaryContact(),
      _emergencyProfileService.fetchProfile(),
    ]);

    return _EmergencyDetailsData(
      contact: results[0],
      profile: results[1],
    );
  }

  Future<void> _showEmergencyDetails() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<_EmergencyDetailsData>(
          future: _loadEmergencyDetails(),
          builder: (context, snapshot) {
            return _EmergencyDetailsSheet(
              snapshot: snapshot,
              accentColor: _accent,
              cardColor: _card,
              onEdit: () {
                Navigator.of(context).pop();
                _openEmergencyEditor();
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openEmergencyEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EmergencyContactPage()),
    );
  }

  Future<void> _openRideArchive() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RideArchivePage()),
    );
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

  String _statusHeadline() {
    if (_helmetData?.crash == true) return 'Crash detected';
    if (_helmetData?.dontDrive == true) return 'Unsafe to ride';
    if (_helmetData?.coAlert == true) return 'CO alert active';
    if (_isRideActive) return 'Ride is live';
    if (_isConnected) return 'Helmet connected';
    return 'Helmet offline';
  }

  Widget _buildCurrentPage(HelmetData? data) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildHomeTab(data);
      case 1:
        return _buildRideTab(data);
      case 2:
        return _buildHealthTab(data);
      case 3:
        return _buildSafetyTab(data);
      default:
        return _buildHomeTab(data);
    }
  }

  Widget _buildHomeTab(HelmetData? data) {
    final alerts = <_AlertBadgeData>[
      _AlertBadgeData(
        label: data?.crash == true ? 'Crash detected' : 'No crash',
        isActive: data?.crash == true,
        color: _danger,
      ),
      _AlertBadgeData(
        label: data?.coAlert == true ? 'CO alert' : 'CO stable',
        isActive: data?.coAlert == true,
        color: _danger,
      ),
      _AlertBadgeData(
        label: data?.obstacleWarning == true ? 'Obstacle ahead' : 'Path clear',
        isActive: data?.obstacleWarning == true,
        color: Colors.orange,
      ),
      _AlertBadgeData(
        label: data?.dontDrive == true ? 'Do not drive' : 'Ride OK',
        isActive: data?.dontDrive == true,
        color: _danger,
      ),
    ];

    return _DashboardScrollView(
      children: [
        _HeroSummaryCard(
          accentColor: _accent,
          deepColor: _deep,
          headline: _statusHeadline(),
          status: _status,
          isConnected: _isConnected,
          isRideActive: _isRideActive,
          position: data?.position ?? '--',
          onEmergencyPressed: _showEmergencyDetails,
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Critical Live Metrics'),
        _MetricGrid(
          minTileWidth: 150,
          childAspectRatio: 1.18,
          children: [
            MetricCard(
              title: 'Speed (km/h)',
              value: _formatDouble(_speedKmh, 1),
              icon: Icons.speed_outlined,
              cardColor: _card,
              valueColor: _speedKmh != null && _speedKmh! > 60
                  ? Colors.orange.shade700
                  : null,
            ),
            MetricCard(
              title: 'BPM',
              value: _formatInt(data?.bpm),
              icon: Icons.favorite_outline,
              cardColor: _card,
            ),
            MetricCard(
              title: 'SpO2',
              value: _formatInt(data?.spo2),
              icon: Icons.bloodtype_outlined,
              cardColor: _card,
            ),
            MetricCard(
              title: 'CO',
              value: _formatInt(data?.co),
              icon: Icons.air_outlined,
              cardColor: _card,
              valueColor: data?.coAlert == true ? _danger : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Safety Snapshot'),
        _AlertOverviewCard(alerts: alerts, cardColor: _card),
      ],
    );
  }

  Widget _buildRideTab(HelmetData? data) {
    return _DashboardScrollView(
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
          onStartRide: _startRide,
          onEndRide: _endRide,
          accentColor: _accent,
          cardColor: _card,
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Ride Tracking'),
        _MetricGrid(
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openRideArchive,
            icon: const Icon(Icons.history),
            label: const Text('Open ride archive'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthTab(HelmetData? data) {
    return _DashboardScrollView(
      children: [
        _SectionIntroCard(
          title: 'Rider health in detail',
          subtitle:
              'Vitals stay separated here so the main page only shows the numbers you need at a glance.',
          icon: Icons.monitor_heart_outlined,
          accentColor: _accent,
          cardColor: _card,
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: 'Health Metrics'),
        _MetricGrid(
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
              valueColor: data?.crash == true ? _danger : null,
              cardColor: _card,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSafetyTab(HelmetData? data) {
    return _DashboardScrollView(
      children: [
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
        const SectionTitle(title: 'Environment'),
        _MetricGrid(
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
              valueColor: data?.coAlert == true ? _danger : null,
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
        const SectionTitle(title: 'Motion & Impact'),
        _MetricGrid(
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
        const SectionTitle(title: 'Debug Feed'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            _lastRawLine.isEmpty ? '--' : _lastRawLine,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
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
    final tab = _tabs[_selectedTabIndex];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          tab.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Emergency info',
            icon: const Icon(Icons.emergency_outlined),
            onPressed: _showEmergencyDetails,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey(_selectedTabIndex),
          child: _buildCurrentPage(data),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        indicatorColor: _accent.withValues(alpha: 0.16),
        backgroundColor: Colors.white,
        destinations: _tabs
            .map(
              (tab) => NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DashboardTab {
  final String label;
  final String title;
  final IconData icon;
  final IconData selectedIcon;

  const _DashboardTab({
    required this.label,
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });
}

class _DashboardScrollView extends StatelessWidget {
  final List<Widget> children;

  const _DashboardScrollView({required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double childAspectRatio;

  const _MetricGrid({
    required this.children,
    this.minTileWidth = 165,
    this.childAspectRatio = 1.35,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = math.max(
          1,
          (constraints.maxWidth / minTileWidth).floor(),
        );

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}

class _HeroSummaryCard extends StatelessWidget {
  final Color accentColor;
  final Color deepColor;
  final String headline;
  final String status;
  final bool isConnected;
  final bool isRideActive;
  final String position;
  final VoidCallback onEmergencyPressed;

  const _HeroSummaryCard({
    required this.accentColor,
    required this.deepColor,
    required this.headline,
    required this.status,
    required this.isConnected,
    required this.isRideActive,
    required this.position,
    required this.onEmergencyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [deepColor, accentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(
                label: isConnected ? 'Connected' : 'Offline',
                icon: isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
              ),
              _HeroChip(
                label: isRideActive ? 'Ride live' : 'Ride idle',
                icon: isRideActive
                    ? Icons.pedal_bike_rounded
                    : Icons.pedal_bike_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.assistant_navigation, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Helmet position: $position',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onEmergencyPressed,
              icon: const Icon(Icons.emergency_outlined),
              label: const Text('Show emergency details'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: deepColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _HeroChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionIntroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color cardColor;

  const _SectionIntroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBadgeData {
  final String label;
  final bool isActive;
  final Color color;

  const _AlertBadgeData({
    required this.label,
    required this.isActive,
    required this.color,
  });
}

class _AlertOverviewCard extends StatelessWidget {
  final List<_AlertBadgeData> alerts;
  final Color cardColor;

  const _AlertOverviewCard({
    required this.alerts,
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
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: alerts
            .map(
              (alert) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: alert.isActive
                      ? alert.color.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  alert.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: alert.isActive ? alert.color : Colors.grey.shade800,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _EmergencyDetailsData {
  final Map<String, dynamic>? contact;
  final Map<String, dynamic>? profile;

  const _EmergencyDetailsData({
    required this.contact,
    required this.profile,
  });
}

class _EmergencyDetailsSheet extends StatelessWidget {
  final AsyncSnapshot<_EmergencyDetailsData> snapshot;
  final Color accentColor;
  final Color cardColor;
  final VoidCallback onEdit;

  const _EmergencyDetailsSheet({
    required this.snapshot,
    required this.accentColor,
    required this.cardColor,
    required this.onEdit,
  });

  String _readValue(Map<String, dynamic>? source, String key) {
    final value = source?[key];
    if (value == null) return '--';
    final text = value.toString().trim();
    return text.isEmpty ? '--' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                )
              : snapshot.hasError
              ? SizedBox(
                  height: 280,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 38,
                        color: Color(0xFFD32F2F),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Could not load emergency details.',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Open emergency info'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                        ),
                      ),
                    ],
                  ),
                )
              : Builder(
                  builder: (context) {
                    final details = snapshot.data;
                    final contact = details?.contact;
                    final profile = details?.profile;
                    final hasAnyData = contact != null || profile != null;

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Emergency Details',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Text(
                            hasAnyData
                                ? 'Critical rider info, ready to review quickly.'
                                : 'No emergency profile saved yet.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _EmergencySectionCard(
                            title: 'Primary Contact',
                            cardColor: cardColor,
                            children: [
                              _EmergencyDetailRow(
                                label: 'Name',
                                value: _readValue(contact, 'full_name'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Phone',
                                value: _readValue(contact, 'phone'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Relationship',
                                value: _readValue(contact, 'relationship'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _EmergencySectionCard(
                            title: 'Medical Info',
                            cardColor: cardColor,
                            children: [
                              _EmergencyDetailRow(
                                label: 'Blood Type',
                                value: _readValue(profile, 'blood_type'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Medications',
                                value: _readValue(profile, 'medications'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Allergies',
                                value: _readValue(profile, 'allergies'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Insurance',
                                value: _readValue(profile, 'insurance_info'),
                              ),
                              _EmergencyDetailRow(
                                label: 'Notes',
                                value: _readValue(profile, 'medical_notes'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(
                                hasAnyData
                                    ? 'Edit emergency info'
                                    : 'Add emergency info',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: accentColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _EmergencySectionCard extends StatelessWidget {
  final String title;
  final Color cardColor;
  final List<Widget> children;

  const _EmergencySectionCard({
    required this.title,
    required this.cardColor,
    required this.children,
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
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _EmergencyDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _EmergencyDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
