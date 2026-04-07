#include <Wire.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"
#include <DHT.h>
#include "BluetoothSerial.h"

MAX30105 particleSensor;
BluetoothSerial SerialBT;

// ======================================================
// Bluetooth Serial
// ======================================================
#define BT_DEVICE_NAME "ESP32_HELMET"

// ======================================================
// HC-SR04 Ultrasonic Sensor
// ======================================================
#define HCSR04_TRIG_PIN 25
#define HCSR04_ECHO_PIN 26

float obstacleDistanceCm = -1.0f;
bool obstacleWarning = false;

unsigned long lastHCSR04Read = 0;
const unsigned long HCSR04_INTERVAL_MS = 120;
const float OBSTACLE_THRESHOLD_CM = 100.0f; 

// ======================================================
// Active buzzer
// ======================================================
#define BUZZER_PIN 33

bool buzzerState = false;
unsigned long lastBuzzerToggle = 0;
const unsigned long BUZZER_BEEP_INTERVAL_MS = 100;

// ======================================================
// Real-time obstacle task
// ======================================================
TaskHandle_t obstacleTaskHandle = NULL;

// ======================================================
// DHT11
// ======================================================
#define DHTPIN 4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

float temperatureC = 0.0f;
float humidityPct = 0.0f;
bool dhtValid = false;

unsigned long lastDHTRead = 0;
const unsigned long DHT_INTERVAL_MS = 2000;

// ======================================================
// RP-C7.6-LT Force Sensor
// ======================================================
#define FORCE_PIN 35

const float FORCE_FIXED_RESISTOR_OHM = 10000.0f;
const float FORCE_SUPPLY_VOLTAGE = 3.3f;
const float FORCE_MODEL_A = 336.04f;
const float FORCE_MODEL_B = -0.712f;
const float FORCE_MIN_G = 30.0f;
const float FORCE_MAX_G = 1500.0f;

int forceRaw = 0;
int forceMilliVolts = 0;
float forceSensorOhms = 0.0f;
float forceGrams = 0.0f;
float forceNewtons = 0.0f;
float forceNewtonsFiltered = 0.0f;
bool forceValid = false;

unsigned long lastForceRead = 0;
const unsigned long FORCE_INTERVAL_MS = 100;

// ======================================================
// MQ-7
// ======================================================
#define MQ7_AO_PIN 34
#define MQ7_DO_PIN 27

const float MQ7_DIVIDER_RATIO = 3.0f;

int mq7Raw = 0;
int mq7AdcMilliVolts = 0;
float mq7ModuleVolts = 0.0f;
int mq7RelativePct = 0;
int mq7DigitalState = 0;
bool mq7Alert = false;

unsigned long lastMQ7Read = 0;
const unsigned long MQ7_INTERVAL_MS = 500;

// ======================================================
// MQ-3 Alcohol Sensor
// ======================================================
#define MQ3_AO_PIN 32

const float MQ3_DIVIDER_RATIO = 3.0f;
const float MQ3_MODULE_VCC = 5.0f;
const float MQ3_RL_OHM = 200000.0f;
const float MQ3_CLEAN_AIR_FACTOR = 5.0f;
const float MQ3_CURVE_X_MGL = 0.4f;
const float MQ3_CURVE_SLOPE = -0.68f;
const float MQ3_DRIVE_LIMIT_MGL = 0.25f;
const unsigned long MQ3_INTERVAL_MS = 500;
const unsigned long MQ3_WARMUP_MS = 60000;

int mq3Raw = 0;
int mq3AdcMilliVolts = 0;
float mq3ModuleVolts = 0.0f;
float mq3SensorRs = 0.0f;
float mq3Ro = 0.0f;
float mq3EstimatedMgL = 0.0f;
float mq3EstimatedMgLFiltered = 0.0f;
float mq3PercentOfLimit = 0.0f;
bool mq3Valid = false;
bool dontDriveAlert = false;

unsigned long lastMQ3Read = 0;

// ======================================================
// MPU6050
// ======================================================
#define MPU6050_ADDR 0x68

float accX = 0, accY = 0, accZ = 0;
float gyroX = 0, gyroY = 0, gyroZ = 0;

float neutralPitch = 0.0f;
float neutralRoll = 0.0f;

float pitchDeg = 0.0f;
float rollDeg = 0.0f;
float pitchDegFiltered = 0.0f;
float rollDegFiltered = 0.0f;

const char* helmetPosition = "UPRIGHT";

