import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/core/format.dart';
import 'package:inventory/domain/models.dart';

import 'fixtures.dart';

void main() {
  late Fixture f;
  setUp(() async {
    f = Fixture();
    await f.open();
    await f.seed();
  });
  tearDown(() async {
    await f.repo.db.close();
  });

  test('FEFO consumes earliest batches atomically and excessive requests do not mutate', () async {
    final order = await f.order(f.north, f.itemNorth, 5);
    await f.deliver(f.north, order, 3, 'later', expiry: DateTime(2026, 11, 3));
    await f.deliver(
      f.north,
      order,
      2,
      'earlier',
      expiry: DateTime(2026, 10, 20),
    );
    await f.repo.consume(f.north, f.itemNorth, 3);
    var item = (await f.repo.load()).item(f.itemNorth);
    expect(item.stock, 2);
    expect(item.lots.first.quantity, 0);
    expect(item.lots.last.quantity, 2);
    await expectLater(
      f.repo.consume(f.north, f.itemNorth, 3),
      throwsA(isA<AppFailure>()),
    );
    item = (await f.repo.load()).item(f.itemNorth);
    expect(item.stock, 2);
  });

  test(
    'expired stock counted until discard; blocking is branch specific',
    () async {
      final a = await f.order(f.north, f.itemNorth, 2);
      await f.deliver(f.north, a, 2, 'expired', expiry: DateTime(2026, 10, 16));
      final b = await f.order(f.south, f.itemSouth, 3);
      await f.deliver(f.south, b, 3, 'fresh', expiry: DateTime(2026, 11, 1));
      var workspace = await f.repo.load();
      expect(workspace.item(f.itemNorth).stock, 2);
      expect(
        workspace.item(f.itemNorth).alerts(f.time),
        contains(AlertKind.expired),
      );
      await expectLater(
        f.repo.consume(f.north, f.itemNorth, 1),
        throwsA(isA<AppFailure>()),
      );
      await f.repo.consume(f.south, f.itemSouth, 1);
      await f.repo.discard(
        f.north,
        f.itemNorth,
        workspace.item(f.itemNorth).lots.single.id,
        2,
        'Caducidad',
      );
      workspace = await f.repo.load();
      expect(
        workspace.item(f.itemNorth).alerts(f.time),
        contains(AlertKind.empty),
      );
      expect(workspace.item(f.itemSouth).stock, 2);
    },
  );

  test('partial receipts, replay protection and cancellation preserve stock and cost', () async {
    await f.repo.setCart(f.north, f.itemNorth, 5);
    final order = await f.order(f.north, f.itemNorth, 5);
    expect((await f.repo.load()).cart, isEmpty);
    final receipt = await f.deliver(f.north, order, 2, 'receipt-1', cost: 2700);
    expect(
      await f.deliver(f.north, order, 2, 'receipt-1', cost: 2700),
      receipt,
    );
    var w = await f.repo.load();
    expect(w.item(f.itemNorth).stock, 2);
    expect(w.orders.single.text('status'), 'partial');
    final window = ReportPeriod.day.window(
      f.time.add(const Duration(seconds: 1)),
    );
    expect(w.spending(window), 5400);
    await expectLater(
      f.deliver(f.north, order, 4, 'too-much'),
      throwsA(isA<AppFailure>()),
    );
    expect((await f.repo.load()).purchases.length, 1);
    await f.repo.cancelOrder(f.north, order, 'No se entregará el resto');
    w = await f.repo.load();
    expect(w.orders.single.text('status'), 'cancelled');
    expect(w.item(f.itemNorth).stock, 2);
    await expectLater(
      f.deliver(f.north, order, 1, 'after-cancel'),
      throwsA(isA<AppFailure>()),
    );
  });

  test(
    'same operation id cannot be reused with a different payload or branch',
    () async {
      final order = await f.order(f.north, f.itemNorth, 5);
      await f.deliver(f.north, order, 1, 'unique');
      await expectLater(
        f.deliver(f.north, order, 2, 'unique'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        f.repo.receive(f.south, order, 'unique', [
          const ReceiptLine(orderLineId: 1, quantity: 1, unitCost: 2500),
        ]),
        throwsA(isA<AppFailure>()),
      );
      expect((await f.repo.load()).item(f.itemNorth).stock, 1);
    },
  );

  test(
    'supplier history is global and last supplier also scoped per branch',
    () async {
      final a = await f.order(f.north, f.itemNorth, 1);
      await f.deliver(f.north, a, 1, 'a');
      final b = await f.order(f.south, f.itemSouth, 1, supplier: f.supplierB);
      await f.deliver(f.south, b, 1, 'b');
      final w = await f.repo.load();
      expect(w.purchases.map((r) => r.integer('supplier_id')).toSet(), {
        f.supplierA,
        f.supplierB,
      });
      expect(w.products.single.integer('ultima_tienda_id'), f.supplierB);
      expect(w.item(f.itemNorth).row.integer('ultima_tienda_id'), f.supplierA);
      expect(w.item(f.itemSouth).row.integer('ultima_tienda_id'), f.supplierB);
    },
  );

  test(
    'invalid later receipt line rolls back all lines and identifiers',
    () async {
      final order = await f.order(f.north, f.itemNorth, 3);
      final line = (await f.repo.load()).lines.single.integer('id');
      await expectLater(
        f.repo.receive(f.north, order, 'rollback', [
          ReceiptLine(orderLineId: line, quantity: 2, unitCost: 100),
          const ReceiptLine(orderLineId: 9999, quantity: 1, unitCost: 100),
        ]),
        throwsA(isA<AppFailure>()),
      );
      expect((await f.repo.load()).item(f.itemNorth).stock, 0);
      expect(await f.repo.db.query('Recepcion'), isEmpty);
    },
  );

  test('scope, referential integrity and immutable history reject invalid mutations', () async {
    await expectLater(
      f.repo.setCart(f.south, f.itemNorth, 1),
      throwsA(isA<AppFailure>()),
    );
    final order = await f.order(f.north, f.itemNorth, 1);
    await expectLater(
      f.repo.submitOrder(f.south, order),
      throwsA(isA<AppFailure>()),
    );
    await f.deliver(f.north, order, 1, 'valid');
    await expectLater(
      f.repo.deleteMaster('Sucursal', f.north),
      throwsA(anything),
    );
    await expectLater(
      f.repo.db.update('Historial_Compras', {'quantity': 2}),
      throwsA(anything),
    );
    await expectLater(
      f.repo.db.insert('Carrito_Item', {
        'branch_id': f.south,
        'branch_product_id': f.itemNorth,
        'quantity': 1,
      }),
      throwsA(anything),
    );
    expect((await f.repo.load()).item(f.itemNorth).stock, 1);
  });

  test('branch thresholds and cart are independent', () async {
    await f.repo.configureProduct(
      f.north,
      f.itemNorth,
      minimum: 8,
      warningDays: 3,
      reminders: false,
    );
    await f.repo.setCart(f.north, f.itemNorth, 3);
    await f.repo.setCart(f.south, f.itemSouth, 7);
    final w = await f.repo.load();
    expect(w.item(f.itemNorth).minimum, 8);
    expect(w.item(f.itemSouth).minimum, 2);
    expect(w.scoped(w.cart, f.north).single.integer('quantity'), 3);
    expect(w.scoped(w.cart, f.south).single.integer('quantity'), 7);
  });

  test('database persists after closing and reopening', () async {
    final dir = await Directory.systemTemp.createTemp('alacena-test-');
    final persistent = Fixture();
    try {
      await persistent.open(path: '${dir.path}/inventory.db');
      await persistent.seed();
      await persistent.repo.setCart(persistent.north, persistent.itemNorth, 4);
      await persistent.repo.db.close();
      await persistent.open(path: '${dir.path}/inventory.db');
      final w = await persistent.repo.load();
      expect(w.branches.length, 2);
      expect(w.cart.single.integer('quantity'), 4);
    } finally {
      await persistent.repo.db.close();
      await dir.delete(recursive: true);
    }
  });
}
