import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ride_stats.dart';

class RideService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<int> createRide({
    required DateTime startedAt,
    double? startLat,
    double? startLng,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final response = await _supabase
        .from('rides')
        .insert({
          'user_id': user.id,
          'started_at': startedAt.toUtc().toIso8601String(),
          'start_lat': startLat,
          'start_lng': startLng,
        })
        .select('id')
        .single();

    return response['id'] as int;
  }

  Future<void> endRide({
    required int rideId,
    required DateTime endedAt,
    double? endLat,
    double? endLng,
    required RideStats stats,
  }) async {
    await _supabase
        .from('rides')
        .update({
          'ended_at': endedAt.toUtc().toIso8601String(),
          'end_lat': endLat,
          'end_lng': endLng,
          'max_speed_kmh': stats.maxSpeedKmh,
          'avg_speed_kmh': stats.avgSpeedKmh,
          'max_bpm': stats.maxBpm,
          'avg_bpm': stats.avgBpm,
          'min_spo2': stats.minSpo2,
          'max_co': stats.maxCo,
          'max_alcohol': stats.maxAlcohol,
          'avg_temperature': stats.avgTemperature,
          'avg_humidity': stats.avgHumidity,
          'max_force': stats.maxForce,
          'min_distance': stats.minDistance,
          'had_crash': stats.hadCrash,
          'had_obstacle_alert': stats.hadObstacleAlert,
          'had_co_alert': stats.hadCoAlert,
          'had_dont_drive_alert': stats.hadDontDriveAlert,
        })
        .eq('id', rideId);
  }

  Future<List<Map<String, dynamic>>> fetchRides() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final response = await _supabase
        .from('rides')
        .select()
        .eq('user_id', user.id)
        .order('started_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}