int16_t axPrev = 0, ayPrev = 0, azPrev = 0;
bool firstCrashReading = true;
bool crashDetected = false;
const int MOTION_THRESHOLD = 1000;

// ======================================================
// Heart rate / SpO2
// ======================================================
#define BUFFER_SIZE 25
uint32_t irBuffer[BUFFER_SIZE];
uint32_t redBuffer[BUFFER_SIZE];

int32_t spo2 = 0;
int8_t validSPO2 = 0;
int32_t heartRateFromAlgo = 0;
int8_t validHeartRateFromAlgo = 0;

int currentBPM = 0;
int beatAvg = 0;

const byte BPM_HISTORY_SIZE = 6;
int bpmHistory[BPM_HISTORY_SIZE];
byte bpmHistorySpot = 0;
byte bpmHistoryCount = 0;

const byte SPO2_AVG_SIZE = 5;
int spo2History[SPO2_AVG_SIZE];
byte spo2Spot = 0;
byte spo2Count = 0;
int spo2Avg = 0;

unsigned long lastSpO2Calc = 0;
const unsigned long SPO2_INTERVAL_MS = 1000;

// ======================================================
// General timing
// ======================================================
unsigned long lastStatusPrint = 0;
const unsigned long STATUS_PRINT_INTERVAL_MS = 200;

unsigned long bootMillis = 0;
bool max30102Available = false;

// ======================================================
// Debug helper
// ======================================================
void printlnDebug(const String &msg) {
  Serial.println(msg);
}

// ======================================================
// Bluetooth Serial helpers
// ======================================================
void initBluetoothSerial() {
  if (!SerialBT.begin(BT_DEVICE_NAME)) {
    printlnDebug("Bluetooth Serial failed to start.");
  } else {
    printlnDebug("Bluetooth Serial started: ESP32_JSON_Bridge");
  }
}

void sendTelemetryJSON() {
  String json = "{";

  json += "\"bpm\":";
  json += currentBPM;

  json += ",\"avgBpm\":";
  if (bpmHistoryCount > 0) json += String(beatAvg);
  else json += "null";

  json += ",\"spo2\":";
  if (spo2Count > 0) json += String(spo2Avg);
  else json += "null";

  json += ",\"t\":";
  if (dhtValid) json += String(temperatureC, 1);
  else json += "null";

  json += ",\"h\":";
  if (dhtValid) json += String(humidityPct, 1);
  else json += "null";

  json += ",\"d\":";
  if (obstacleDistanceCm > 0) json += String(obstacleDistanceCm, 1);
  else json += "null";

  json += ",\"obs\":";
  json += String(obstacleWarning ? "true" : "false");

  json += ",\"co\":";
  json += mq7RelativePct;

  json += ",\"coa\":";
  json += String(mq7Alert ? "true" : "false");

  json += ",\"alc\":";
  if (millis() - bootMillis < MQ3_WARMUP_MS || !mq3Valid) json += "null";
  else json += String(mq3EstimatedMgLFiltered, 3);

  json += ",\"dd\":";
  json += String(dontDriveAlert ? "true" : "false");

  json += ",\"p\":";
  json += String(pitchDegFiltered, 1);

  json += ",\"r\":";
  json += String(rollDegFiltered, 1);

  json += ",\"pos\":\"";
  json += helmetPosition;
  json += "\"";

  json += ",\"cr\":";
  json += String(crashDetected ? "true" : "false");

  json += ",\"f\":";
  json += String(forceNewtonsFiltered, 2);

  json += "}";

  Serial.println(json);
  SerialBT.println(json);
}

// ======================================================
// Shared ADC helpers
// ======================================================
int readAnalogAverage(int pin, int samples) {
  long total = 0;
  for (int i = 0; i < samples; i++) total += analogRead(pin);
  return total / samples;
}

int readMilliVoltsAverage(int pin, int samples) {
  long total = 0;
  for (int i = 0; i < samples; i++) total += analogReadMilliVolts(pin);
  return total / samples;
}

