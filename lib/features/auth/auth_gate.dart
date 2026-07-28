import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/supabase_service_log_repository.dart';
import '../shell/service_log_workspace.dart';
import 'login_screen.dart';
import 'organization_setup_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  Future<WorkspaceProfile?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _session = client.auth.currentSession;
    if (_session != null) _profileFuture = _fetchProfile();
    _subscription = client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _session = state.session;
        _profileFuture = _session == null ? null : _fetchProfile();
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _reloadProfile() {
    setState(() => _profileFuture = _fetchProfile());
  }

  Future<WorkspaceProfile?> _fetchProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final response = await Supabase.instance.client
        .from('profiles')
        .select('full_name, role, organizations(name)')
        .eq('user_id', user.id)
        .maybeSingle();
    if (response == null) return null;
    final organization = _firstMap(response['organizations']);
    return WorkspaceProfile(
      fullName: response['full_name'] as String? ?? user.email ?? 'Usuário',
      role: _roleLabel(response['role'] as String? ?? 'technician'),
      organizationName: organization['name'] as String? ?? 'Organização',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const LoginScreen();

    final profileFuture = _profileFuture ??= _fetchProfile();
    return FutureBuilder<WorkspaceProfile?>(
      future: profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 14),
                    Text(
                      'Não foi possível carregar o perfil.',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString(),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _reloadProfile,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return OrganizationSetupScreen(onCompleted: _reloadProfile);
        }
        return ServiceLogWorkspace(
          repository: SupabaseServiceLogRepository(),
          profile: profile,
        );
      },
    );
  }

  static Map<String, dynamic> _firstMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _firstMap(value.first);
    return <String, dynamic>{};
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Administrador';
      case 'engineer':
        return 'Engenheiro';
      case 'manager':
        return 'Gestor';
      case 'viewer':
        return 'Consulta';
      default:
        return 'Técnico';
    }
  }
}
