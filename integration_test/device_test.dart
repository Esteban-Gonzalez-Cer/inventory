import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory/app.dart';
import 'package:inventory/core/controller.dart';
import 'package:inventory/core/format.dart';
import 'package:inventory/data/database.dart';
import 'package:inventory/data/repository.dart';
import 'package:inventory/domain/models.dart';
import 'package:inventory/services/reminders.dart';
import 'package:inventory/services/reports.dart';
import 'package:inventory/ui/reports_view.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Uses a separate database and removes it after the test. Never changes alacena.db.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final screenshots = <Map<String, dynamic>>[];
  binding.reportData = {'screenshots': screenshots};

  testWidgets('native persistence, purchasing, map, reminders and PDF', (
    tester,
  ) async {
    await initializeDateFormatting('es_MX');
    final path = p.join(
      await getDatabasesPath(),
      'integration_${const Uuid().v4()}.db',
    );
    var db = await AppDatabase.open(path: path);
    var repo = AlacenaRepository(db);
    final now = DateTime.now();
    final tomorrow = dateOnly(now).add(const Duration(days: 1));
    final nextWeek = dateOnly(now).add(const Duration(days: 7));
    final north = await repo.saveMaster('Sucursal', {
      'name': 'Centro',
      'address': 'Centro histórico, Ciudad de México',
      'latitude': 19.4326,
      'longitude': -99.1332,
    });
    final south = await repo.saveMaster('Sucursal', {
      'name': 'Jardines',
      'address': 'Colonia Roma, Ciudad de México',
      'latitude': 19.4194,
      'longitude': -99.1617,
    });
    final supplier = await repo.saveMaster('Tienda', {'name': 'Mercado local'});
    final category = await repo.saveMaster('Categoria', {'name': 'Lácteos'});
    final product = await repo.createProduct({
      'name': 'Leche entera',
      'unit': 'cartón',
      'category_id': category,
      'image_asset': 'assets/products/milk.svg',
    });
    final itemNorth = await repo.assignProduct(north, product);
    final itemSouth = await repo.assignProduct(south, product);
    await repo.setCart(north, itemNorth, 10);
    final order = await repo.saveDraft(north, supplier, [
      (itemId: itemNorth, quantity: 10, unitCost: 2450),
    ]);
    await repo.submitOrder(north, order);
    var w = await repo.load();
    expect(w.items.singleWhere((i) => i.id == itemNorth).stock, 0);
    expect(w.cart, isEmpty);
    final line = w.lines.single.integer('id');
    final delivery = [
      ReceiptLine(
        orderLineId: line,
        quantity: 3,
        unitCost: 2500,
        expiry: tomorrow,
      ),
      ReceiptLine(
        orderLineId: line,
        quantity: 2,
        unitCost: 2500,
        expiry: nextWeek,
      ),
    ];
    final receipt = await repo.receive(
      north,
      order,
      'device-receipt',
      delivery,
    );
    expect(
      await repo.receive(north, order, 'device-receipt', delivery),
      receipt,
    );
    await repo.consume(north, itemNorth, 4);
    w = await repo.load();
    expect(w.items.singleWhere((i) => i.id == itemNorth).stock, 1);
    expect(w.items.singleWhere((i) => i.id == itemSouth).stock, 0);
    expect(w.orders.single.text('status'), 'partial');
    expect(w.purchases.length, 2);
    await repo.cancelOrder(north, order, 'Cerrar cantidades pendientes');
    await db.close();
    db = await AppDatabase.open(path: path);
    repo = AlacenaRepository(db);
    w = await repo.load();
    expect(w.items.singleWhere((i) => i.id == itemNorth).stock, 1);
    expect(w.orders.single.text('status'), 'cancelled');

    final reminders = ReminderService();
    await reminders.initialize();
    await reminders.synchronize(w);
    final scheduled = await reminders.plugin.pendingNotificationRequests();
    expect(scheduled.length, 1);
    expect(scheduled.single.payload, dayKey(nextWeek));

    final report = ReportSnapshot.capture(
      w,
      period: ReportPeriod.week,
      generatedAt: DateTime.now().add(const Duration(seconds: 1)),
      timezone: reminders.timezone,
    );
    expect(report.receivedTotal, 12500);
    expect(report.consumed, 4);
    final bytes = await ReportService.generate(report);
    final saved = await ReportService.save(repo, report, bytes);
    expect(await File(saved).exists(), isTrue);
    expect((await Printing.info()).canRaster, isTrue);
    final raster = await Printing.raster(bytes, pages: [0], dpi: 72).first;
    expect(raster.width, greaterThan(500));
    final cache = await getApplicationCacheDirectory();
    await File(p.join(cache.path, 'qa-native-pdf.png'))
        .writeAsBytes(await raster.toPng());
    screenshots.add({'screenshotName': 'pdf', 'bytes': await raster.toPng()});

    await repo.setCart(north, itemNorth, 3);
    await repo.setCart(south, itemSouth, 2);
    final controller = AppController(repo);
    await controller.refresh();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: AlacenaApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.cartCount, 2);
    await capture(boundary, screenshots, 'dashboard');
    await tester.tap(find.text('Mapa'));
    // Allow normal on-demand tiles to finish; there is no bulk download.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
      2,
    );
    await capture(boundary, screenshots, 'map');
    await tester.tap(find.text('Abrir tienda'));
    await tester.pumpAndSettle();
    expect(controller.selectedBranchId, north);
    expect(controller.cartCount, 1);
    await tester.tap(find.text('Inventario').last);
    await tester.pumpAndSettle();
    expect(find.text('Leche entera'), findsOneWidget);
    await capture(boundary, screenshots, 'inventory');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PdfDocumentPage(
          bytes: bytes,
          title: 'Centro',
          filename: 'qa.pdf',
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugPrint(
      'NATIVE QA: SQLite reopen, partial receipt replay, FEFO, branch '
      'isolation, pending notification and PDF raster passed.',
    );
    debugPrint('QA images: ${cache.path}');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await reminders.plugin.cancelAllPendingNotifications();
    await File(saved).delete();
    await db.close();
    await deleteDatabase(path);
  });
}

Future<void> capture(
  GlobalKey key,
  List<Map<String, dynamic>> screenshots,
  String name,
) async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  screenshots.add({
    'screenshotName': name,
    'bytes': bytes!.buffer.asUint8List(),
  });
  image.dispose();
}
