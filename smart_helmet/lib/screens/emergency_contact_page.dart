import 'package:flutter/material.dart';

import '../services/emergency_contact_service.dart';
import '../services/emergency_profile_service.dart';

class EmergencyContactPage extends StatefulWidget {
  const EmergencyContactPage({super.key});

  @override
  State<EmergencyContactPage> createState() => _EmergencyContactPageState();
}

class _EmergencyContactPageState extends State<EmergencyContactPage> {
  final EmergencyContactService _contactService = EmergencyContactService();
  final EmergencyProfileService _profileService = EmergencyProfileService();

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();

  final TextEditingController _bloodTypeController = TextEditingController();
  final TextEditingController _medicationsController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _insuranceInfoController =
      TextEditingController();
  final TextEditingController _medicalNotesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadEmergencyData();
  }

  Future<void> _loadEmergencyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final contact = await _contactService.fetchPrimaryContact();
      final profile = await _profileService.fetchProfile();

      if (!mounted) return;

      if (contact != null) {
        _fullNameController.text = (contact['full_name'] ?? '').toString();
        _phoneController.text = (contact['phone'] ?? '').toString();
        _relationshipController.text = (contact['relationship'] ?? '')
            .toString();
      }

      if (profile != null) {
        _bloodTypeController.text = (profile['blood_type'] ?? '').toString();
        _medicationsController.text = (profile['medications'] ?? '').toString();
        _allergiesController.text = (profile['allergies'] ?? '').toString();
        _insuranceInfoController.text = (profile['insurance_info'] ?? '')
            .toString();
        _medicalNotesController.text = (profile['medical_notes'] ?? '')
            .toString();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load emergency info')),
      );
    }
  }

  Future<void> _saveEmergencyData() async {
    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final relationship = _relationshipController.text.trim();

    final bloodType = _bloodTypeController.text.trim();
    final medications = _medicationsController.text.trim();
    final allergies = _allergiesController.text.trim();
    final insuranceInfo = _insuranceInfoController.text.trim();
    final medicalNotes = _medicalNotesController.text.trim();

    if (fullName.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency contact name and phone are required'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _contactService.upsertPrimaryContact(
        fullName: fullName,
        phone: phone,
        relationship: relationship.isEmpty ? null : relationship,
      );

      await _profileService.upsertProfile(
        bloodType: bloodType.isEmpty ? null : bloodType,
        medications: medications.isEmpty ? null : medications,
        allergies: allergies.isEmpty ? null : allergies,
        insuranceInfo: insuranceInfo.isEmpty ? null : insuranceInfo,
        medicalNotes: medicalNotes.isEmpty ? null : medicalNotes,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Emergency info saved')));
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save emergency info')),
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    _bloodTypeController.dispose();
    _medicationsController.dispose();
    _allergiesController.dispose();
    _insuranceInfoController.dispose();
    _medicalNotesController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFC4C02), width: 1.5),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Info')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _sectionTitle('Emergency Contact'),
                    TextField(
                      controller: _fullNameController,
                      decoration: _inputDecoration(
                        'Full name',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        'Phone number',
                        Icons.phone_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _relationshipController,
                      decoration: _inputDecoration(
                        'Relationship',
                        Icons.group_outlined,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Rider Medical Info'),
                    TextField(
                      controller: _bloodTypeController,
                      decoration: _inputDecoration(
                        'Blood type',
                        Icons.bloodtype_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _medicationsController,
                      maxLines: 2,
                      decoration: _inputDecoration(
                        'Medications',
                        Icons.medication_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _allergiesController,
                      maxLines: 2,
                      decoration: _inputDecoration(
                        'Allergies',
                        Icons.warning_amber_rounded,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _insuranceInfoController,
                      maxLines: 2,
                      decoration: _inputDecoration(
                        'Insurance info',
                        Icons.shield_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _medicalNotesController,
                      maxLines: 3,
                      decoration: _inputDecoration(
                        'Medical notes',
                        Icons.notes_outlined,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _saveEmergencyData,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFC4C02),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          _isSaving ? 'Saving...' : 'Save emergency info',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
