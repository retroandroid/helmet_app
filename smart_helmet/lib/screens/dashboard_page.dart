import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

import '../models/helmet_data.dart';
import '../services/bluetooth_service.dart';

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

  Widget _buildValueCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(value, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _formatDouble(double? value, [int decimals = 1]) {
    if (value == null) return '--';
    return value.toStringAsFixed(decimals);
  }

  String _formatInt(int? value) {
    if (value == null) return '--';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final data = _helmetData;

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Helmet Dashboard')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed:
                        (_isConnecting || _isLoadingDevices || _isConnected)
                        ? null
                        : _connect,
                    child: Text(
                      _isConnecting ? 'Connecting...' : 'CONNECT TO ESP32',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _isConnected ? _disconnect : null,
                    child: const Text('DISCONNECT'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _isLoadingDevices ? null : _loadPairedDevices,
                    child: Text(
                      _isLoadingDevices
                          ? 'Loading devices...'
                          : 'REFRESH DEVICES',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Status: $_status',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    _buildValueCard('BPM', _formatInt(data?.bpm)),
                    _buildValueCard('Avg BPM', _formatInt(data?.avgBpm)),
                    _buildValueCard('SpO2', _formatInt(data?.spo2)),
                    _buildValueCard(
                      'Temp (°C)',
                      _formatDouble(data?.temperature),
                    ),
                    _buildValueCard(
                      'Humidity (%)',
                      _formatDouble(data?.humidity),
                    ),
                    _buildValueCard(
                      'Distance (cm)',
                      _formatDouble(data?.distance),
                    ),
                    _buildValueCard(
                      'Obstacle',
                      data?.obstacleWarning == true ? 'YES' : 'NO',
                    ),
                    _buildValueCard('CO', _formatInt(data?.co)),
                    _buildValueCard(
                      'CO Alert',
                      data?.coAlert == true ? 'YES' : 'NO',
                    ),
                    _buildValueCard(
                      'Alcohol (mg/L)',
                      _formatDouble(data?.alcohol, 3),
                    ),
                    _buildValueCard(
                      'Dont Drive',
                      data?.dontDrive == true ? 'YES' : 'NO',
                    ),
                    _buildValueCard('Pitch', _formatDouble(data?.pitch)),
                    _buildValueCard('Roll', _formatDouble(data?.roll)),
                    _buildValueCard('Position', data?.position ?? '--'),
                    _buildValueCard(
                      'Crash',
                      data?.crash == true ? 'YES' : 'NO',
                    ),
                    _buildValueCard('Force (N)', _formatDouble(data?.force, 2)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Last raw line:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: Text(
                  _lastRawLine.isEmpty ? '--' : _lastRawLine,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
