import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

import '../models/helmet_data.dart';
import '../services/bluetooth_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final BluetoothService _bluetoothService = BluetoothService();

  List<BluetoothDevice> _pairedDevices = [];
  String? _selectedDeviceAddress;
  StreamSubscription<String>? _dataSubscription;

  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isConnected = false;

  String _status = 'Not connected';
  String _lastRawLine = '';
  HelmetData? _helmetData;

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
          : 'Select your ESP32 device';
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
      final parsed = HelmetData.fromJson(jsonMap);

      setState(() {
        _helmetData = parsed;
        _status = 'Receiving live data';
      });
    } catch (_) {
      setState(() {
        _status = 'Connected, waiting for valid JSON';
      });
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _bluetoothService.dispose();
    super.dispose();
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    IconData? icon,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(height: 10),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertChip(String label, bool active, {Color? activeColor}) {
    final color = activeColor ?? _danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.12) : Colors.grey.shade200,
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
    final data = _helmetData;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Smart Helmet Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
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
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedDeviceAddress,
                      isExpanded: true,
                      items: _pairedDevices.map((device) {
                        final label = device.name.isNotEmpty
                            ? '${device.name} (${device.address})'
                            : device.address;
                        return DropdownMenuItem<String>(
                          value: device.address,
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: _isConnected
                          ? null
                          : (value) {
                              setState(() {
                                _selectedDeviceAddress = value;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'Paired Bluetooth device',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed:
                            (_isConnecting || _isLoadingDevices || _isConnected)
                            ? null
                            : _connect,
                        child: Text(
                          _isConnecting ? 'Connecting...' : 'Connect to ESP32',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isConnected ? _disconnect : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Disconnect'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoadingDevices
                                ? null
                                : _loadPairedDevices,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _isLoadingDevices ? 'Loading...' : 'Refresh',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _statusColor(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _alertChip(
                          data?.crash == true ? 'Crash detected' : 'No crash',
                          data?.crash == true,
                        ),
                        _alertChip(
                          data?.obstacleWarning == true
                              ? 'Obstacle ahead'
                              : 'Path clear',
                          data?.obstacleWarning == true,
                          activeColor: Colors.orange,
                        ),
                        _alertChip(
                          data?.coAlert == true ? 'CO alert' : 'CO normal',
                          data?.coAlert == true,
                        ),
                        _alertChip(
                          data?.dontDrive == true ? 'Do not drive' : 'Drive OK',
                          data?.dontDrive == true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Position: ${data?.position ?? '--'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              _sectionTitle('Health'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _metricCard(
                    title: 'BPM',
                    value: _formatInt(data?.bpm),
                    icon: Icons.favorite_outline,
                  ),
                  _metricCard(
                    title: 'Avg BPM',
                    value: _formatInt(data?.avgBpm),
                    icon: Icons.monitor_heart_outlined,
                  ),
                  _metricCard(
                    title: 'SpO2',
                    value: _formatInt(data?.spo2),
                    icon: Icons.bloodtype_outlined,
                  ),
                  _metricCard(
                    title: 'Force (N)',
                    value: _formatDouble(data?.force, 2),
                    icon: Icons.fitness_center_outlined,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _sectionTitle('Environment'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _metricCard(
                    title: 'Temp (°C)',
                    value: _formatDouble(data?.temperature),
                    icon: Icons.thermostat_outlined,
                  ),
                  _metricCard(
                    title: 'Humidity (%)',
                    value: _formatDouble(data?.humidity),
                    icon: Icons.water_drop_outlined,
                  ),
                  _metricCard(
                    title: 'Distance (cm)',
                    value: _formatDouble(data?.distance),
                    icon: Icons.social_distance_outlined,
                  ),
                  _metricCard(
                    title: 'CO',
                    value: _formatInt(data?.co),
                    icon: Icons.air_outlined,
                  ),
                  _metricCard(
                    title: 'Alcohol (mg/L)',
                    value: _formatDouble(data?.alcohol, 3),
                    icon: Icons.local_bar_outlined,
                    valueColor: (data?.dontDrive == true) ? _danger : null,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _sectionTitle('Motion'),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _metricCard(
                    title: 'Pitch',
                    value: _formatDouble(data?.pitch),
                    icon: Icons.screen_rotation_alt_outlined,
                  ),
                  _metricCard(
                    title: 'Roll',
                    value: _formatDouble(data?.roll),
                    icon: Icons.threesixty_outlined,
                  ),
                  _metricCard(
                    title: 'Obstacle',
                    value: data?.obstacleWarning == true ? 'YES' : 'NO',
                    icon: Icons.warning_amber_rounded,
                    valueColor: data?.obstacleWarning == true
                        ? Colors.orange
                        : null,
                  ),
                  _metricCard(
                    title: 'Crash',
                    value: data?.crash == true ? 'YES' : 'NO',
                    icon: Icons.report_problem_outlined,
                    valueColor: data?.crash == true ? _danger : null,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _sectionTitle('Debug'),
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
