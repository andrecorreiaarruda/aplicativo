import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/runtime/app_runtime.dart';
import 'core/storage/memory_snapshot_store.dart';
import 'core/storage/sqlite_snapshot_store.dart';
import 'core/theme/orion_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('ORION UNCAUGHT ERROR: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  ErrorWidget.builder = (details) => _OrionErrorWidget(details: details);

  await runZonedGuarded(
    () async {
      if (AppConfig.isSupabaseConfigured) {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabasePublishableKey,
        );
      }

      final runtime = await _createRuntime();
      runApp(ServiceLogApp(runtime: runtime));
    },
    (error, stack) {
      debugPrint('ORION ZONE ERROR: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

Future<AppRuntime> _createRuntime() async {
  try {
    final store = await SqliteSnapshotStore.open();
    return AppRuntime(localStore: store);
  } catch (error, stack) {
    debugPrint('ORION LOCAL DATABASE ERROR: $error');
    debugPrintStack(stackTrace: stack);
    return AppRuntime(
      localStore: MemorySnapshotStore(),
      storageWarning:
          'O banco local SQLite não pôde ser aberto. Nesta execução, os dados '
          'ficarão somente na memória e serão perdidos ao fechar o aplicativo.',
    );
  }
}

class _OrionErrorWidget extends StatelessWidget {
  const _OrionErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final message = kReleaseMode
        ? 'Não foi possível carregar esta área.'
        : details.exceptionAsString();

    return ColoredBox(
      color: OrionColors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: OrionColors.danger,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Falha ao renderizar a interface',
                        style: TextStyle(
                          color: OrionColors.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
