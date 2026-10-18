import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> openDraft(
  BuildContext context,
  AppController controller,
  int branchId, {
  int? orderId,
}) async {
  final id = await Navigator.push<int>(
    context,
    MaterialPageRoute(
      builder: (_) => DraftPage(
        controller: controller,
        branchId: branchId,
        orderId: orderId,
      ),
    ),
  );
  if (id != null && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsPage(
          controller: controller,
          branchId: branchId,
          orderId: id,
        ),
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  const CartPage({super.key, required this.controller, this.branchId});
  final AppController controller;
  final int? branchId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final w = controller.workspace!;
      final groups = w.branches
          .where(
            (b) =>
                (branchId == null || b.id == branchId) &&
                w.cart.any((c) => c.integer('branch_id') == b.id),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Lista de compra')),
        body: AppScroll(
          slivers: [
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SmallLabel('Tu próxima reposición'),
                    const SizedBox(height: 8),
                    Text(
                      '${w.scoped(w.cart, branchId).length} artículos',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Al enviar un pedido se retiran sus cantidades de esta lista. Las existencias aumentan al recibirlo.',
                    ),
                  ],
                ),
              ),
            ),
            if (groups.isEmpty)
              sliverBox(
                const EmptyState(
                  'El carrito está vacío',
                  'Agrega artículos desde el inventario o desde las alertas.',
                  icon: Icons.shopping_bag_outlined,
                ),
              ),
            for (final branch in groups) ...[
              sliverBox(
                SectionTitle(
                  branch.name,
                  action: 'Crear pedido',
                  onAction: () => openDraft(context, controller, branch.id),
                ),
              ),
              SliverList.list(
                children: [
                  for (final cart in w.scoped(w.cart, branch.id))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Panel(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ProductPicture(
                              w.item(cart.integer('branch_product_id')).row,
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    w
                                        .item(cart.integer('branch_product_id'))
                                        .name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    '${cart.integer('quantity')} ${w.item(cart.integer('branch_product_id')).unit}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Quitar una unidad',
                              onPressed: controller.busy
                                  ? null
                                  : () => perform(
                                      context,
                                      () => controller.mutate(
                                        () => controller.repository.setCart(
                                          branch.id,
                                          cart.integer('branch_product_id'),
                                          cart.integer('quantity') - 1,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 22,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Agregar una unidad',
                              onPressed: controller.busy
                                  ? null
                                  : () => perform(
                                      context,
                                      () => controller.mutate(
                                        () => controller.repository.setCart(
                                          branch.id,
                                          cart.integer('branch_product_id'),
                                          1,
                                          add: true,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 22,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar del carrito',
                              onPressed: controller.busy
                                  ? null
                                  : () => perform(
                                      context,
                                      () => controller.mutate(
                                        () => controller.repository.setCart(
                                          branch.id,
                                          cart.integer('branch_product_id'),
                                          0,
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({
    super.key,
    required this.controller,
    required this.branchId,
  });
  final AppController controller;
  final int branchId;
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String? status;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, w = c.workspace!;
    final orders = w
        .scoped(w.orders, widget.branchId)
        .where((o) => status == null || o.text('status') == status)
        .toList();
    return AppScroll(
      slivers: [
        sliverBox(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedidos',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => openDraft(context, c, widget.branchId),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
              ),
            ],
          ),
        ),
        sliverBox(
          Panel(
            child: Row(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${w.scoped(w.cart, widget.branchId).length} artículos en tu lista de compra',
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CartPage(controller: c, branchId: widget.branchId),
                    ),
                  ),
                  child: const Text('Ver lista'),
                ),
              ],
            ),
          ),
        ),
        sliverBox(
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              for (final s in [
                'draft',
                'ordered',
                'partial',
                'received',
                'cancelled',
              ])
                ChoiceChip(
                  label: Text(orderStatus(s)),
                  selected: status == s,
                  onSelected: (_) => setState(() => status = s),
                ),
            ],
          ),
        ),
        if (orders.isEmpty)
          sliverBox(
            const EmptyState(
              'Sin pedidos en esta vista',
              'Crea un borrador con los artículos que quieras reponer.',
              icon: Icons.receipt_long_outlined,
            ),
          ),
        SliverList.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            final lines = w.lines
                .where((l) => l.integer('order_id') == order.integer('id'))
                .toList();
            final total = lines.fold(
              0,
              (sum, l) => sum + l.integer('quantity') * l.integer('unit_cost'),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailsPage(
                        controller: c,
                        branchId: widget.branchId,
                        orderId: order.integer('id'),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'OC-${order.integer('id').toString().padLeft(5, '0')}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _OrderTag(order.text('status')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          order.text('supplier_name'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateTimeLabel(order.text('created_at')),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${lines.length} artículos · solicitado',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              money(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
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

class _OrderTag extends StatelessWidget {
  const _OrderTag(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'received'
        ? AppColors.teal
        : status == 'cancelled'
        ? AppColors.red
        : status == 'draft'
        ? AppColors.muted
        : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        orderStatus(status),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class DraftFields {
  DraftFields(this.itemId, int quantity, int cents)
    : quantity = TextEditingController(text: '$quantity'),
      cost = TextEditingController(text: (cents / 100).toStringAsFixed(2));
  final int itemId;
  final TextEditingController quantity, cost;
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class DraftPage extends StatefulWidget {
  const DraftPage({
    super.key,
    required this.controller,
    required this.branchId,
    this.orderId,
  });
  final AppController controller;
  final int branchId;
  final int? orderId;
  @override
  State<DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<DraftPage> {
  final fields = <DraftFields>[];
  final removedFields = <DraftFields>[];
  int? supplierId;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final w = widget.controller.workspace!;
    if (widget.orderId != null) {
      final order = w.orders.firstWhere(
        (o) => o.integer('id') == widget.orderId,
      );
      supplierId = order.integer('supplier_id');
      for (final line in w.lines.where(
        (l) => l.integer('order_id') == widget.orderId,
      )) {
        fields.add(
          DraftFields(
            line.integer('branch_product_id'),
            line.integer('quantity'),
            line.integer('unit_cost'),
          ),
        );
      }
    } else {
      for (final cart in w.scoped(w.cart, widget.branchId)) {
        fields.add(
          DraftFields(
            cart.integer('branch_product_id'),
            cart.integer('quantity'),
            0,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final f in [...fields, ...removedFields]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> add() async {
    final items = widget.controller.workspace!
        .inventory(widget.branchId)
        .where((i) => !fields.any((f) => f.itemId == i.id))
        .toList();
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .7,
        child: AppScroll(
          slivers: [
            sliverBox(
              const SectionTitle('Agregar artículo'),
              padding: const EdgeInsets.all(20),
            ),
            if (items.isEmpty)
              sliverBox(
                const EmptyState(
                  'No hay más artículos disponibles',
                  'Asigna artículos a esta tienda desde Inventario.',
                ),
              ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => ListTile(
                leading: ProductPicture(items[index].row, size: 44),
                title: Text(items[index].name),
                onTap: () => Navigator.pop(context, items[index].id),
              ),
            ),
          ],
        ),
      ),
    );
    if (id != null && mounted) {
      setState(() => fields.add(DraftFields(id, 1, 0)));
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (supplierId == null) {
        throw const AppFailure('Selecciona un proveedor.');
      }
      final lines = <({int itemId, int quantity, int unitCost})>[];
      for (final f in fields) {
        final quantity = int.tryParse(f.quantity.text),
            cost = parseCents(f.cost.text);
        if (quantity == null || quantity <= 0 || cost == null) {
          throw const AppFailure(
            'Revisa la cantidad y el precio de cada artículo.',
          );
        }
        lines.add((itemId: f.itemId, quantity: quantity, unitCost: cost));
      }
      final id = await widget.controller.mutate(
        () => widget.controller.repository.saveDraft(
          widget.branchId,
          supplierId!,
          lines,
          orderId: widget.orderId,
        ),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => error = humanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final w = widget.controller.workspace!;
      return PopScope(
        canPop: !saving,
        child: Scaffold(
          appBar: AppBar(title: const Text('Borrador de pedido')),
          body: AbsorbPointer(
            absorbing: saving,
            child: AppScroll(
              slivers: [
                sliverBox(
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmallLabel(w.branch(widget.branchId).name),
                        const SizedBox(height: 16),
                        if (w.suppliers.isNotEmpty)
                          DropdownButtonFormField<int>(
                            key: ValueKey(supplierId),
                            initialValue: supplierId,
                            decoration: const InputDecoration(
                              labelText: 'Proveedor',
                            ),
                            items: w.suppliers
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s.integer('id'),
                                    child: Text(s.text('name')),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => supplierId = v),
                          ),
                        TextButton.icon(
                          onPressed: () async {
                            final id = await editMaster(
                              context,
                              widget.controller,
                              'Tienda',
                            );
                            if (id != null && mounted) {
                              setState(() => supplierId = id);
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Registrar proveedor'),
                        ),
                        const Text(
                          'El precio solicitado se puede ajustar al recibir. Un borrador no modifica existencias.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                sliverBox(
                  SectionTitle('Artículos', action: 'Agregar', onAction: add),
                ),
                if (fields.isEmpty)
                  sliverBox(
                    EmptyState(
                      'Elige los artículos',
                      'Puedes agregar productos asignados a esta tienda.',
                      action: 'Agregar artículo',
                      onAction: add,
                    ),
                  ),
                SliverList.builder(
                  itemCount: fields.length,
                  itemBuilder: (context, index) {
                    final f = fields[index], item = w.item(f.itemId);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Panel(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ProductPicture(item.row, size: 44),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Quitar del pedido',
                                  onPressed: () {
                                    setState(() {
                                      removedFields.add(fields.removeAt(index));
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: f.quantity,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Cantidad (${item.unit})',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: f.cost,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Precio unitario MXN',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (error != null)
                  sliverBox(
                    Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
                sliverBox(
                  FilledButton.icon(
                    onPressed: saving ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar borrador'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class OrderDetailsPage extends StatelessWidget {
  const OrderDetailsPage({
    super.key,
    required this.controller,
    required this.branchId,
    required this.orderId,
  });
  final AppController controller;
  final int branchId, orderId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final w = controller.workspace!,
          order = w.orders
              .where(
                (o) =>
                    o.integer('id') == orderId &&
                    o.integer('branch_id') == branchId,
              )
              .firstOrNull;
      if (order == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Pedido')),
          body: const Center(child: Text('Este borrador ya no existe.')),
        );
      }
      final lines = w.lines
          .where((l) => l.integer('order_id') == orderId)
          .toList();
      final purchases = w.purchases
          .where((r) => r.integer('order_id') == orderId)
          .toList();
      final status = order.text('status');
      return Scaffold(
        appBar: AppBar(title: Text('OC-${orderId.toString().padLeft(5, '0')}')),
        body: AppScroll(
          slivers: [
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrderTag(status),
                    const SizedBox(height: 12),
                    Text(
                      order.text('supplier_name'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      order.text('branch_name'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateTimeLabel(order.text('created_at')),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (status == 'draft') ...[
                          FilledButton.icon(
                            onPressed: controller.busy
                                ? null
                                : () => perform(
                                    context,
                                    () => controller.mutate(
                                      () => controller.repository.submitOrder(
                                        branchId,
                                        orderId,
                                      ),
                                    ),
                                    success: 'Pedido enviado. Las existencias cambiarán al recibirlo.',
                                  ),
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Enviar pedido'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DraftPage(
                                  controller: controller,
                                  branchId: branchId,
                                  orderId: orderId,
                                ),
                              ),
                            ),
                            child: const Text('Editar'),
                          ),
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    if (await confirm(
                                      context,
                                      'Eliminar borrador',
                                      'Se eliminarán este borrador y sus artículos.',
                                    )) {
                                      if (!context.mounted) return;
                                      final ok = await perform(
                                        context,
                                        () => controller.mutate(
                                          () => controller.repository
                                              .deleteDraft(branchId, orderId),
                                        ),
                                      );
                                      if (ok && context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    }
                                  },
                            child: const Text('Eliminar'),
                          ),
                        ],
                        if (status == 'ordered' || status == 'partial')
                          FilledButton.icon(
                            onPressed: controller.busy
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReceiptPage(
                                        controller: controller,
                                        branchId: branchId,
                                        orderId: orderId,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                            ),
                            label: const Text('Registrar entrega'),
                          ),
                        if ({'draft', 'ordered', 'partial'}.contains(status))
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    final reason = await requestReason(context);
                                    if (reason != null && context.mounted) {
                                      await perform(
                                        context,
                                        () => controller.mutate(
                                          () =>
                                              controller.repository.cancelOrder(
                                                branchId,
                                                orderId,
                                                reason,
                                              ),
                                        ),
                                        success: 'Se cancelaron las cantidades pendientes.',
                                      );
                                    }
                                  },
                            child: const Text('Cancelar pendientes'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            sliverBox(
              const SectionTitle(
                'Artículos del pedido',
                subtitle: 'Solicitado / recibido / pendiente',
              ),
            ),
            SliverList.list(
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.text('product_name'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${line.integer('quantity')} / ${w.receivedQuantity(line.integer('id'))} / ${status == 'cancelled' ? 'cancelado' : line.integer('quantity') - w.receivedQuantity(line.integer('id'))} ${line.text('unit')}',
                          ),
                          Text(
                            '${money(line.integer('unit_cost'))} por unidad solicitado',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            sliverBox(const SectionTitle('Compras recibidas')),
            if (purchases.isEmpty)
              sliverBox(
                const EmptyState(
                  'Todavía no hay recepciones',
                  'Las entregas confirmadas aparecerán aquí.',
                  icon: Icons.local_shipping_outlined,
                ),
              ),
            SliverList.list(
              children: [
                for (final r in purchases)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r.text('product_name')} · ${r.integer('quantity')} ${r.text('unit')}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'RC-${r.integer('receipt_id')} / C-${r.integer('id')} / L-${r.integer('lot_id')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '${r['expiry_date'] ?? 'Sin caducidad'} · ${money(r.integer('quantity') * r.integer('unit_cost'))}',
                          ),
                          Text(
                            dateTimeLabel(r.text('created_at')),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            sliverBox(const SectionTitle('Trazabilidad del pedido')),
            SliverList.list(
              children: [
                for (final e in w.events.where(
                  (e) => e.integer('order_id') == orderId,
                ))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.text('kind') == 'edited'
                                ? 'Borrador editado'
                                : orderStatus(e.text('kind')),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            dateTimeLabel(e.text('created_at')),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (e.text('note').isNotEmpty) Text(e.text('note')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<String?> requestReason(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _CancellationDialog(),
);

class _CancellationDialog extends StatefulWidget {
  const _CancellationDialog();
  @override
  State<_CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<_CancellationDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancelar pendientes'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Las recepciones anteriores y sus existencias se conservan.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Motivo'),
          maxLines: 3,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, reason.text.trim()),
        child: const Text('Confirmar'),
      ),
    ],
  );
}

class ReceiptFields {
  ReceiptFields(this.line)
    : quantity = TextEditingController(text: '0'),
      cost = TextEditingController(
        text: (line.integer('unit_cost') / 100).toStringAsFixed(2),
      );
  final DbRow line;
  final TextEditingController quantity, cost;
  DateTime? expiry;
  bool noExpiry = false;
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class ReceiptPage extends StatefulWidget {
  const ReceiptPage({
    super.key,
    required this.controller,
    required this.branchId,
    required this.orderId,
  });
  final AppController controller;
  final int branchId, orderId;
  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final operationId = const Uuid().v4();
  final fields = <ReceiptFields>[];
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final w = widget.controller.workspace!;
    for (final line in w.lines.where(
      (l) =>
          l.integer('order_id') == widget.orderId &&
          l.integer('quantity') > w.receivedQuantity(l.integer('id')),
    )) {
      fields.add(
        ReceiptFields(line)
          ..quantity.text =
              '${line.integer('quantity') - w.receivedQuantity(line.integer('id'))}',
      );
    }
  }

  @override
  void dispose() {
    for (final f in fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final deliveries = <ReceiptLine>[];
      for (final f in fields) {
        final quantity = int.tryParse(f.quantity.text);
        if (quantity == null || quantity < 0) {
          throw const AppFailure('Captura cantidades válidas.');
        }
        if (quantity == 0) continue;
        final cost = parseCents(f.cost.text);
        if (cost == null) throw const AppFailure('Revisa el precio unitario.');
        if (!f.noExpiry && f.expiry == null) {
          throw const AppFailure(
            'Selecciona la fecha de caducidad o indica Sin caducidad para cada lote recibido.',
          );
        }
        deliveries.add(
          ReceiptLine(
            orderLineId: f.line.integer('id'),
            quantity: quantity,
            unitCost: cost,
            expiry: f.noExpiry ? null : f.expiry,
          ),
        );
      }
      await widget.controller.mutate(
        () => widget.controller.repository.receive(
          widget.branchId,
          widget.orderId,
          operationId,
          deliveries,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = humanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.controller.workspace!;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(title: Text('Entrega de OC-${widget.orderId}')),
        body: AbsorbPointer(
          absorbing: saving,
          child: AppScroll(
            slivers: [
              sliverBox(
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SmallLabel(w.branch(widget.branchId).name),
                      const SizedBox(height: 8),
                      const Text(
                        'Cada fecha, un lote',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Captura lo recibido hoy. Usa cero en los artículos pendientes. Para distintas caducidades, reparte la cantidad entre varios lotes.',
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: fields.length,
                itemBuilder: (context, index) {
                  final f = fields[index];
                  final pending =
                      f.line.integer('quantity') -
                      w.receivedQuantity(f.line.integer('id'));
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.line.text('product_name'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '$pending ${f.line.text('unit')} pendientes en total',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: f.quantity,
                                  decoration: const InputDecoration(
                                    labelText: 'Recibido en este lote',
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: f.cost,
                                  decoration: const InputDecoration(
                                    labelText: 'Precio real MXN',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Sin caducidad'),
                            value: f.noExpiry,
                            onChanged: (v) => setState(() => f.noExpiry = v),
                          ),
                          if (!f.noExpiry)
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      f.expiry ?? widget.controller.now,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2200),
                                );
                                if (picked != null && mounted) {
                                  setState(() => f.expiry = picked);
                                }
                              },
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(
                                f.expiry == null
                                    ? 'Seleccionar caducidad'
                                    : shortDate(f.expiry!),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => setState(
                              () => fields.add(ReceiptFields(f.line)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Otro lote del mismo artículo'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (error != null)
                sliverBox(
                  Text(error!, style: const TextStyle(color: AppColors.red)),
                ),
              sliverBox(
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar recepción'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
