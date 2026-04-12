import 'package:supabase_flutter/supabase_flutter.dart';

class EmergencyContactService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchPrimaryContact() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final response = await _supabase
        .from('emergency_contacts')
        .select()
        .eq('user_id', user.id)
        .eq('is_primary', true)
        .maybeSingle();

    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  Future<void> upsertPrimaryContact({
    required String fullName,
    required String phone,
    String? relationship,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final existing = await _supabase
        .from('emergency_contacts')
        .select('id')
        .eq('user_id', user.id)
        .eq('is_primary', true)
        .maybeSingle();

    if (existing == null) {
      await _supabase.from('emergency_contacts').insert({
        'user_id': user.id,
        'full_name': fullName,
        'phone': phone,
        'relationship': relationship,
        'is_primary': true,
      });
    } else {
      await _supabase
          .from('emergency_contacts')
          .update({
            'full_name': fullName,
            'phone': phone,
            'relationship': relationship,
          })
          .eq('id', existing['id']);
    }
  }
}