// ======================================================
// HC-SR04 helpers
// ======================================================
float readHCSR04DistanceCm() {
  digitalWrite(HCSR04_TRIG_PIN, LOW);
  delayMicroseconds(3);

  digitalWrite(HCSR04_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(HCSR04_TRIG_PIN, LOW);

  unsigned long duration = pulseIn(HCSR04_ECHO_PIN, HIGH, 25000);

  if (duration == 0) return -1.0f;

  float distance = duration * 0.0343f / 2.0f;

  if (!isfinite(distance) || distance <= 0.0f || distance > 400.0f) return -1.0f;
  return distance;
}

void updateHCSR04() {
  if (millis() - lastHCSR04Read < HCSR04_INTERVAL_MS) return;
  lastHCSR04Read = millis();

  float d = readHCSR04DistanceCm();

  if (d < 0.0f) {
    obstacleDistanceCm = -1.0f;
    obstacleWarning = false;
    return;
  }

  if (obstacleDistanceCm < 0.0f) obstacleDistanceCm = d;
  else obstacleDistanceCm = 0.7f * obstacleDistanceCm + 0.3f * d;

  obstacleWarning = (obstacleDistanceCm <= OBSTACLE_THRESHOLD_CM);
}

// ======================================================
// Buzzer helpers
// ======================================================
void updateBuzzer() {
  if (obstacleWarning) {
    if (millis() - lastBuzzerToggle >= BUZZER_BEEP_INTERVAL_MS) {
      lastBuzzerToggle = millis();
      buzzerState = !buzzerState;
      digitalWrite(BUZZER_PIN, buzzerState ? HIGH : LOW);
    }
  } else {
    buzzerState = false;
    digitalWrite(BUZZER_PIN, LOW);
  }
}

// ======================================================
// Real-time obstacle task
// ======================================================
void obstacleTask(void *parameter) {
  for (;;) {
    updateHCSR04();
    updateBuzzer();
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

// ======================================================
// DHT11 helpers
// ======================================================
void updateDHT11() {
  if (millis() - lastDHTRead < DHT_INTERVAL_MS) return;
  lastDHTRead = millis();

  float h = dht.readHumidity();
  float t = dht.readTemperature();

  if (!isnan(h) && !isnan(t)) {
    humidityPct = h;
    temperatureC = t;
    dhtValid = true;
  } else {
    dhtValid = false;
  }
}

// ======================================================
// Force sensor helpers
// ======================================================
void updateForceSensor() {
  if (millis() - lastForceRead < FORCE_INTERVAL_MS) return;
  lastForceRead = millis();

  forceRaw = readAnalogAverage(FORCE_PIN, 12);
  forceMilliVolts = readMilliVoltsAverage(FORCE_PIN, 12);

  float vOut = forceMilliVolts / 1000.0f;

  if (vOut < 0.01f || vOut >= (FORCE_SUPPLY_VOLTAGE - 0.01f)) {
    forceSensorOhms = 0.0f;
    forceGrams = 0.0f;
    forceNewtons = 0.0f;
    forceNewtonsFiltered = 0.0f;
    forceValid = false;
    return;
  }

  forceSensorOhms = FORCE_FIXED_RESISTOR_OHM * (FORCE_SUPPLY_VOLTAGE - vOut) / vOut;

  if (!isfinite(forceSensorOhms) || forceSensorOhms <= 0.0f) {
    forceSensorOhms = 0.0f;
    forceGrams = 0.0f;
    forceNewtons = 0.0f;
    forceNewtonsFiltered = 0.0f;
    forceValid = false;
    return;
  }

  float resistanceKOhm = forceSensorOhms / 1000.0f;
  float estimatedGrams = pow(resistanceKOhm / FORCE_MODEL_A, 1.0f / FORCE_MODEL_B);

  if (!isfinite(estimatedGrams) || estimatedGrams < FORCE_MIN_G) {
    forceGrams = 0.0f;
    forceNewtons = 0.0f;
    forceNewtonsFiltered = 0.0f;
    forceValid = false;
    return;
  }

  if (estimatedGrams > FORCE_MAX_G) estimatedGrams = FORCE_MAX_G;

  forceGrams = estimatedGrams;
  forceNewtons = forceGrams * 0.00980665f;
  forceNewtonsFiltered = 0.75f * forceNewtonsFiltered + 0.25f * forceNewtons;

  if (forceNewtonsFiltered < 0.03f) forceNewtonsFiltered = 0.0f;

  forceValid = true;
}

// ======================================================
// MQ-7 helpers
// ======================================================
void updateMQ7() {
  if (millis() - lastMQ7Read < MQ7_INTERVAL_MS) return;
  lastMQ7Read = millis();

  mq7Raw = readAnalogAverage(MQ7_AO_PIN, 8);
  mq7AdcMilliVolts = readMilliVoltsAverage(MQ7_AO_PIN, 8);

  mq7ModuleVolts = (mq7AdcMilliVolts / 1000.0f) * MQ7_DIVIDER_RATIO;
  mq7RelativePct = map(mq7Raw, 0, 4095, 0, 100);
  mq7RelativePct = constrain(mq7RelativePct, 0, 100);

  mq7DigitalState = digitalRead(MQ7_DO_PIN);
  mq7Alert = (mq7DigitalState == HIGH);
}

// ======================================================
// MQ-3 helpers
// ======================================================
float estimateAlcoholMgLFromRsRo(float rsRo) {
  if (!isfinite(rsRo) || rsRo <= 0.0f) return 0.0f;

  float mgL = MQ3_CURVE_X_MGL * pow(rsRo, 1.0f / MQ3_CURVE_SLOPE);

  if (!isfinite(mgL) || mgL < 0.0f) mgL = 0.0f;
  if (mgL > 10.0f) mgL = 10.0f;

  return mgL;
}

void invalidateMQ3() {
  mq3Valid = false;
  mq3EstimatedMgL = 0.0f;
  mq3EstimatedMgLFiltered = 0.0f;
  mq3PercentOfLimit = 0.0f;
  dontDriveAlert = false;
}

void updateMQ3() {
  if (millis() - lastMQ3Read < MQ3_INTERVAL_MS) return;
  lastMQ3Read = millis();

  mq3Raw = readAnalogAverage(MQ3_AO_PIN, 12);
  mq3AdcMilliVolts = readMilliVoltsAverage(MQ3_AO_PIN, 12);

  mq3ModuleVolts = (mq3AdcMilliVolts / 1000.0f) * MQ3_DIVIDER_RATIO;

  if (mq3ModuleVolts < 0.05f || mq3ModuleVolts > 4.95f) {
    invalidateMQ3();
    return;
  }

  mq3SensorRs = ((MQ3_MODULE_VCC / mq3ModuleVolts) - 1.0f) * MQ3_RL_OHM;

  if (!isfinite(mq3SensorRs) || mq3SensorRs <= 0.0f) {
    invalidateMQ3();
    return;
  }

  if (millis() - bootMillis < MQ3_WARMUP_MS) {
    invalidateMQ3();
    return;
  }

  float roCandidate = mq3SensorRs / MQ3_CLEAN_AIR_FACTOR;

  if (!isfinite(roCandidate) || roCandidate <= 0.0f) {
    invalidateMQ3();
    return;
  }

  if (mq3Ro <= 0.0f) {
    mq3Ro = roCandidate;
  } else {
    float provisionalRsRo = mq3SensorRs / mq3Ro;
    float provisionalMgL = estimateAlcoholMgLFromRsRo(provisionalRsRo);

    if (provisionalMgL < 0.08f) {
      mq3Ro = 0.98f * mq3Ro + 0.02f * roCandidate;
    }
  }

  if (!isfinite(mq3Ro) || mq3Ro <= 0.0f) {
    invalidateMQ3();
    return;
  }

  float rsRo = mq3SensorRs / mq3Ro;
  mq3EstimatedMgL = estimateAlcoholMgLFromRsRo(rsRo);

  mq3EstimatedMgLFiltered = 0.80f * mq3EstimatedMgLFiltered + 0.20f * mq3EstimatedMgL;

  if (!isfinite(mq3EstimatedMgLFiltered) || mq3EstimatedMgLFiltered < 0.0f) {
    mq3EstimatedMgLFiltered = 0.0f;
  }

  mq3PercentOfLimit = (mq3EstimatedMgLFiltered / MQ3_DRIVE_LIMIT_MGL) * 100.0f;
  if (mq3PercentOfLimit < 0.0f) mq3PercentOfLimit = 0.0f;

  dontDriveAlert = (mq3EstimatedMgLFiltered > MQ3_DRIVE_LIMIT_MGL);
  mq3Valid = true;
}

// ======================================================
// MPU6050 helpers
// ======================================================
bool mpu6050Connected() {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x75);
  if (Wire.endTransmission(false) != 0) return false;

  if (Wire.requestFrom(MPU6050_ADDR, 1, true) != 1) return false;
  byte who = Wire.read();
  return (who == 0x68);
}

void initMPU6050() {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00);
  Wire.endTransmission(true);

  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x1B);
  Wire.write(0x00);
  Wire.endTransmission(true);

  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x1C);
  Wire.write(0x00);
  Wire.endTransmission(true);

  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x1A);
  Wire.write(0x03);
  Wire.endTransmission(true);
}

