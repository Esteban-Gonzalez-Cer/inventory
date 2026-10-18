import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'orders.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller, this.branchId});
  final AppController controller;
  final int? branchId;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? kind;
  @override
  Widget build(BuildContext context) {
    final w = widget.controller.workspace!;
    final records =
        <DbRow>[
              for (final r in w.scoped(w.purchases, widget.branchId))
                {...r, 'history_type': 'purchase'},
              for (final r
                  in w
                      .scoped(w.movements, widget.branchId)
                      .where((r) => r.text('kind') != 'receipt'))
                {...r, 'history_type': r.text('kind')},
              for (final r in w.scoped(w.events, widget.branchId))
                {...r, 'history_type': 'event'},
            ]
            .where((r) => kind == null || r.text('history_type') == kind)
            .toList()
          ..sort(
            (a, b) => b.text('created_at').compareTo(a.text('created_at')),
          );
    final discards = w
        .scoped(w.movements, widget.branchId)
        .where((m) => m.text('kind') == 'discard')
        .fold(0, (sum, m) => sum + m.integer('quantity'));
    return AppScroll(
      slivers: [
        sliverBox(
          const SectionTitle(
            'Historial',
            subtitle: 'Cada entrada, consumo y descarte queda registrado',
          ),
        ),
        sliverBox(
          Panel(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.recycling_outlined,
                    color: AppColors.orange,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$discards unidades descartadas',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'Registro de desperdicio · todo el historial',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        sliverBox(
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in <String?, String>{
                null: 'Todo',
                'purchase': 'Compras',
                'consume': 'Consumos',
                'discard': 'Descartes',
                'event': 'Pedidos',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: kind == entry.key,
                  onSelected: (_) => setState(() => kind = entry.key),
                ),
            ],
          ),
        ),
        if (records.isEmpty)
          sliverBox(
            const EmptyState(
              'Tu historial está listo',
              'Las operaciones confirmadas aparecerán aquí con sus referencias.',
              icon: Icons.history,
            ),
          ),
        SliverList.builder(
          itemCount: records.length,
          itemBuilder: (context, index) {
            final r = records[index], type = r.text('history_type');
            final color = type == 'discard'
                ? AppColors.orange
                : type == 'consume'
                ? AppColors.ink
                : AppColors.teal;
            final icon = type == 'purchase'
                ? Icons.local_shipping_outlined
                : type == 'consume'
                ? Icons.remove_circle_outline
                : type == 'discard'
                ? Icons.recycling_outlined
                : Icons.receipt_long_outlined;
            final label = type == 'purchase'
                ? 'Compra recibida'
                : type == 'consume'
                ? 'Consumo'
                : type == 'discard'
                ? 'Descarte'
                : r.text('kind') == 'edited'
                ? 'Borrador editado'
                : orderStatus(r.text('kind'));
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsPage(
                        controller: widget.controller,
                        branchId: r.integer('branch_id'),
                        orderId: r.integer('order_id'),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (type == 'purchase')
                              Text(
                                money(
                                  r.integer('quantity') *
                                      r.integer('unit_cost'),
                                ),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          type == 'event'
                              ? 'OC-${r.integer('order_id')} · ${r.text('supplier_name')}'
                              : r.text('product_name'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${r.text('branch_name')} · ${dateTimeLabel(r.text('created_at'))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (type != 'event')
                          Text(
                            '${r.integer('quantity')} ${r.text('unit')} · L-${r.integer('lot_id')} · OC-${r.integer('order_id')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (type == 'purchase')
                          Text(
                            '${r.text('supplier_name')} · RC-${r.integer('receipt_id')} / C-${r.integer('id')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (r.text('reason').isNotEmpty)
                          Text(
                            r.text('reason'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (r.text('note').isNotEmpty)
                          Text(
                            r.text('note'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
