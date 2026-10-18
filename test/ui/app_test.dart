import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory/app.dart';
import 'package:inventory/core/controller.dart';
import 'package:inventory/core/format.dart';
import 'package:inventory/ui/calendar.dart';
import 'package:inventory/ui/forms.dart';
import 'package:inventory/ui/inventory.dart';
import 'package:inventory/ui/orders.dart';
import 'package:inventory/ui/theme.dart';

import '../data/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('es_MX');
    final font = FontLoader('Rubik')
      ..addFont(rootBundle.load('assets/fonts/Rubik-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Rubik-Medium.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<(Fixture, AppController)> setup(
    WidgetTester tester, {
    bool seed = true,
  }) async {
    late Fixture fixture;
    late AppController controller;
    await tester.runAsync(() async {
      fixture = Fixture();
      await fixture.open();
      if (seed) await fixture.seed();
      controller = AppController(fixture.repo);
      await controller.refresh();
    });
    return (fixture, controller);
  }

  Future<void> close(
    WidgetTester tester,
    Fixture fixture,
    AppController controller,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(() => fixture.repo.db.close());
  }

  testWidgets(
    'global start is empty, uses real zeros and opens branch registration',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (f, c) = await setup(tester, seed: false);
      await tester.pumpWidget(AlacenaApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Todo en su lugar.'), findsOneWidget);
      expect(find.text('0 tiendas'), findsOneWidget);
      await tester.tap(find.text('Gestión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis tiendas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar tienda'));
      await tester.pumpAndSettle();
      expect(find.byType(MasterEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, f, c);
    },
  );

  testWidgets(
    'branch switch resets scoped navigation and cart badge counts pairs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (f, c) = await setup(tester);
      await tester.runAsync(() async {
        await f.repo.setCart(f.north, f.itemNorth, 3);
        await f.repo.setCart(f.south, f.itemSouth, 5);
        await c.refresh();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: AlacenaApp(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.cartCount, 2);
      await _capture(tester, boundary, 'dashboard');
      c.selectBranch(f.north);
      await tester.pumpAndSettle();
      expect(c.cartCount, 1);
      await tester.tap(find.text('Inventario').last);
      await tester.pumpAndSettle();
      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('Leche'), findsOneWidget);
      c.selectBranch(f.south);
      await tester.pumpAndSettle();
      expect(find.byType(InventoryPage), findsNothing);
      expect(find.text('Sur'), findsWidgets);
      await tester.tap(find.text('Inventario').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leche'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailsPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, f, c);
    },
  );

  testWidgets('five calendar alerts create five dots and a full-screen modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (f, c) = await setup(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        final product = await f.repo.createProduct({
          'name': 'Artículo $i',
          'unit': 'pieza',
          'category_id': f.category,
        });
        await f.repo.assignProduct(f.north, product);
      }
      await c.refresh();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: alacenaTheme(),
          home: Scaffold(
            body: CalendarPage(controller: c, branchId: f.north),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final prefix = 'calendar-dot-${dayKey(f.time)}-';
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(prefix),
      ),
      findsNWidgets(5),
    );
    await _capture(tester, boundary, 'calendar');
    final context = tester.element(find.byType(CalendarPage));
    showDayAlerts(context, c, f.time, branchId: f.north);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.getSize(find.byType(Dialog)), const Size(390, 844));
    expect(find.text('5 artículos · cantidades actuales'), findsOneWidget);
    await _capture(tester, boundary, 'calendar-day');
    expect(tester.takeException(), isNull);
    await close(tester, f, c);
  });

  testWidgets('dashboard fits a narrow phone with larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (f, c) = await setup(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: AlacenaApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await close(tester, f, c);
  });
  testWidgets('cold notification opens its day after the first app frame', (
    tester,
  ) async {
    final (f, c) = await setup(tester);
    await tester.runAsync(() async {
      final order = await f.order(f.north, f.itemNorth, 1);
      await f.deliver(f.north, order, 1, 'today', expiry: f.time);
      await c.refresh();
    });
    c.pendingNotificationDate = dayKey(f.time);
    await tester.pumpWidget(AlacenaApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Leche'), findsOneWidget);
    expect(c.pendingNotificationDate, isNull);
    expect(tester.takeException(), isNull);
    await close(tester, f, c);
  });

  testWidgets('cancellation dialog owns its field through closing animation', (
    tester,
  ) async {
    String? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async => answer = await requestReason(context),
              child: const Text('Cancelar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Entrega incompleta');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(answer, 'Entrega incompleta');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/qa').create(recursive: true);
    await File('build/qa/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
