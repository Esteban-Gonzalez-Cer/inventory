import 'dart:io';

import 'package:inventory/data/database.dart';
import 'package:inventory/data/repository.dart';
import 'package:inventory/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Fixture {
  DateTime time = DateTime(2026, 10, 17, 12);
  late AlacenaRepository repo;
  late int north,
      south,
      supplierA,
      supplierB,
      category,
      product,
      itemNorth,
      itemSouth;
  Future<void> open({String path = inMemoryDatabasePath}) async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      schema: await File('assets/sql/001_schema.sql').readAsString(),
    );
    repo = AlacenaRepository(db, clock: () => time);
  }

  Future<void> seed() async {
    north = await repo.saveMaster('Sucursal', {
      'name': 'Norte',
      'address': 'Calle 1',
      'latitude': 19.4,
      'longitude': -99.1,
    });
    south = await repo.saveMaster('Sucursal', {
      'name': 'Sur',
      'address': 'Calle 2',
      'latitude': 19.3,
      'longitude': -99.2,
    });
    supplierA = await repo.saveMaster('Tienda', {'name': 'Proveedor A'});
    supplierB = await repo.saveMaster('Tienda', {'name': 'Proveedor B'});
    category = await repo.saveMaster('Categoria', {'name': 'Lácteos'});
    product = await repo.createProduct({
      'name': 'Leche',
      'unit': 'cartón',
      'category_id': category,
    });
    itemNorth = await repo.assignProduct(north, product);
    itemSouth = await repo.assignProduct(south, product);
  }

  Future<int> order(
    int branch,
    int item,
    int quantity, {
    int? supplier,
    int cost = 2500,
    bool submit = true,
  }) async {
    final id = await repo.saveDraft(branch, supplier ?? supplierA, [
      (itemId: item, quantity: quantity, unitCost: cost),
    ]);
    if (submit) await repo.submitOrder(branch, id);
    return id;
  }

  Future<int> deliver(
    int branch,
    int order,
    int quantity,
    String operation, {
    DateTime? expiry,
    int cost = 2500,
  }) async {
    final snapshot = await repo.load();
    final line = snapshot.lines.firstWhere(
      (l) => l.integer('order_id') == order,
    );
    return repo.receive(branch, order, operation, [
      ReceiptLine(
        orderLineId: line.integer('id'),
        quantity: quantity,
        unitCost: cost,
        expiry: expiry,
      ),
    ]);
  }
}
