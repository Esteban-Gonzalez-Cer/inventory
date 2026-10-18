import '../core/format.dart';

typedef DbRow = Map<String, Object?>;

extension RowValues on DbRow {
  int integer(String key) => (this[key] as num?)?.toInt() ?? 0;
  String text(String key) => this[key]?.toString() ?? '';
  double decimal(String key) => (this[key] as num?)?.toDouble() ?? 0;
}

enum AlertKind {
  expired('Caducado'),
  empty('Agotado'),
  today('Caduca hoy'),
  expiring('Por caducar'),
  low('Por agotarse');

  const AlertKind(this.label);
  final String label;
}

class Branch {
  Branch(this.row);
  final DbRow row;
  int get id => row.integer('id');
  String get name => row.text('name');
  String get address => row.text('address');
  double get latitude => row.decimal('latitude');
  double get longitude => row.decimal('longitude');
}

class Lot {
  Lot(this.row);
  final DbRow row;
  int get id => row.integer('id');
  int get branchProductId => row.integer('branch_product_id');
  int get quantity => row.integer('cantidad');
  DateTime? get expiry => row['expiry_date'] == null
      ? null
      : DateTime.parse(row.text('expiry_date'));
  DateTime? get alarmDate => row['fecha_alarma'] == null
      ? null
      : DateTime.parse(row.text('fecha_alarma'));
  String get reference => 'L-${id.toString().padLeft(5, '0')}';
}

class InventoryItem {
  InventoryItem(this.row, this.lots);
  final DbRow row;
  final List<Lot> lots;
  int get id => row.integer('id');
  int get branchId => row.integer('branch_id');
  int get productId => row.integer('product_id');
  String get name => row.text('name');
  String get unit => row.text('unit');
  String get branchName => row.text('branch_name');
  String get category => row.text('category_name');
  int get categoryId => row.integer('category_id');
  int get stock => lots.fold(0, (sum, lot) => sum + lot.quantity);
  int get minimum => row.integer('minimum_stock');
  int get warningDays => row.integer('warning_days');
  DateTime? get nearestExpiry {
    final dated =
        lots
            .where((l) => l.quantity > 0 && l.expiry != null)
            .map((l) => l.expiry!)
            .toList()
          ..sort();
    return dated.isEmpty ? null : dated.first;
  }

  Set<AlertKind> alerts(DateTime now) {
    final today = dateOnly(now);
    final through = DateTime(today.year, today.month, today.day + warningDays);
    return {
      if (stock == 0) AlertKind.empty,
      if (stock > 0 && stock <= minimum) AlertKind.low,
      for (final lot in lots.where((l) => l.quantity > 0 && l.expiry != null))
        if (lot.expiry!.isBefore(today))
          AlertKind.expired
        else if (lot.expiry == today)
          AlertKind.today
        else if (!lot.expiry!.isAfter(through))
          AlertKind.expiring,
    };
  }

  bool alertsOn(DateTime selected, DateTime now) {
    final day = dateOnly(selected);
    final today = dateOnly(now);
    if (day == today) return alerts(now).isNotEmpty;
    return lots.any((lot) {
      final expiry = lot.expiry;
      if (lot.quantity <= 0 || expiry == null) return false;
      if (day.isBefore(today)) return expiry == day;
      return !day.isAfter(expiry) &&
          !day.isBefore(
            DateTime(expiry.year, expiry.month, expiry.day - warningDays),
          );
    });
  }
}

enum ReportPeriod {
  day('Último día', null),
  week('Última semana', null),
  month('Último mes', 1),
  quarter('Últimos 3 meses', 3),
  halfYear('Últimos 6 meses', 6),
  year('Último año', 12);

  const ReportPeriod(this.label, this.months);
  final String label;
  final int? months;
  ReportWindow window(DateTime generatedAt) {
    final end = generatedAt.toUtc();
    if (this == day || this == week) {
      return ReportWindow(
        end.subtract(Duration(days: this == day ? 1 : 7)),
        end,
      );
    }
    final local = generatedAt.toLocal();
    final first = DateTime(local.year, local.month - months!, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    final start = DateTime(
      first.year,
      first.month,
      local.day > lastDay ? lastDay : local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
    return ReportWindow(start.toUtc(), end);
  }
}

class ReportWindow {
  const ReportWindow(this.start, this.end);
  final DateTime start, end;
  bool includes(String timestamp) {
    final time = DateTime.parse(timestamp).toUtc();
    return !time.isBefore(start) && time.isBefore(end);
  }
}

class Workspace {
  Workspace({
    required this.branches,
    required this.categories,
    required this.suppliers,
    required this.products,
    required this.items,
    required this.cart,
    required this.orders,
    required this.lines,
    required this.purchases,
    required this.movements,
    required this.events,
    required this.reports,
    required this.settings,
  });
  final List<Branch> branches;
  final List<DbRow> categories,
      suppliers,
      products,
      cart,
      orders,
      lines,
      purchases,
      movements,
      events,
      reports;
  final List<InventoryItem> items;
  final Map<String, String> settings;
  List<InventoryItem> inventory([int? branchId]) =>
      items.where((p) => branchId == null || p.branchId == branchId).toList();
  InventoryItem item(int id) => items.firstWhere((p) => p.id == id);
  Branch branch(int id) => branches.firstWhere((b) => b.id == id);
  List<DbRow> scoped(List<DbRow> rows, int? branchId) => rows
      .where((r) => branchId == null || r.integer('branch_id') == branchId)
      .toList();
  int receivedQuantity(int lineId) => purchases
      .where((p) => p.integer('order_line_id') == lineId)
      .fold(0, (sum, p) => sum + p.integer('quantity'));
  int spending(ReportWindow window, [int? branchId]) =>
      scoped(purchases, branchId)
          .where((p) => window.includes(p.text('created_at')))
          .fold(
            0,
            (sum, p) => sum + p.integer('quantity') * p.integer('unit_cost'),
          );
}

class ReceiptLine {
  const ReceiptLine({
    required this.orderLineId,
    required this.quantity,
    required this.unitCost,
    this.expiry,
  });
  final int orderLineId, quantity, unitCost;
  final DateTime? expiry;
}

String orderStatus(String status) => switch (status) {
  'draft' => 'Borrador',
  'ordered' => 'Pedido',
  'partial' => 'Parcialmente recibido',
  'received' => 'Recibido',
  'cancelled' => 'Cancelado',
  _ => status,
};