bool readMPU6050() {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) return false;

  if (Wire.requestFrom(MPU6050_ADDR, 14, true) != 14) return false;

  int16_t rawAx = (Wire.read() << 8) | Wire.read();
  int16_t rawAy = (Wire.read() << 8) | Wire.read();
  int16_t rawAz = (Wire.read() << 8) | Wire.read();
  Wire.read(); Wire.read();
  int16_t rawGx = (Wire.read() << 8) | Wire.read();
  int16_t rawGy = (Wire.read() << 8) | Wire.read();
  int16_t rawGz = (Wire.read() << 8) | Wire.read();

  accX = rawAx / 16384.0f;
  accY = rawAy / 16384.0f;
  accZ = rawAz / 16384.0f;

  gyroX = rawGx / 131.0f;
  gyroY = rawGy / 131.0f;
  gyroZ = rawGz / 131.0f;

  if (!isfinite(accX) || !isfinite(accY) || !isfinite(accZ)) return false;
  if (!isfinite(gyroX) || !isfinite(gyroY) || !isfinite(gyroZ)) return false;

  return true;
}

float calcBodyPitchDeg() {
  return atan2(accY, accZ) * 180.0f / PI;
}

float calcBodyRollDeg() {
  return atan2(-accX, sqrt(accY * accY + accZ * accZ)) * 180.0f / PI;
}

