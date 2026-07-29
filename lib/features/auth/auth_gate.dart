import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/runtime/app_runtime.dart';
import '../../data/repositories/offline_first_service_log_repository.dart';
import '../../data/repositories/service_log_repository.dart';
import '../shell/service_log_workspace.dart';
import 'login_screen.dart';
import 'organization_setup_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.runtime});

  final AppRuntime runtime;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  Future<_WorkspaceSession?>? _profileFuture;
  String? _repositoryKey;
  ServiceLogRepository? _repository;

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
        if (_session == null) {
          _repository = null;
          _repositoryKey = null;
        }
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

  Future<_WorkspaceSession?> _fetchProfile() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    final cacheKey = 'workspace_profile:${user.id}';

    try {
      final response = await client
          .from('profiles')
          .select('organization_id, full_name, role, organizations(name)')
          .eq('user_id', user.id)
          .maybeSingle();
      if (response == null) return null;
      final organization = _firstMap(response['organizations']);
      final session = _WorkspaceSession(
        userId: user.id,
        organizationId: response['organization_id'] as String,
        profile: WorkspaceProfile(
          fullName: response['full_name'] as String? ?? user.email ?? 'Usuário',
          role: _roleLabel(response['role'] as String? ?? 'technician'),
          organizationName: organization['name'] as String? ?? 'Organização',
        ),
      );
      await widget.runtime.localStore.writeMetadata(
        'auth-cache',
        cacheKey,
        jsonEncode(session.toJson()),
      );
      return session;
    } catch (_) {
      final cached = await widget.runtime.localStore.readMetadata(
        'auth-cache',
        cacheKey,
      );
      if (cached == null || cached.isEmpty) rethrow;
      return _WorkspaceSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(cached) as Map),
      );
    }
  }

  ServiceLogRepository _repositoryFor(_WorkspaceSession session) {
    final key = '${session.organizationId}:${session.userId}';
    if (_repository != null && _repositoryKey == key) return _repository!;
    _repositoryKey = key;
    _repository = OfflineFirstServiceLogRepository.supabase(
      store: widget.runtime.localStore,
      namespace: 'supabase:$key',
    );
    return _repository!;
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const LoginScreen();

    final profileFuture = _profileFuture ??= _fetchProfile();
    return FutureBuilder<_WorkspaceSession?>(
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
                    const Text(
                      'Conecte-se uma vez para armazenar o perfil neste dispositivo. Depois disso, o aplicativo poderá abrir offline.',
                      textAlign: TextAlign.center,
                    ),
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
        final session = snapshot.data;
        if (session == null) {
          return OrganizationSetupScreen(onCompleted: _reloadProfile);
        }
        return ServiceLogWorkspace(
          repository: _repositoryFor(session),
          profile: session.profile,
          storageLabel: '${widget.runtime.localStore.storageLabel} + Supabase',
          startupWarning: widget.runtime.storageWarning,
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

class _WorkspaceSession {
  const _WorkspaceSession({
    required this.userId,
    required this.organizationId,
    required this.profile,
  });

  final String userId;
  final String organizationId;
  final WorkspaceProfile profile;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'organizationId': organizationId,
    'fullName': profile.fullName,
    'role': profile.role,
    'organizationName': profile.organizationName,
  };

  factory _WorkspaceSession.fromJson(Map<String, dynamic> json) {
    return _WorkspaceSession(
      userId: json['userId'] as String,
      organizationId: json['organizationId'] as String,
      profile: WorkspaceProfile(
        fullName: json['fullName'] as String? ?? 'Usuário',
        role: json['role'] as String? ?? 'Técnico',
        organizationName: json['organizationName'] as String? ?? 'Organização',
      ),
    );
  }
}
