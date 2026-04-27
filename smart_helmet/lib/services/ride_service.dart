import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ride_stats.dart';
import 'local_ride_persistence_service.dart';

class RideService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalRidePersistenceService _localPersistence =
      LocalRidePersistenceService();

  Future<int> createRide({
    required DateTime startedAt,
    double? startLat,
    double? startLng,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final localRideId = await _localPersistence.createRide(
      userId: user.id,
      startedAt: startedAt,
      startLat: startLat,
      startLng: startLng,
    );

    try {
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

      await _localPersistence.setRemoteId(
        localRideId: localRideId,
        remoteRideId: response['id'] as int,
      );
    } catch (_) {
      // Keep the ride locally so it can still be completed and viewed offline.
    }

    return localRideId;
  }

  Future<void> endRide({
    required int rideId,
    required DateTime endedAt,
    double? endLat,
    double? endLng,
    required RideStats stats,
  }) async {
    await _localPersistence.endRide(
      localRideId: rideId,
      endedAt: endedAt,
      endLat: endLat,
      endLng: endLng,
      stats: stats,
    );

    final localRide = await _localPersistence.fetchRideByLocalId(rideId);
    if (localRide == null) return;

    final payload = {
      'user_id': localRide['user_id'],
      'started_at': localRide['started_at'],
      'ended_at': endedAt.toUtc().toIso8601String(),
      'start_lat': localRide['start_lat'],
      'start_lng': localRide['start_lng'],
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
    };

    final remoteRideId = localRide['remote_id'] as int?;

    try {
      if (remoteRideId != null) {
        await _supabase.from('rides').update(payload).eq('id', remoteRideId);
      } else {
        final response = await _supabase
            .from('rides')
            .insert(payload)
            .select('id')
            .single();

        await _localPersistence.setRemoteId(
          localRideId: rideId,
          remoteRideId: response['id'] as int,
        );
      }
    } catch (_) {
      // Local persistence already has the completed ride.
    }
  }

  Future<List<Map<String, dynamic>>> fetchRides() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      final response = await _supabase
          .from('rides')
          .select()
          .eq('user_id', user.id)
          .order('started_at', ascending: false);

      for (final ride in response) {
        await _localPersistence.upsertRemoteRide(
          Map<String, dynamic>.from(ride),
        );
      }
    } catch (_) {
      // Fall back to the local cache when the network is unavailable.
    }

    return _localPersistence.fetchRidesForUser(user.id);
  }
}
