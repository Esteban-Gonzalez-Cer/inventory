import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/domain/models.dart';
import 'package:inventory/services/reports.dart';

import '../data/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  setUp(() async {
    f = Fixture();
    await f.open();
    await f.seed();
  });
  tearDown(() async {
    await f.repo.db.close();
  });

  test('report includes older orders for receipts in range, without double counting', () async {
    f.time = DateTime(2026, 8, 1, 9);
    final older = await f.order(f.north, f.itemNorth, 8);
    f.time = DateTime(2026, 10, 17, 10);
    await f.deliver(
      f.north,
      older,
      5,
      'october',
      cost: 2500,
      expiry: DateTime(2026, 11, 1),
    );
    await f.repo.consume(f.north, f.itemNorth, 2);
    final item = (await f.repo.load()).item(f.itemNorth);
    await f.repo.discard(
      f.north,
      f.itemNorth,
      item.lots.single.id,
      1,
      'Daño en el envase',
    );
    final south = await f.order(f.south, f.itemSouth, 2);
    await f.deliver(f.south, south, 2, 'south', cost: 900);
    final w = await f.repo.load();
    final report = ReportSnapshot.capture(
      w,
      branchId: f.north,
      period: ReportPeriod.day,
      generatedAt: f.time.add(const Duration(seconds: 1)),
      timezone: 'America/Mexico_City',
    );
    expect(report.orders.single.integer('id'), older);
    expect(report.receivedTotal, 12500);
    expect(report.orderedTotal, 20000);
    expect(report.consumed, 2);
    expect(report.discarded, 1);
    expect(
      report.purchases.every((r) => r.integer('branch_id') == f.north),
      true,
    );
    expect(
      () => report.purchases.first['quantity'] = 999,
      throwsUnsupportedError,
    );
    final global = ReportSnapshot.capture(
      w,
      period: ReportPeriod.day,
      generatedAt: f.time.add(const Duration(seconds: 1)),
      timezone: 'America/Mexico_City',
    );
    expect(global.receivedTotal, 14300);
    final bytes = await ReportService.generate(report);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/report-short.pdf').writeAsBytes(bytes);
  });

  test('empty period creates a readable PDF with zero totals', () async {
    final report = ReportSnapshot.capture(
      await f.repo.load(),
      period: ReportPeriod.year,
      generatedAt: f.time,
      timezone: 'America/Mexico_City',
    );
    expect(report.receivedTotal, 0);
    expect(report.orders, isEmpty);
    final bytes = await ReportService.generate(report);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/report-empty.pdf').writeAsBytes(bytes);
    expect(bytes.length, greaterThan(5000));
  });

  test(
    'consuming an older purchase retains its order as report context',
    () async {
      f.time = DateTime(2026, 8, 1, 9);
      final order = await f.order(f.north, f.itemNorth, 5);
      await f.deliver(f.north, order, 5, 'old', expiry: DateTime(2026, 12, 1));
      f.time = DateTime(2026, 10, 17, 10);
      await f.repo.consume(f.north, f.itemNorth, 2);
      final snapshot = ReportSnapshot.capture(
        await f.repo.load(),
        period: ReportPeriod.day,
        generatedAt: f.time.add(const Duration(seconds: 1)),
        timezone: 'America/Mexico_City',
      );
      expect(snapshot.purchases, isEmpty);
      expect(snapshot.events, isEmpty);
      expect(snapshot.receivedTotal, 0);
      expect(snapshot.consumed, 2);
      expect(snapshot.orders.single.integer('id'), order);
    },
  );

  test('long PDF paginates all receipt, movement and event rows', () async {
    final timestamp = DateTime(2026, 10, 17, 9).toUtc().toIso8601String();
    final report = ReportSnapshot(
      id: 'qa-long-report-20261017',
      scopeName: 'Todas las tiendas',
      branchId: null,
      period: ReportPeriod.year,
      generatedAt: f.time.toUtc(),
      timezone: 'America/Mexico_City',
      window: ReportPeriod.year.window(f.time),
      orders: [
        {
          'id': 1,
          'branch_id': 1,
          'branch_name': 'Norte',
          'supplier_name': 'Proveedor de prueba',
          'status': 'received',
          'created_at': timestamp,
        },
      ],
      lines: [
        for (var i = 0; i < 320; i++)
          {
            'id': i + 1,
            'order_id': 1,
            'product_name': 'Artículo de prueba número ${i + 1}',
            'quantity': 5,
            'unit': 'paquete',
            'unit_cost': 2599,
          },
      ],
      purchases: [
        for (var i = 0; i < 320; i++)
          {
            'id': i + 1,
            'receipt_id': 1,
            'order_id': 1,
            'branch_id': 1,
            'branch_name': 'Norte',
            'supplier_name': 'Proveedor de prueba',
            'product_name': 'Artículo de prueba número ${i + 1}',
            'lot_id': i + 1,
            'expiry_date': '2027-01-01',
            'quantity': 5,
            'unit': 'paquete',
            'unit_cost': 2599,
            'created_at': timestamp,
          },
      ],
      movements: [
        for (var i = 0; i < 320; i++)
          {
            'id': i + 1,
            'lot_id': i + 1,
            'purchase_id': i + 1,
            'order_id': 1,
            'branch_id': 1,
            'branch_name': 'Norte',
            'product_name': 'Artículo de prueba número ${i + 1}',
            'quantity': 1,
            'unit': 'paquete',
            'kind': 'discard',
            'reason':
                'Envase dañado; se conserva la referencia de compra y lote.',
            'created_at': timestamp,
          },
      ],
      events: [
        {
          'id': 1,
          'order_id': 1,
          'branch_name': 'Norte',
          'kind': 'received',
          'note': 'Recepción RC-1',
          'created_at': timestamp,
        },
      ],
    );
    final bytes = await ReportService.generate(report);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/report-long.pdf').writeAsBytes(bytes);
    expect(report.receivedTotal, 4158400);
    expect(bytes.length, greaterThan(10000));
  });
}
