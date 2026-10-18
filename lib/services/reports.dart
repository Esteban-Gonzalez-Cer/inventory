import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import '../domain/models.dart';

class ReportSnapshot {
  ReportSnapshot({
    required this.id,
    required this.scopeName,
    required this.branchId,
    required this.period,
    required this.generatedAt,
    required this.timezone,
    required this.window,
    required List<DbRow> orders,
    required List<DbRow> lines,
    required List<DbRow> purchases,
    required List<DbRow> movements,
    required List<DbRow> events,
  }) : orders = _freeze(orders),
       lines = _freeze(lines),
       purchases = _freeze(purchases),
       movements = _freeze(movements),
       events = _freeze(events);
  final String id, scopeName, timezone;
  final int? branchId;
  final ReportPeriod period;
  final DateTime generatedAt;
  final ReportWindow window;
  final List<DbRow> orders, lines, purchases, movements, events;
  static List<DbRow> _freeze(List<DbRow> rows) =>
      List.unmodifiable(rows.map((r) => Map<String, Object?>.unmodifiable(r)));
  int get receivedTotal => purchases.fold(
    0,
    (s, r) => s + r.integer('quantity') * r.integer('unit_cost'),
  );
  int get orderedTotal => lines.fold(
    0,
    (s, r) => s + r.integer('quantity') * r.integer('unit_cost'),
  );
  int get consumed => movements
      .where((m) => m.text('kind') == 'consume')
      .fold(0, (s, m) => s + m.integer('quantity'));
  int get discarded => movements
      .where((m) => m.text('kind') == 'discard')
      .fold(0, (s, m) => s + m.integer('quantity'));

  factory ReportSnapshot.capture(
    Workspace workspace, {
    int? branchId,
    required ReportPeriod period,
    required DateTime generatedAt,
    required String timezone,
    String? id,
  }) {
    final window = period.window(generatedAt);
    List<DbRow> inPeriod(List<DbRow> rows) => workspace
        .scoped(rows, branchId)
        .where((r) => window.includes(r.text('created_at')))
        .toList();
    final purchases = inPeriod(workspace.purchases);
    final movements = inPeriod(workspace.movements)
        .where((m) => m.text('kind') != 'receipt')
        .toList();
    final events = inPeriod(workspace.events);
    final relevant = {
      ...purchases.map((r) => r.integer('order_id')),
      ...events.map((r) => r.integer('order_id')),
      ...movements.map((r) => r.integer('order_id')),
    };
    final orders = workspace
        .scoped(workspace.orders, branchId)
        .where(
          (o) =>
              relevant.contains(o.integer('id')) ||
              window.includes(o.text('created_at')),
        )
        .toList();
    final orderIds = orders.map((r) => r.integer('id')).toSet();
    return ReportSnapshot(
      id: id ?? const Uuid().v4(),
      scopeName: branchId == null
          ? 'Todas las tiendas'
          : workspace.branch(branchId).name,
      branchId: branchId,
      period: period,
      generatedAt: generatedAt.toUtc(),
      timezone: timezone,
      window: window,
      orders: orders,
      lines: workspace.lines
          .where((l) => orderIds.contains(l.integer('order_id')))
          .toList(),
      purchases: purchases,
      movements: movements,
      events: events,
    );
  }
}

class PdfInput {
  const PdfInput(this.snapshot, this.regular, this.bold);
  final ReportSnapshot snapshot;
  final Uint8List regular, bold;
}

class ReportService {
  static Future<Uint8List> generate(ReportSnapshot snapshot) async {
    final regular = await rootBundle.load('assets/fonts/Rubik-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Rubik-Medium.ttf');
    return compute(
      renderReport,
      PdfInput(
        snapshot,
        regular.buffer.asUint8List(),
        bold.buffer.asUint8List(),
      ),
    );
  }

  static Future<String> save(
    AlacenaRepository repository,
    ReportSnapshot snapshot,
    Uint8List bytes,
  ) async {
    final directory = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'reportes'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'alacena_${snapshot.id}.pdf'));
    final existing = await repository.db.query(
      'ReporteExportado',
      where: 'id=?',
      whereArgs: [snapshot.id],
    );
    if (existing.isNotEmpty) {
      final saved = File(existing.single.text('file_path'));
      if (!await saved.exists()) await saved.writeAsBytes(bytes, flush: true);
      return saved.path;
    }
    await file.writeAsBytes(bytes, flush: true);
    try {
      await repository.saveReport({
        'id': snapshot.id,
        'branch_id': snapshot.branchId,
        'scope_name': snapshot.scopeName,
        'period': snapshot.period.name,
        'starts_at': snapshot.window.start.toIso8601String(),
        'ends_at': snapshot.window.end.toIso8601String(),
        'generated_at': snapshot.generatedAt.toIso8601String(),
        'timezone': snapshot.timezone,
        'file_path': file.path,
      });
    } catch (e) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return file.path;
  }
}

