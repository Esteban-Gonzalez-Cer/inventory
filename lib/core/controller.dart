import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import '../services/reminders.dart';
import 'format.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, {this.reminders});
  final AlacenaRepository repository;
  final ReminderService? reminders;
  Workspace? workspace;
  int? selectedBranchId;
  bool busy = false;
  String? loadError, reminderError, pendingNotificationDate;
  int _revision = 0;
  bool _disposed = false;
  DateTime get now => repository.clock();
  int get cartCount => workspace == null
      ? 0
      : workspace!.scoped(workspace!.cart, selectedBranchId).length;
  Branch? get selectedBranch =>
      workspace?.branches.where((b) => b.id == selectedBranchId).firstOrNull;

  Future<void> initialize() async {
    await refresh();
    try {
      await reminders?.initialize();
      reminders?.onOpen = (date) {
        pendingNotificationDate = date;
        _notify();
      };
      pendingNotificationDate = reminders?.initialDate;
      if (workspace != null) await reminders?.synchronize(workspace!);
    } catch (e) {
      reminderError = 'Los recordatorios necesitan atención: ${humanError(e)}';
    }
    _notify();
  }

  void selectBranch(int? id) {
    if (busy) return;
    if (id != null && !(workspace?.branches.any((b) => b.id == id) ?? false)) {
      return;
    }
    selectedBranchId = id;
    _notify();
  }

  void acknowledgeNotification() {
    pendingNotificationDate = null;
  }

  Future<void> refresh() async {
    final revision = ++_revision;
    try {
      final next = await repository.load();
      if (revision != _revision || _disposed) return;
      workspace = next;
      loadError = null;
      if (selectedBranchId != null &&
          !next.branches.any((b) => b.id == selectedBranchId)) {
        selectedBranchId = null;
      }
      _notify();
    } catch (e) {
      if (revision == _revision) {
        loadError = humanError(e);
        _notify();
      }
    }
  }

  Future<T> mutate<T>(Future<T> Function() operation) async {
    if (busy) {
      throw const AppFailure('Espera a que termine la operación actual.');
    }
    busy = true;
    _notify();
    try {
      final result = await operation();
      await refresh();
      if (workspace != null) unawaited(_synchronize());
      return result;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _synchronize() async {
    try {
      await reminders?.synchronize(workspace!);
      reminderError = null;
    } catch (e) {
      reminderError =
          'No se pudieron actualizar los recordatorios: ${humanError(e)}';
    }
    _notify();
  }

  Future<void> resume() async {
    await refresh();
    if (workspace != null) await _synchronize();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    reminders?.onOpen = null;
    super.dispose();
  }
}

String humanError(Object error) {
  if (error is AppFailure) return error.message;
  if (error is DatabaseException) {
    if (error.isUniqueConstraintError()) {
      return 'Ya existe un registro con esos datos.';
    }
    if (error.toString().contains('FOREIGN KEY')) {
      return 'No se puede eliminar: este registro tiene artículos, pedidos o historial asociados.';
    }
    if (error.toString().contains('CHECK constraint')) {
      return 'Revisa los datos y las cantidades del formulario.';
    }
    return 'No se pudo guardar. Tus datos anteriores se conservaron.';
  }
  return 'No se pudo completar la operación. Inténtalo de nuevo.';
}