void calibrateUprightReference() {
  float sumPitch = 0.0f;
  float sumRoll = 0.0f;
  int validCount = 0;

  for (int i = 0; i < 250; i++) {
    if (readMPU6050()) {
      float mag = sqrt(accX * accX + accY * accY + accZ * accZ);

      if (isfinite(mag) && mag > 0.75f && mag < 1.25f) {
        float p = calcBodyPitchDeg();
        float r = calcBodyRollDeg();

        if (isfinite(p) && isfinite(r)) {
          sumPitch += p;
          sumRoll += r;
          validCount++;
        }
      }
    }
    delay(8);
  }

  if (validCount > 0) {
    neutralPitch = sumPitch / validCount;
    neutralRoll = sumRoll / validCount;
  } else {
    neutralPitch = 0.0f;
    neutralRoll = 0.0f;
  }

  pitchDeg = 0.0f;
  rollDeg = 0.0f;
  pitchDegFiltered = 0.0f;
  rollDegFiltered = 0.0f;

  crashDetected = false;
  firstCrashReading = true;
  helmetPosition = "UPRIGHT";
}

void updateMPU6050() {
  if (!readMPU6050()) return;

  int16_t rawAx = (int16_t)(accX * 16384.0f);
  int16_t rawAy = (int16_t)(accY * 16384.0f);
  int16_t rawAz = (int16_t)(accZ * 16384.0f);

  if (firstCrashReading) {
    axPrev = rawAx;
    ayPrev = rawAy;
    azPrev = rawAz;
    firstCrashReading = false;
  }

  int16_t dx = abs(rawAx - axPrev);
  int16_t dy = abs(rawAy - ayPrev);
  int16_t dz = abs(rawAz - azPrev);

  axPrev = rawAx;
  ayPrev = rawAy;
  azPrev = rawAz;

  crashDetected = (dx > MOTION_THRESHOLD || dy > MOTION_THRESHOLD || dz > (MOTION_THRESHOLD * 2));

  float rawPitch = calcBodyPitchDeg() - neutralPitch;
  float rawRoll = calcBodyRollDeg() - neutralRoll;

  if (!isfinite(rawPitch) || !isfinite(rawRoll)) return;

  pitchDeg = rawPitch;
  rollDeg = rawRoll;

  pitchDegFiltered = 0.70f * pitchDegFiltered + 0.30f * pitchDeg;
  rollDegFiltered  = 0.70f * rollDegFiltered  + 0.30f * rollDeg;

  if (!isfinite(pitchDegFiltered)) pitchDegFiltered = 0.0f;
  if (!isfinite(rollDegFiltered))  rollDegFiltered = 0.0f;

  float absPitch = fabs(pitchDegFiltered);
  float absRoll  = fabs(rollDegFiltered);

  if (crashDetected) {
    helmetPosition = "CRASH";
  } else if (absPitch >= 40.0f || absRoll >= 40.0f) {
    helmetPosition = "FALL";
  } else if (absPitch >= 15.0f || absRoll >= 15.0f) {
    helmetPosition = "INCLINED";
  } else {
    helmetPosition = "UPRIGHT";
  }
}

