import 'package:supabase_flutter/supabase_flutter.dart';

class EmergencyProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final response = await _supabase
        .from('emergency_profiles')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> upsertProfile({
    String? bloodType,
    String? medications,
    String? allergies,
    String? insuranceInfo,
    String? medicalNotes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final existing = await _supabase
        .from('emergency_profiles')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();

    final payload = {
      'user_id': user.id,
      'blood_type': bloodType,
      'medications': medications,
      'allergies': allergies,
      'insurance_info': insuranceInfo,
      'medical_notes': medicalNotes,
    };

    if (existing == null) {
      await _supabase.from('emergency_profiles').insert(payload);
    } else {
      await _supabase
          .from('emergency_profiles')
          .update(payload)
          .eq('id', existing['id']);
    }
  }
}
