import 'package:flutter/material.dart';

import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class ConnectionCard extends StatelessWidget {
  final List<BluetoothDevice> pairedDevices;
  final String? selectedDeviceAddress;
  final bool isConnected;
  final bool isConnecting;
  final bool isLoadingDevices;
  final ValueChanged<String?> onDeviceChanged;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRefresh;
  final Color accentColor;
  final Color cardColor;

  const ConnectionCard({
    super.key,
    required this.pairedDevices,
    required this.selectedDeviceAddress,
    required this.isConnected,
    required this.isConnecting,
    required this.isLoadingDevices,
    required this.onDeviceChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefresh,
    required this.accentColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
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
            value: selectedDeviceAddress,
            isExpanded: true,
            items: pairedDevices.map((device) {
              final label = device.name.isNotEmpty
                  ? '${device.name} (${device.address})'
                  : device.address;
              return DropdownMenuItem<String>(
                value: device.address,
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: isConnected ? null : onDeviceChanged,
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
                backgroundColor: accentColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (isConnecting || isLoadingDevices || isConnected)
                  ? null
                  : onConnect,
              child: Text(
                isConnecting ? 'Connecting...' : 'Connect to ESP32',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isConnected ? onDisconnect : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Disconnect'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoadingDevices ? null : onRefresh,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(isLoadingDevices ? 'Loading...' : 'Refresh'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
