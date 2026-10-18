import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../domain/models.dart';

class AlacenaRepository {
  AlacenaRepository(this.db, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Database db;
  final DateTime Function() clock;
  String get timestamp => clock().toUtc().toIso8601String();

  Future<Workspace> load() => db.transaction((tx) async {
    final branches = (await tx.query(
      'Sucursal',
      orderBy: 'name',
    )).map(Branch.new).toList();
    final lots = (await tx.query(
      'Lote',
      orderBy: 'expiry_date,id',
    )).map(Lot.new).toList();
    final inventory = await tx.rawQuery(
      '''SELECT ps.*,p.name,p.unit,p.category_id,p.image_path,p.image_asset,
      c.name category_name,b.name branch_name,s.name last_supplier
      FROM ProductoSucursal ps JOIN Producto p ON p.id=ps.product_id
      JOIN Categoria c ON c.id=p.category_id JOIN Sucursal b ON b.id=ps.branch_id
      LEFT JOIN Tienda s ON s.id=ps.ultima_tienda_id ORDER BY p.name''',
    );
    final grouped = <int, List<Lot>>{};
    for (final lot in lots) {
      grouped.putIfAbsent(lot.branchProductId, () => []).add(lot);
    }
    return Workspace(
      branches: branches,
      categories: await tx.query('Categoria', orderBy: 'name'),
      suppliers: await tx.query('Tienda', orderBy: 'name'),
      products: await tx.rawQuery(
        'SELECT p.*,c.name category_name FROM Producto p JOIN Categoria c ON c.id=p.category_id ORDER BY p.name',
      ),
      items: inventory
          .map((r) => InventoryItem(r, grouped[r.integer('id')] ?? []))
          .toList(),
      cart: await tx.query('Carrito_Item', orderBy: 'branch_id,id'),
      orders: await tx.query('OrdenCompra', orderBy: 'id DESC'),
      lines: await tx.query('DetalleOrdenCompra', orderBy: 'id'),
      purchases: await tx.rawQuery(
        'SELECT h.*,l.id lot_id,l.expiry_date FROM Historial_Compras h JOIN Lote l ON l.purchase_id=h.id ORDER BY h.created_at DESC,h.id DESC',
      ),
      movements: await tx.rawQuery('''SELECT m.*,h.product_name,h.branch_name,h.supplier_name,h.order_id,h.receipt_id,h.id purchase_id,h.unit
        FROM Movimiento_Inventario m JOIN Lote l ON l.id=m.lot_id JOIN Historial_Compras h ON h.id=l.purchase_id
        ORDER BY m.created_at DESC,m.id DESC'''),
      events: await tx.rawQuery(
        'SELECT e.*,o.branch_name,o.supplier_name FROM EventoOrden e JOIN OrdenCompra o ON o.id=e.order_id ORDER BY e.created_at DESC,e.id DESC',
      ),
      reports: await tx.query('ReporteExportado', orderBy: 'generated_at DESC'),
      settings: {
        for (final r in await tx.query('Configuracion'))
          r.text('key'): r.text('value'),
      },
    );
  });

  Future<int> saveMaster(String table, DbRow values, {int? id}) async {
    if (!{'Sucursal', 'Categoria', 'Tienda', 'Producto'}.contains(table)) {
      throw const AppFailure('Registro no permitido.');
    }
    final name = values.text('name').trim();
    if (name.isEmpty || name.length > (table == 'Producto' ? 120 : 100)) {
      throw const AppFailure('Escribe un nombre válido.');
    }
    final data = {...values, 'name': name};
    if (table == 'Sucursal' &&
        (values.text('address').trim().isEmpty ||
            !values.decimal('latitude').isFinite ||
            !values.decimal('longitude').isFinite ||
            values.decimal('latitude').abs() > 90 ||
            values.decimal('longitude').abs() > 180)) {
      throw const AppFailure(
        'Revisa la dirección y las coordenadas de la tienda.',
      );
    }
    if (table == 'Producto' && values.text('unit').trim().isEmpty) {
      throw const AppFailure('La unidad es obligatoria.');
    }
    if (id == null) return db.insert(table, data);
    if (await db.update(table, data, where: 'id=?', whereArgs: [id]) != 1) {
      throw const AppFailure('El registro ya no existe.');
    }
    return id;
  }

  Future<void> deleteMaster(String table, int id) async {
    if (!{'Sucursal', 'Categoria', 'Tienda', 'Producto'}.contains(table)) {
      throw const AppFailure('Registro no permitido.');
    }
    await db.delete(table, where: 'id=?', whereArgs: [id]);
  }

  Future<int> assignProduct(
    int branchId,
    int productId, {
    int minimum = 2,
    int warningDays = 7,
    bool reminders = true,
  }) async {
    _thresholds(minimum, warningDays);
    return db.insert('ProductoSucursal', {
      'branch_id': branchId,
      'product_id': productId,
      'minimum_stock': minimum,
      'warning_days': warningDays,
      'reminders': reminders ? 1 : 0,
    });
  }

  Future<int> createProduct(DbRow values, {int? branchId}) =>
      db.transaction((tx) async {
        if (values.text('name').trim().isEmpty ||
            values.text('unit').trim().isEmpty) {
          throw const AppFailure('Completa nombre y unidad.');
        }
        final id = await tx.insert('Producto', {
          ...values,
          'name': values.text('name').trim(),
        });
        if (branchId != null) {
          await tx.insert('ProductoSucursal', {
            'branch_id': branchId,
            'product_id': id,
          });
        }
        return id;
      });

  void _thresholds(int minimum, int warning) {
    if (minimum < 0 || warning < 0 || warning > 365) {
      throw const AppFailure(
        'El mínimo no puede ser negativo y el aviso debe ser de 0 a 365 días.',
      );
    }
  }

  Future<void> configureProduct(
    int branchId,
    int branchProductId, {
    required int minimum,
    required int warningDays,
    required bool reminders,
  }) async {
    _thresholds(minimum, warningDays);
    final count = await db.update(
      'ProductoSucursal',
      {
        'minimum_stock': minimum,
        'warning_days': warningDays,
        'reminders': reminders ? 1 : 0,
      },
      where: 'id=? AND branch_id=?',
      whereArgs: [branchProductId, branchId],
    );
    if (count != 1) {
      throw const AppFailure('El artículo no pertenece a esta tienda.');
    }
  }

  Future<void> unassignProduct(int branchId, int branchProductId) async {
    await db.delete(
      'ProductoSucursal',
      where: 'id=? AND branch_id=?',
      whereArgs: [branchProductId, branchId],
    );
  }

  Future<void> setCart(
    int branchId,
    int branchProductId,
    int quantity, {
    bool add = false,
  }) => db.transaction((tx) async {
    await _item(tx, branchId, branchProductId);
    if (quantity < 0) {
      throw const AppFailure('La cantidad no puede ser negativa.');
    }
    final old = await tx.query(
      'Carrito_Item',
      where: 'branch_id=? AND branch_product_id=?',
      whereArgs: [branchId, branchProductId],
    );
    final next =
        quantity + (add && old.isNotEmpty ? old.first.integer('quantity') : 0);
    if (next > 1000000000) throw const AppFailure('Cantidad demasiado grande.');
    if (next == 0) {
      await tx.delete(
        'Carrito_Item',
        where: 'branch_id=? AND branch_product_id=?',
        whereArgs: [branchId, branchProductId],
      );
    } else if (old.isEmpty) {
      await tx.insert('Carrito_Item', {
        'branch_id': branchId,
        'branch_product_id': branchProductId,
        'quantity': next,
      });
    } else {
      await tx.update(
        'Carrito_Item',
        {'quantity': next},
        where: 'id=?',
        whereArgs: [old.first.integer('id')],
      );
    }
  });

  Future<DbRow> _item(DatabaseExecutor tx, int branchId, int id) async {
    final found = await tx.rawQuery(
      'SELECT ps.*,p.name,p.unit FROM ProductoSucursal ps JOIN Producto p ON p.id=ps.product_id WHERE ps.id=? AND ps.branch_id=?',
      [id, branchId],
    );
    if (found.isEmpty) {
      throw const AppFailure('El artículo no pertenece a esta tienda.');
    }
    return found.single;
  }

  Future<DbRow> _order(DatabaseExecutor tx, int branchId, int id) async {
    final rows = await tx.query(
      'OrdenCompra',
      where: 'id=? AND branch_id=?',
      whereArgs: [id, branchId],
    );
    if (rows.isEmpty) {
      throw const AppFailure('El pedido no pertenece a esta tienda.');
    }
    return rows.single;
  }

  Future<void> _event(
    DatabaseExecutor tx,
    int branchId,
    int orderId,
    String kind, {
    String note = '',
  }) => tx.insert('EventoOrden', {
    'branch_id': branchId,
    'order_id': orderId,
    'kind': kind,
    'note': note,
    'created_at': timestamp,
  });

  Future<int> saveDraft(
    int branchId,
    int supplierId,
    List<({int itemId, int quantity, int unitCost})> lines, {
    int? orderId,
  }) => db.transaction((tx) async {
    var draftId = orderId;
    if (lines.isEmpty) throw const AppFailure('Agrega al menos un artículo.');
    if (lines.map((l) => l.itemId).toSet().length != lines.length) {
      throw const AppFailure('El artículo está repetido.');
    }
    final branch = (await tx.query(
      'Sucursal',
      where: 'id=?',
      whereArgs: [branchId],
    )).firstOrNull;
    final supplier = (await tx.query(
      'Tienda',
      where: 'id=?',
      whereArgs: [supplierId],
    )).firstOrNull;
    if (branch == null || supplier == null) {
      throw const AppFailure('Selecciona tienda y proveedor válidos.');
    }
    final data = {
      'supplier_id': supplierId,
      'branch_name': branch.text('name'),
      'supplier_name': supplier.text('name'),
    };
    if (draftId != null) {
      if ((await _order(tx, branchId, draftId)).text('status') != 'draft') {
        throw const AppFailure('Solo puedes editar borradores.');
      }
      await tx.update(
        'OrdenCompra',
        data,
        where: 'id=? AND branch_id=?',
        whereArgs: [draftId, branchId],
      );
      await tx.delete(
        'DetalleOrdenCompra',
        where: 'order_id=? AND branch_id=?',
        whereArgs: [draftId, branchId],
      );
    } else {
      draftId = await tx.insert('OrdenCompra', {
        'branch_id': branchId,
        ...data,
        'created_at': timestamp,
      });
    }
    for (final line in lines) {
      if (line.quantity <= 0 ||
          line.quantity > 1000000000 ||
          line.unitCost < 0 ||
          line.unitCost > 99999999999) {
        throw const AppFailure('Revisa cantidades y precios.');
      }
      final item = await _item(tx, branchId, line.itemId);
      await tx.insert('DetalleOrdenCompra', {
        'order_id': draftId,
        'branch_id': branchId,
        'branch_product_id': line.itemId,
        'quantity': line.quantity,
        'unit_cost': line.unitCost,
        'product_name': item.text('name'),
        'unit': item.text('unit'),
      });
    }
    await _event(
      tx,
      branchId,
      draftId,
      (await tx.query(
            'EventoOrden',
            where: 'order_id=?',
            whereArgs: [draftId],
          )).isEmpty
          ? 'draft'
          : 'edited',
    );
    return draftId;
  });

  Future<void> submitOrder(int branchId, int orderId) => db.transaction((
    tx,
  ) async {
    final order = await _order(tx, branchId, orderId);
    if (order.text('status') != 'draft') {
      throw const AppFailure('El pedido ya fue enviado.');
    }
    final lines = await tx.query(
      'DetalleOrdenCompra',
      where: 'order_id=? AND branch_id=?',
      whereArgs: [orderId, branchId],
    );
    if (lines.isEmpty) throw const AppFailure('El pedido está vacío.');
    for (final line in lines) {
      final cart = await tx.query(
        'Carrito_Item',
        where: 'branch_id=? AND branch_product_id=?',
        whereArgs: [branchId, line.integer('branch_product_id')],
      );
      if (cart.isNotEmpty) {
        final left = cart.single.integer('quantity') - line.integer('quantity');
        if (left <= 0) {
          await tx.delete(
            'Carrito_Item',
            where: 'id=?',
            whereArgs: [cart.single.integer('id')],
          );
        } else {
          await tx.update(
            'Carrito_Item',
            {'quantity': left},
            where: 'id=?',
            whereArgs: [cart.single.integer('id')],
          );
        }
      }
    }
    await tx.update(
      'OrdenCompra',
      {'status': 'ordered'},
      where: 'id=? AND branch_id=?',
      whereArgs: [orderId, branchId],
    );
    await _event(tx, branchId, orderId, 'ordered');
  });

  Future<void> deleteDraft(int branchId, int orderId) =>
      db.transaction((tx) async {
        if ((await _order(tx, branchId, orderId)).text('status') != 'draft') {
          throw const AppFailure('Solo se pueden eliminar borradores.');
        }
        await tx.delete(
          'OrdenCompra',
          where: 'id=? AND branch_id=?',
          whereArgs: [orderId, branchId],
        );
      });

  Future<void> cancelOrder(int branchId, int orderId, String reason) =>
      db.transaction((tx) async {
        final order = await _order(tx, branchId, orderId);
        if (!{'draft', 'ordered', 'partial'}.contains(order.text('status'))) {
          throw const AppFailure('Este pedido ya está cerrado.');
        }
        if (reason.trim().isEmpty) {
          throw const AppFailure('Escribe el motivo de cancelación.');
        }
        await tx.update(
          'OrdenCompra',
          {'status': 'cancelled'},
          where: 'id=? AND branch_id=?',
          whereArgs: [orderId, branchId],
        );
        await _event(tx, branchId, orderId, 'cancelled', note: reason.trim());
      });

  Future<int> receive(
    int branchId,
    int orderId,
    String operationId,
    List<ReceiptLine> lines,
  ) => db.transaction((tx) async {
    if (operationId.isEmpty || lines.isEmpty) {
      throw const AppFailure('Agrega al menos una entrega.');
    }
    final signatures =
        lines
            .map(
              (l) =>
                  '${l.orderLineId}:${l.quantity}:${l.unitCost}:${l.expiry == null ? '' : dayKey(l.expiry!)}',
            )
            .toList()
          ..sort();
    final payload = jsonEncode(signatures);
    final previous = await tx.query(
      'Recepcion',
      where: 'operation_id=?',
      whereArgs: [operationId],
    );
    if (previous.isNotEmpty) {
      final old = previous.single;
      if (old.integer('branch_id') != branchId ||
          old.integer('order_id') != orderId ||
          old.text('payload') != payload) {
        throw const AppFailure(
          'El identificador de entrega ya se usó para otra operación.',
        );
      }
      return old.integer('id');
    }
    final order = await _order(tx, branchId, orderId);
    if (!{'ordered', 'partial'}.contains(order.text('status'))) {
      throw const AppFailure('El pedido no admite recepciones.');
    }
    final orderLines = await tx.query(
      'DetalleOrdenCompra',
      where: 'order_id=? AND branch_id=?',
      whereArgs: [orderId, branchId],
    );
    final byId = {for (final l in orderLines) l.integer('id'): l};
    final quantities = <int, int>{};
    for (final line in lines) {
      if (!byId.containsKey(line.orderLineId) ||
          line.quantity <= 0 ||
          line.unitCost < 0 ||
          line.unitCost > 99999999999) {
        throw const AppFailure(
          'Revisa los artículos, cantidades y precios de esta entrega.',
        );
      }
      quantities.update(
        line.orderLineId,
        (q) => q + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    for (final entry in quantities.entries) {
      final received = Sqflite.firstIntValue(
        await tx.rawQuery(
          'SELECT COALESCE(SUM(quantity),0) FROM Historial_Compras WHERE order_line_id=?',
          [entry.key],
        ),
      )!;
      if (received + entry.value > byId[entry.key]!.integer('quantity')) {
        throw const AppFailure('La entrega supera la cantidad pendiente.');
      }
    }
    final now = timestamp;
    final receiptId = await tx.insert('Recepcion', {
      'branch_id': branchId,
      'order_id': orderId,
      'operation_id': operationId,
      'payload': payload,
      'created_at': now,
    });
    for (final line in lines) {
      final detail = byId[line.orderLineId]!;
      final item = await _item(
        tx,
        branchId,
        detail.integer('branch_product_id'),
      );
      final purchaseId = await tx.insert('Historial_Compras', {
        'receipt_id': receiptId,
        'order_id': orderId,
        'order_line_id': line.orderLineId,
        'branch_id': branchId,
        'branch_product_id': item.integer('id'),
        'product_id': item.integer('product_id'),
        'supplier_id': order.integer('supplier_id'),
        'quantity': line.quantity,
        'unit_cost': line.unitCost,
        'product_name': detail.text('product_name'),
        'unit': detail.text('unit'),
        'branch_name': order.text('branch_name'),
        'supplier_name': order.text('supplier_name'),
        'created_at': now,
      });
      final expiry = line.expiry == null ? null : dayKey(line.expiry!);
      final lotId = await tx.insert('Lote', {
        'branch_id': branchId,
        'branch_product_id': item.integer('id'),
        'purchase_id': purchaseId,
        'initial_quantity': line.quantity,
        'cantidad': line.quantity,
        'expiry_date': expiry,
        'fecha_alarma': expiry,
      });
      await tx.insert('Movimiento_Inventario', {
        'branch_id': branchId,
        'branch_product_id': item.integer('id'),
        'lot_id': lotId,
        'kind': 'receipt',
        'quantity': line.quantity,
        'reason': 'Recepción RC-$receiptId',
        'created_at': now,
      });
    }
    final pending =
        Sqflite.firstIntValue(
          await tx.rawQuery(
            '''SELECT SUM(d.quantity-COALESCE((SELECT SUM(h.quantity) FROM Historial_Compras h WHERE h.order_line_id=d.id),0)) FROM DetalleOrdenCompra d WHERE d.order_id=? AND d.branch_id=?''',
            [orderId, branchId],
          ),
        ) ??
        0;
    final status = pending == 0 ? 'received' : 'partial';
    await tx.update(
      'OrdenCompra',
      {'status': status},
      where: 'id=? AND branch_id=?',
      whereArgs: [orderId, branchId],
    );
    await _event(
      tx,
      branchId,
      orderId,
      status,
      note: 'Recepción RC-$receiptId',
    );
    return receiptId;
  });

  Future<void> consume(int branchId, int branchProductId, int quantity) =>
      db.transaction((tx) async {
        if (quantity <= 0) {
          throw const AppFailure('La cantidad debe ser mayor que cero.');
        }
        await _item(tx, branchId, branchProductId);
        final lots = await tx.query(
          'Lote',
          where: 'branch_id=? AND branch_product_id=? AND cantidad>0',
          whereArgs: [branchId, branchProductId],
          orderBy: 'expiry_date IS NULL,expiry_date,id',
        );
        if (lots.any(
          (l) =>
              l['expiry_date'] != null &&
              l.text('expiry_date').compareTo(dayKey(clock())) < 0,
        )) {
          throw const AppFailure(
            'Descarta primero los lotes caducados de este artículo.',
          );
        }
        final stock = lots.fold(0, (s, l) => s + l.integer('cantidad'));
        if (quantity > stock) {
          throw const AppFailure(
            'No hay suficientes unidades. El inventario no cambió.',
          );
        }
        var remaining = quantity;
        for (final lot in lots) {
          if (remaining == 0) break;
          final used = math.min(remaining, lot.integer('cantidad'));
          await tx.update(
            'Lote',
            {'cantidad': lot.integer('cantidad') - used},
            where: 'id=? AND branch_id=?',
            whereArgs: [lot.integer('id'), branchId],
          );
          await tx.insert('Movimiento_Inventario', {
            'branch_id': branchId,
            'branch_product_id': branchProductId,
            'lot_id': lot.integer('id'),
            'kind': 'consume',
            'quantity': used,
            'reason': 'Consumo FEFO',
            'created_at': timestamp,
          });
          remaining -= used;
        }
      });

  Future<void> discard(
    int branchId,
    int branchProductId,
    int lotId,
    int quantity,
    String reason,
  ) => db.transaction((tx) async {
    await _item(tx, branchId, branchProductId);
    final lots = await tx.query(
      'Lote',
      where: 'id=? AND branch_id=? AND branch_product_id=?',
      whereArgs: [lotId, branchId, branchProductId],
    );
    if (lots.isEmpty ||
        quantity <= 0 ||
        quantity > lots.single.integer('cantidad')) {
      throw const AppFailure('Revisa el lote y la cantidad a descartar.');
    }
    if (reason.trim().isEmpty) {
      throw const AppFailure('Indica el motivo del descarte.');
    }
    await tx.update(
      'Lote',
      {'cantidad': lots.single.integer('cantidad') - quantity},
      where: 'id=? AND branch_id=?',
      whereArgs: [lotId, branchId],
    );
    await tx.insert('Movimiento_Inventario', {
      'branch_id': branchId,
      'branch_product_id': branchProductId,
      'lot_id': lotId,
      'kind': 'discard',
      'quantity': quantity,
      'reason': reason.trim(),
      'created_at': timestamp,
    });
  });

  Future<void> saveReminderTime(int hour, int minute) =>
      db.transaction((tx) async {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          throw const AppFailure('Hora de recordatorio inválida.');
        }
        for (final entry in {
          'reminder_hour': '$hour',
          'reminder_minute': '$minute',
        }.entries) {
          await tx.insert('Configuracion', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> saveReport(DbRow report) async {
    await db.insert('ReporteExportado', report);
  }
}