// ======================================================
// MAX30102 helpers
// ======================================================
void initMAX30102() {
  byte ledBrightness = 60;
  byte sampleAverage = 4;
  byte ledMode = 2;
  byte sampleRate = 100;
  int pulseWidth = 411;
  int adcRange = 4096;

  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
}

bool readMAX30102Block(int32_t &heartRate, int8_t &validHeartRate, int32_t &spo2Value, int8_t &validSpO2Value) {
  for (byte i = 0; i < BUFFER_SIZE; i++) {
    unsigned long startWait = millis();

    while (particleSensor.available() == false) {
      particleSensor.check();
      if (millis() - startWait > 1000) return false;
    }

    redBuffer[i] = particleSensor.getRed();
    irBuffer[i] = particleSensor.getIR();
    particleSensor.nextSample();
  }

  maxim_heart_rate_and_oxygen_saturation(
    irBuffer,
    BUFFER_SIZE,
    redBuffer,
    &spo2Value,
    &validSpO2Value,
    &heartRate,
    &validHeartRate
  );

  return true;
}

// ======================================================
// Setup
// ======================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  bootMillis = millis();

  Wire.begin(21, 22);

  initBluetoothSerial();

  pinMode(HCSR04_TRIG_PIN, OUTPUT);
  pinMode(HCSR04_ECHO_PIN, INPUT);
  digitalWrite(HCSR04_TRIG_PIN, LOW);

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  dht.begin();

  pinMode(MQ7_DO_PIN, INPUT);

  analogReadResolution(12);
  analogSetPinAttenuation(MQ7_AO_PIN, ADC_11db);
  analogSetPinAttenuation(MQ3_AO_PIN, ADC_11db);
  analogSetPinAttenuation(FORCE_PIN, ADC_11db);

  printlnDebug("Initializing MPU6050...");

  if (!mpu6050Connected()) {
    printlnDebug("MPU6050 not found. Check wiring.");
    while (1);
  }

  initMPU6050();

  printlnDebug("Stand upright and keep still for calibration...");
  delay(1200);
  calibrateUprightReference();

  printlnDebug("Initializing MAX30102...");

  if (!particleSensor.begin(Wire)) {
    printlnDebug("MAX30102 was not found. Check wiring.");
    max30102Available = false;
  } else {
    printlnDebug("MAX30102 found.");
    initMAX30102();
    max30102Available = true;
  }

  xTaskCreatePinnedToCore(
    obstacleTask,
    "ObstacleTask",
    4096,
    NULL,
    2,
    &obstacleTaskHandle,
    0
  );

  printlnDebug("System ready.");
  printlnDebug("Bluetooth serial ready.");
}

// ======================================================
// Loop
// ======================================================
void loop() {
  updateMPU6050();
  updateDHT11();
  updateMQ7();
  updateMQ3();
  updateForceSensor();

  if (max30102Available && millis() - lastSpO2Calc >= SPO2_INTERVAL_MS) {
    lastSpO2Calc = millis();

    bool ok = readMAX30102Block(
      heartRateFromAlgo,
      validHeartRateFromAlgo,
      spo2,
      validSPO2
    );

    if (ok) {
      if (validHeartRateFromAlgo && heartRateFromAlgo > 0 && heartRateFromAlgo < 220) {
        currentBPM = heartRateFromAlgo;

        bpmHistory[bpmHistorySpot++] = currentBPM;
        bpmHistorySpot %= BPM_HISTORY_SIZE;

        if (bpmHistoryCount < BPM_HISTORY_SIZE) bpmHistoryCount++;

        int sum = 0;
        for (byte i = 0; i < bpmHistoryCount; i++) sum += bpmHistory[i];
        beatAvg = sum / bpmHistoryCount;
      } else {
        currentBPM = 0;
      }

      if (validSPO2 && spo2 >= 70 && spo2 <= 100) {
        spo2History[spo2Spot++] = spo2;
        spo2Spot %= SPO2_AVG_SIZE;

        if (spo2Count < SPO2_AVG_SIZE) spo2Count++;

        int total = 0;
        for (byte i = 0; i < spo2Count; i++) total += spo2History[i];
        spo2Avg = total / spo2Count;
      }
    }
  }

  if (millis() - lastStatusPrint >= STATUS_PRINT_INTERVAL_MS) {
    lastStatusPrint = millis();
    sendTelemetryJSON();
  }
}