Future<Uint8List> renderReport(PdfInput input) async {
  final s = input.snapshot;
  final doc = pw.Document(
    title: 'Alacena - ${s.scopeName}',
    author: 'Alacena',
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(ByteData.sublistView(input.regular)),
      bold: pw.Font.ttf(ByteData.sublistView(input.bold)),
    ),
  );
  const ink = PdfColor.fromInt(0xff171827),
      accent = PdfColor.fromInt(0xffe16f42);
  String cost(int cents) => 'MXN ${(cents / 100).toStringAsFixed(2)}';
  String date(String value) => value.isEmpty
      ? '—'
      : DateTime.parse(value)
            .toLocal()
            .toIso8601String()
            .replaceFirst('T', ' ')
            .substring(0, 16);
  pw.Widget section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: ink,
      ),
    ),
  );
  pw.Widget table(List<String> headers, List<List<String>> rows) => rows.isEmpty
      ? pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Text(
            'Sin registros en este período.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        )
      : pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 8,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: ink),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 7,
          ),
          oddRowDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xfff6f3ed),
          ),
          border: null,
        );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages:
          s.purchases.length +
          s.movements.length +
          s.events.length +
          s.lines.length +
          100,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'alacena.',
              style: pw.TextStyle(
                fontSize: 25,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
            pw.Text(
              'INVENTARIO Y TRAZABILIDAD',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Referencia ${s.id.substring(0, 8)} · ${s.scopeName}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        section(s.scopeName),
        pw.Text(
          s.period.label,
          style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Desde ${date(s.window.start.toIso8601String())} (incluido)\nHasta ${date(s.window.end.toIso8601String())} (excluido)\nGenerado ${date(s.generatedAt.toIso8601String())} · ${s.timezone}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        section('Resumen'),
        table(
          [
            'Pedidos relacionados',
            'Valor solicitado (contexto)',
            'Compras recibidas',
            'Unidades consumidas',
            'Unidades descartadas',
          ],
          [
            [
              '${s.orders.length}',
              cost(s.orderedTotal),
              cost(s.receivedTotal),
              '${s.consumed}',
              '${s.discarded}',
            ],
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'El valor solicitado corresponde a los pedidos relacionados. El gasto suma únicamente las recepciones del período; las órdenes no se suman otra vez como compras.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        section('Pedidos y artículos solicitados'),
        table(
          [
            'Pedido / tienda',
            'Proveedor / estado',
            'Artículo',
            'Cantidad',
            'Precio solicitado',
          ],
          [
            for (final o in s.orders)
              for (final l in s.lines.where(
                (l) => l.integer('order_id') == o.integer('id'),
              ))
                [
                  'OC-${o.integer('id')}\n${o.text('branch_name')}',
                  '${o.text('supplier_name')}\n${orderStatus(o.text('status'))}',
                  l.text('product_name'),
                  '${l.integer('quantity')} ${l.text('unit')}',
                  cost(l.integer('unit_cost')),
                ],
          ],
        ),
        section('Recepciones y compras del período'),
        table(
          [
            'Fecha / referencias',
            'Tienda / proveedor',
            'Artículo / lote',
            'Cantidad',
            'Precio unitario',
            'Importe',
          ],
          [
            for (final r in s.purchases)
              [
                '${date(r.text('created_at'))}\nOC-${r.integer('order_id')} / RC-${r.integer('receipt_id')} / C-${r.integer('id')}',
                '${r.text('branch_name')}\n${r.text('supplier_name')}',
                '${r.text('product_name')}\nL-${r.integer('lot_id')} · ${r['expiry_date'] ?? 'Sin caducidad'}',
                '${r.integer('quantity')} ${r.text('unit')}',
                cost(r.integer('unit_cost')),
                cost(r.integer('quantity') * r.integer('unit_cost')),
              ],
          ],
        ),
        section('Consumos y descartes del período'),
        table(
          [
            'Fecha / tienda',
            'Movimiento',
            'Artículo / referencias',
            'Cantidad',
            'Motivo',
          ],
          [
            for (final m in s.movements)
              [
                '${date(m.text('created_at'))}\n${m.text('branch_name')}',
                m.text('kind') == 'consume' ? 'Consumo' : 'Descarte',
                '${m.text('product_name')}\nM-${m.integer('id')} / L-${m.integer('lot_id')} / C-${m.integer('purchase_id')} / OC-${m.integer('order_id')}',
                '${m.integer('quantity')} ${m.text('unit')}',
                m.text('reason'),
              ],
          ],
        ),
        section('Eventos de pedidos del período'),
        table(
          ['Fecha', 'Tienda / pedido', 'Evento', 'Detalle'],
          [
            for (final e in s.events)
              [
                date(e.text('created_at')),
                '${e.text('branch_name')} / OC-${e.integer('order_id')}',
                e.text('kind') == 'edited'
                    ? 'Borrador editado'
                    : orderStatus(e.text('kind')),
                e.text('note'),
              ],
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
