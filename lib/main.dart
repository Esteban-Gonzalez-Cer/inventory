import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/controller.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'services/reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  try {
    final database = await AppDatabase.open();
    final controller = AppController(
      AlacenaRepository(database),
      reminders: ReminderService(),
    );
    runApp(AlacenaApp(controller: controller));
    await controller.initialize();
  } catch (error, stackTrace) {
    debugPrint('No se pudo abrir Alacena: $error\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo abrir el inventario local. Tus datos no se han eliminado.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: main,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
