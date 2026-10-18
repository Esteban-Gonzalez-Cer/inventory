import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'forms.dart';
import 'inventory.dart';
import 'orders.dart';
import 'reports_view.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onOpenBranch,
    this.branchId,
    this.onInventory,
    this.onOrders,
  });
  final AppController controller;
  final int? branchId;
  final void Function(int) onOpenBranch;
  final VoidCallback? onInventory, onOrders;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  ReportPeriod period = ReportPeriod.month;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        w = c.workspace!,
        items = w.inventory(widget.branchId);
    final stock = items.fold(0, (sum, i) => sum + i.stock);
    final alerts = items.where((i) => i.alerts(c.now).isNotEmpty).toList()
      ..sort((a, b) {
        final ae = a.alerts(c.now).contains(AlertKind.expired),
            be = b.alerts(c.now).contains(AlertKind.expired);
        return ae == be ? a.name.compareTo(b.name) : (ae ? -1 : 1);
      });
    final window = period.window(c.now),
        spent = w.spending(window, widget.branchId);
    final pending = w
        .scoped(w.orders, widget.branchId)
        .where((o) => {'ordered', 'partial'}.contains(o.text('status')))
        .length;
    final counts = [
      items.where((i) => i.alerts(c.now).contains(AlertKind.expired)).length,
      items.where((i) => i.stock == 0).length,
      items
          .where(
            (i) => i
                .alerts(c.now)
                .any((s) => s == AlertKind.expiring || s == AlertKind.today),
          )
          .length,
      items.where((i) => i.alerts(c.now).contains(AlertKind.low)).length,
    ];
    final branch = widget.branchId == null ? null : w.branch(widget.branchId!);
    final values = List<double>.filled(7, 0);
    final duration = window.end.difference(window.start).inMilliseconds;
    for (final purchase
        in w
            .scoped(w.purchases, widget.branchId)
            .where((p) => window.includes(p.text('created_at')))) {
      final elapsed = DateTime.parse(purchase.text('created_at'))
          .toUtc()
          .difference(window.start)
          .inMilliseconds;
      final index = math.min(6, (elapsed / duration * 7).floor());
      values[index] +=
          purchase.integer('quantity') * purchase.integer('unit_cost') / 100;
    }
    return AppScroll(
      slivers: [
        sliverBox(
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SmallLabel(
                      branch == null ? 'Vista general' : 'Resumen de tu tienda',
                    ),
                    const SizedBox(height: 7),
                    Text(
                      branch == null ? 'Todo en su lugar.' : branch.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              if (branch != null)
                IconButton(
                  tooltip: 'Exportar PDF de esta tienda',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(branch.name)),
                        body: ReportsPage(controller: c, branchId: branch.id),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
            ],
          ),
        ),
        sliverBox(
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [
                  Color(0xfff4d29b),
                  Color(0xfff29169),
                  Color(0xffdf7355),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 21),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Existencias actuales',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'EN VIVO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '$stock',
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontSize: 54),
                ),
                const Text(
                  'unidades registradas',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(
                        branch == null
                            ? '${w.branches.length} tiendas'
                            : '${items.length} artículos',
                        branch == null ? 'registradas' : 'asignados',
                      ),
                    ),
                    Expanded(
                      child: _HeroMetric('$pending pedidos', 'pendientes'),
                    ),
                    Expanded(
                      child: _HeroMetric(
                        '${alerts.length} artículos',
                        'con alertas',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        sliverBox(
          const SectionTitle(
            'Lo que necesita atención',
            subtitle: 'Estado actual · un artículo puede tener varias alertas',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.crossAxisExtent >= 600 ? 4 : 2;
              return SliverGrid.count(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio:
                    ((constraints.crossAxisExtent - (columns - 1) * 10) /
                        columns) /
                    (116 * MediaQuery.textScalerOf(context).scale(16) / 16),
                children: [
                  _Indicator(
                    '${counts[0]}',
                    'Caducados',
                    Icons.event_busy_outlined,
                    AppColors.red,
                  ),
                  _Indicator(
                    '${counts[1]}',
                    'Agotados',
                    Icons.remove_shopping_cart_outlined,
                    AppColors.ink,
                  ),
                  _Indicator(
                    '${counts[2]}',
                    'Por caducar',
                    Icons.schedule,
                    AppColors.amber,
                  ),
                  _Indicator(
                    '${counts[3]}',
                    'Por agotarse',
                    Icons.battery_1_bar,
                    AppColors.orange,
                  ),
                ],
              );
            },
          ),
        ),
        sliverBox(
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'Compras recibidas',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    DropdownButton<ReportPeriod>(
                      value: period,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.ink,
                        fontFamily: 'Rubik',
                      ),
                      items: ReportPeriod.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => period = v!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(spent),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const Text(
                  'MXN · importe real de las entregas',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 115,
                  width: double.infinity,
                  child: CustomPaint(painter: PurchaseChartPainter(values)),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      shortDate(window.start.toLocal()),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      shortDate(window.end.toLocal()),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                if (spent == 0) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Sin compras recibidas en este período.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (branch == null) ...[
          sliverBox(
            SectionTitle(
              'Tus tiendas',
              subtitle:
                  '${w.products.length} productos en el catálogo compartido',
              action: 'Agregar',
              onAction: () => editMaster(context, c, 'Sucursal'),
            ),
          ),
          if (w.branches.isEmpty)
            sliverBox(
              EmptyState(
                'Dale un lugar a tu inventario',
                'Registra tu primera tienda. Después podrás agregar artículos, recibir pedidos y consultar sus alertas.',
                icon: Icons.storefront_outlined,
                action: 'Agregar primera tienda',
                onAction: () => editMaster(context, c, 'Sucursal'),
              ),
            ),
          SliverList.builder(
            itemCount: w.branches.length,
            itemBuilder: (context, index) {
              final b = w.branches[index],
                  inventory = w.inventory(b.id),
                  issues = inventory
                      .where((i) => i.alerts(c.now).isNotEmpty)
                      .length;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => widget.onOpenBranch(b.id),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  b.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${inventory.length} artículos · $issues con alertas',
                                  style: TextStyle(
                                    color: issues > 0
                                        ? AppColors.orange
                                        : AppColors.teal,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ] else ...[
          sliverBox(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onInventory,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Inventario'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onOrders,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Pedidos'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      editMaster(context, c, 'Producto', branchId: branch.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo artículo'),
                ),
              ],
            ),
          ),
        ],
        sliverBox(
          SectionTitle(
            'Alertas prioritarias',
            subtitle: branch == null
                ? 'Artículos de todas tus tiendas'
                : '${alerts.length} artículos requieren atención',
          ),
        ),
        if (alerts.isEmpty)
          sliverBox(
            const EmptyState(
              'Todo en orden',
              'Aquí aparecerán los productos caducados, próximos a caducar, agotados o con pocas unidades.',
              icon: Icons.check_circle_outline,
            ),
          ),
        SliverList.builder(
          itemCount: alerts.length,
          itemBuilder: (context, index) => ProductTile(
            item: alerts[index],
            now: c.now,
            showBranch: branch == null,
            onTap: () => openProduct(context, c, alerts[index]),
            onCart: c.busy
                ? null
                : () => perform(
                    context,
                    () => c.mutate(
                      () => c.repository.setCart(
                        alerts[index].branchId,
                        alerts[index].id,
                        1,
                        add: true,
                      ),
                    ),
                    success:
                        'Agregado a la lista de ${alerts[index].branchName}.',
                  ),
          ),
        ),
        if (branch != null)
          sliverBox(
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CartPage(controller: c, branchId: branch.id),
                ),
              ),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Ver lista de compra'),
            ),
          ),
      ],
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

