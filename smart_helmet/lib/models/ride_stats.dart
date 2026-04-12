class RideStats {
  int sampleCount = 0;

  double speedSum = 0;
  double? maxSpeedKmh;

  int bpmCount = 0;
  int bpmSum = 0;
  int? maxBpm;

  int? minSpo2;

  int? maxCo;
  double? maxAlcohol;

  double temperatureSum = 0;
  int temperatureCount = 0;

  double humiditySum = 0;
  int humidityCount = 0;

  double? maxForce;
  double? minDistance;

  bool hadCrash = false;
  bool hadObstacleAlert = false;
  bool hadCoAlert = false;
  bool hadDontDriveAlert = false;

  void reset() {
    sampleCount = 0;

    speedSum = 0;
    maxSpeedKmh = null;

    bpmCount = 0;
    bpmSum = 0;
    maxBpm = null;

    minSpo2 = null;

    maxCo = null;
    maxAlcohol = null;

    temperatureSum = 0;
    temperatureCount = 0;

    humiditySum = 0;
    humidityCount = 0;

    maxForce = null;
    minDistance = null;

    hadCrash = false;
    hadObstacleAlert = false;
    hadCoAlert = false;
    hadDontDriveAlert = false;
  }

  void addSample({
    double? speedKmh,
    int? bpm,
    int? spo2,
    int? co,
    double? alcohol,
    double? temperature,
    double? humidity,
    double? force,
    double? distance,
    bool? crash,
    bool? obstacle,
    bool? coAlert,
    bool? dontDrive,
  }) {
    sampleCount++;

    if (speedKmh != null) {
      speedSum += speedKmh;
      if (maxSpeedKmh == null || speedKmh > maxSpeedKmh!) {
        maxSpeedKmh = speedKmh;
      }
    }

    if (bpm != null && bpm > 0) {
      bpmCount++;
      bpmSum += bpm;
      if (maxBpm == null || bpm > maxBpm!) {
        maxBpm = bpm;
      }
    }

    if (spo2 != null && spo2 > 0) {
      if (minSpo2 == null || spo2 < minSpo2!) {
        minSpo2 = spo2;
      }
    }

    if (co != null) {
      if (maxCo == null || co > maxCo!) {
        maxCo = co;
      }
    }

    if (alcohol != null) {
      if (maxAlcohol == null || alcohol > maxAlcohol!) {
        maxAlcohol = alcohol;
      }
    }

    if (temperature != null) {
      temperatureSum += temperature;
      temperatureCount++;
    }

    if (humidity != null) {
      humiditySum += humidity;
      humidityCount++;
    }

    if (force != null) {
      if (maxForce == null || force > maxForce!) {
        maxForce = force;
      }
    }

    if (distance != null && distance > 0) {
      if (minDistance == null || distance < minDistance!) {
        minDistance = distance;
      }
    }

    if (crash == true) hadCrash = true;
    if (obstacle == true) hadObstacleAlert = true;
    if (coAlert == true) hadCoAlert = true;
    if (dontDrive == true) hadDontDriveAlert = true;
  }

  double? get avgSpeedKmh {
    if (sampleCount == 0) return null;
    return speedSum / sampleCount;
  }

  int? get avgBpm {
    if (bpmCount == 0) return null;
    return (bpmSum / bpmCount).round();
  }

  double? get avgTemperature {
    if (temperatureCount == 0) return null;
    return temperatureSum / temperatureCount;
  }

  double? get avgHumidity {
    if (humidityCount == 0) return null;
    return humiditySum / humidityCount;
  }
}
