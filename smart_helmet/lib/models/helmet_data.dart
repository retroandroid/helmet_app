class HelmetData {
  final int? bpm;
  final int? avgBpm;
  final int? spo2;
  final double? temperature;
  final double? humidity;
  final double? distance;
  final bool obstacleWarning;
  final int? co;
  final bool coAlert;
  final double? alcohol;
  final bool dontDrive;
  final double? pitch;
  final double? roll;
  final String position;
  final bool crash;
  final double? force;

  HelmetData({
    required this.bpm,
    required this.avgBpm,
    required this.spo2,
    required this.temperature,
    required this.humidity,
    required this.distance,
    required this.obstacleWarning,
    required this.co,
    required this.coAlert,
    required this.alcohol,
    required this.dontDrive,
    required this.pitch,
    required this.roll,
    required this.position,
    required this.crash,
    required this.force,
  });

  factory HelmetData.fromJson(Map<String, dynamic> json) {
    return HelmetData(
      bpm: json['bpm'] as int?,
      avgBpm: json['avgBpm'] as int?,
      spo2: json['spo2'] as int?,
      temperature: (json['t'] as num?)?.toDouble(),
      humidity: (json['h'] as num?)?.toDouble(),
      distance: (json['d'] as num?)?.toDouble(),
      obstacleWarning: json['obs'] as bool? ?? false,
      co: json['co'] as int?,
      coAlert: json['coa'] as bool? ?? false,
      alcohol: (json['alc'] as num?)?.toDouble(),
      dontDrive: json['dd'] as bool? ?? false,
      pitch: (json['p'] as num?)?.toDouble(),
      roll: (json['r'] as num?)?.toDouble(),
      position: json['pos'] as String? ?? 'UNKNOWN',
      crash: json['cr'] as bool? ?? false,
      force: (json['f'] as num?)?.toDouble(),
    );
  }
}