class _Indicator extends StatelessWidget {
  const _Indicator(this.value, this.label, this.icon, this.color);
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Icon(icon, color: color, size: 24),
      ],
    ),
  );
}

class PurchaseChartPainter extends CustomPainter {
  PurchaseChartPainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = math.max(1, values.reduce(math.max));
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var y = 0; y < 3; y++) {
      canvas.drawLine(
        Offset(0, y * size.height / 3),
        Offset(size.width, y * size.height / 3),
        grid,
      );
    }
    final slot = size.width / values.length,
        barWidth = math.min(28.0, slot * .55);
    for (var i = 0; i < values.length; i++) {
      final height = values[i] <= 0
          ? 2.0
          : math.max(3.0, values[i] / maxValue * (size.height - 8));
      final rect = Rect.fromLTWH(
        i * slot + (slot - barWidth) / 2,
        size.height - height,
        barWidth,
        height,
      );
      final paint = Paint();
      if (values[i] == maxValue && values[i] > 0) {
        paint.shader = const LinearGradient(
          colors: [Color(0xfff7cc92), Color(0xff21a4a1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect);
      } else {
        paint.color = values[i] > 0 ? const Color(0xffe7e6e2) : AppColors.line;
      }
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PurchaseChartPainter oldDelegate) =>
      oldDelegate.values.toString() != values.toString();
}
