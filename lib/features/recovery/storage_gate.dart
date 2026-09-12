import 'package:flutter/material.dart';

import '../../core/runtime/app_runtime.dart';

/// No workspace (and no writable memory fallback) exists until SQLite opens.
class StorageGate extends StatefulWidget {
  const StorageGate({
    super.key,
    required this.openRuntime,
    required this.builder,
  });

  final Future<AppRuntime> Function() openRuntime;
  final Widget Function(AppRuntime) builder;

  @override
  State<StorageGate> createState() => _StorageGateState();
}

class _StorageGateState extends State<StorageGate> {
  late Future<AppRuntime> _opening;

  @override
  void initState() {
    super.initState();
    _opening = Future.sync(widget.openRuntime);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppRuntime>(
    future: _opening,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        return widget.builder(snapshot.requireData);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storage_rounded, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Armazenamento local indisponível',
                            style: TextStyle(fontSize: 22),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Para proteger seus dados, novos registros estão temporariamente bloqueados. Tente abrir o armazenamento novamente.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () => setState(() {
                              _opening = Future.sync(widget.openRuntime);
                            }),
                            child: const Text('Tentar novamente'),
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      );
    },
  );
}
