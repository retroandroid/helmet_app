import 'dart:async';

import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';

class BluetoothService {
  final FlutterBluetoothClassic _bluetooth = FlutterBluetoothClassic();

  StreamSubscription<BluetoothData>? _dataSubscription;

  final StreamController<String> _rawLineController =
      StreamController<String>.broadcast();

  String _buffer = '';

  Stream<String> get rawLines => _rawLineController.stream;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      return await _bluetooth.getPairedDevices();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    try {
      final bool connected = await _bluetooth.connect(address);
      if (!connected) return false;

      await _dataSubscription?.cancel();
      _dataSubscription = _bluetooth.onDataReceived.listen(
        _onDataReceived,
        onError: (_) {},
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  void _onDataReceived(BluetoothData data) {
    final chunk = data.asString();
    _buffer += chunk;

    final parts = _buffer.split('\n');

    for (int i = 0; i < parts.length - 1; i++) {
      final line = parts[i].trim();
      if (line.isNotEmpty) {
        _rawLineController.add(line);
      }
    }

    _buffer = parts.last;
  }

  Future<bool> disconnect() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;

    try {
      return await _bluetooth.disconnect();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _dataSubscription?.cancel();
    _rawLineController.close();
  }
}
