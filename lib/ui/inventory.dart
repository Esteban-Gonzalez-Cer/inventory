import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'forms.dart';
import 'orders.dart';
import 'theme.dart';
import 'widgets.dart';

void openProduct(
  BuildContext context,
  AppController controller,
  InventoryItem item,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ProductDetailsPage(
      controller: controller,
      branchId: item.branchId,
      itemId: item.id,
    ),
  ),
);

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.controller,
    required this.branchId,
  });
  final AppController controller;
  final int branchId;
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final search = SearchController();
  String query = '';
  int? categoryId;
  Set<AlertKind> selectedAlerts = {};
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filters() async {
    var category = categoryId;
    final statuses = {...selectedAlerts};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        minChildSize: .4,
        maxChildSize: .9,
        builder: (context, scroll) => StatefulBuilder(
          builder: (context, update) => AppScroll(
            controller: scroll,
            slivers: [
              sliverBox(
                const SectionTitle('Filtrar inventario'),
                padding: const EdgeInsets.all(20),
              ),
              sliverBox(const SmallLabel('Estado')),
              sliverBox(
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in AlertKind.values)
                      FilterChip(
                        label: Text(kind.label),
                        selected: statuses.contains(kind),
                        onSelected: (value) => update(() {
                          if (value) {
                            statuses.add(kind);
                          } else {
                            statuses.remove(kind);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              sliverBox(const SmallLabel('Categoría')),
              sliverBox(
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todas'),
                      selected: category == null,
                      onSelected: (_) => update(() => category = null),
                    ),
                    for (final c in widget.controller.workspace!.categories)
                      ChoiceChip(
                        label: Text(c.text('name')),
                        selected: category == c.integer('id'),
                        onSelected: (_) =>
                            update(() => category = c.integer('id')),
                      ),
                  ],
                ),
              ),
              sliverBox(
                FilledButton(
                  onPressed: () {
                    setState(() {
                      categoryId = category;
                      selectedAlerts = statuses;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Aplicar filtros'),
                ),
              ),
              sliverBox(
                TextButton(
                  onPressed: () {
                    setState(() {
                      categoryId = null;
                      selectedAlerts = {};
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Limpiar filtros'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        w = c.workspace!,
        all = w.inventory(widget.branchId);
    final items = all
        .where(
          (i) =>
              i.name.toLowerCase().contains(query.toLowerCase()) &&
              (categoryId == null || i.categoryId == categoryId) &&
              (selectedAlerts.isEmpty ||
                  i.alerts(c.now).any(selectedAlerts.contains)),
        )
        .toList();
    return AppScroll(
      slivers: [
        sliverBox(
          SectionTitle(
            'Inventario',
            subtitle: '${all.length} artículos asignados a esta tienda',
          ),
        ),
        sliverBox(
          Row(
            children: [
              Expanded(
                child: SearchAnchor(
                  searchController: search,
                  viewHintText: 'Buscar artículo',
                  viewBuilder: (suggestions) => CustomScrollView(
                    slivers: [SliverList.list(children: suggestions.toList())],
                  ),
                  builder: (context, controller) => SearchBar(
                    controller: controller,
                    hintText: 'Buscar artículo',
                    leading: const Icon(Icons.search, size: 21),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: const WidgetStatePropertyAll(Colors.white),
                    onTap: controller.openView,
                    onChanged: (value) {
                      setState(() => query = value);
                      if (!controller.isOpen) controller.openView();
                    },
                  ),
                  suggestionsBuilder: (context, controller) => all
                      .where(
                        (i) => i.name.toLowerCase().contains(
                          controller.text.toLowerCase(),
                        ),
                      )
                      .map(
                        (item) => ListTile(
                          leading: ProductPicture(item.row, size: 42),
                          title: Text(item.name),
                          subtitle: Text('${item.stock} ${item.unit}'),
                          onTap: () {
                            controller.closeView(item.name);
                            setState(() => query = item.name);
                            openProduct(context, c, item);
                          },
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: IconButton(
                  tooltip: 'Filtros',
                  onPressed: filters,
                  icon: const Icon(Icons.tune),
                ),
              ),
            ],
          ),
        ),
        sliverBox(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => editMaster(
                  context,
                  c,
                  'Producto',
                  branchId: widget.branchId,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo artículo'),
              ),
              OutlinedButton.icon(
                onPressed: () => assignProduct(context, c, widget.branchId),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Del catálogo'),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          sliverBox(
            EmptyState(
              all.isEmpty ? 'Tu inventario comienza aquí' : 'Sin coincidencias',
              all.isEmpty
                  ? 'Agrega un artículo nuevo o selecciona uno del catálogo. Después registra un pedido y su entrega.'
                  : 'Prueba otro nombre o cambia los filtros.',
            ),
          ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) => ProductTile(
            item: items[index],
            now: c.now,
            onTap: () => openProduct(context, c, items[index]),
            onCart: c.busy
                ? null
                : () => perform(
                    context,
                    () => c.mutate(
                      () => c.repository.setCart(
                        widget.branchId,
                        items[index].id,
                        1,
                        add: true,
                      ),
                    ),
                    success: 'Agregado a la lista de compra.',
                  ),
          ),
        ),
      ],
    );
  }
}

class ProductDetailsPage extends StatefulWidget {
  const ProductDetailsPage({
    super.key,
    required this.controller,
    required this.branchId,
    required this.itemId,
  });
  final AppController controller;
  final int branchId, itemId;
  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  bool allHistory = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          w = c.workspace!,
          item = w.items
              .where(
                (i) => i.id == widget.itemId && i.branchId == widget.branchId,
              )
              .firstOrNull;
      if (item == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Artículo')),
          body: const Center(child: Text('El artículo ya no está asignado.')),
        );
      }
      final history = w.purchases
          .where(
            (r) =>
                r.integer('product_id') == item.productId &&
                (allHistory || r.integer('branch_id') == widget.branchId),
          )
          .toList();
      final suppliers = w.purchases
          .where((r) => r.integer('product_id') == item.productId)
          .map((r) => r.text('supplier_name'))
          .toSet();
      final expired = item.alerts(c.now).contains(AlertKind.expired);
      return Scaffold(
        appBar: AppBar(
          title: Text(item.branchName),
          actions: [
            IconButton(
              tooltip: 'Configurar alertas',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProductSettingsPage(controller: c, item: item),
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await editMaster(
                    context,
                    c,
                    'Producto',
                    row: w.products.firstWhere(
                      (p) => p.integer('id') == item.productId,
                    ),
                  );
                }
                if (value == 'remove' &&
                    context.mounted &&
                    await confirm(
                      context,
                      'Quitar de la tienda',
                      'Solo se puede quitar un artículo que no tenga lotes, pedidos, carrito ni historial.',
                    )) {
                  if (!context.mounted) return;
                  final ok = await perform(
                    context,
                    () => c.mutate(
                      () =>
                          c.repository.unassignProduct(item.branchId, item.id),
                    ),
                  );
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Editar datos compartidos'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Quitar de esta tienda'),
                ),
              ],
            ),
          ],
        ),
        body: AppScroll(
          slivers: [
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProductPicture(item.row, size: 86),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SmallLabel(item.category),
                              const SizedBox(height: 6),
                              Text(
                                item.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${item.stock}',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    Text(
                      '${item.unit} · existencias actuales',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    StatusTags(item.alerts(c.now)),
                    const SizedBox(height: 14),
                    Text(
                      'Mínimo ${item.minimum} · Aviso ${item.warningDays} días antes',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (item.row.text('last_supplier').isNotEmpty)
                      Text(
                        'Última compra de esta tienda: ${item.row.text('last_supplier')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: c.busy
                              ? null
                              : () => perform(
                                  context,
                                  () => c.mutate(
                                    () => c.repository.setCart(
                                      item.branchId,
                                      item.id,
                                      1,
                                      add: true,
                                    ),
                                  ),
                                  success: 'Agregado al carrito.',
                                ),
                          icon: const Icon(
                            Icons.add_shopping_cart_outlined,
                            size: 18,
                          ),
                          label: const Text('Agregar al carrito'),
                        ),
                        OutlinedButton.icon(
                          onPressed: item.stock == 0 || expired
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockActionPage(
                                      controller: c,
                                      itemId: item.id,
                                      branchId: item.branchId,
                                    ),
                                  ),
                                ),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Consumir'),
                        ),
                      ],
                    ),
                    if (expired) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Descarta los lotes caducados antes de consumir las unidades restantes.',
                        style: TextStyle(color: AppColors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            sliverBox(
              const SectionTitle(
                'Lotes',
                subtitle: 'La fecha más cercana se consume primero',
              ),
            ),
            if (item.lots.isEmpty)
              sliverBox(
                const EmptyState(
                  'Todavía no hay lotes',
                  'Crea un pedido y registra una entrega para agregar existencias.',
                ),
              ),
            SliverList.list(
              children: [
                for (final lot in item.lots)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lot.reference,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                '${lot.quantity} ${item.unit}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lot.expiry == null
                                ? 'Sin caducidad'
                                : 'Caducidad: ${shortDate(lot.expiry!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (lot.quantity > 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockActionPage(
                                      controller: c,
                                      itemId: item.id,
                                      branchId: item.branchId,
                                      lotId: lot.id,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                label: const Text('Descartar'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SmallLabel('Dónde se ha comprado este producto'),
                    const SizedBox(height: 10),
                    suppliers.isEmpty
                        ? const Text('Sin compras registradas.')
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: suppliers
                                .map(
                                  (s) => Chip(
                                    label: Text(s),
                                    avatar: const Icon(
                                      Icons.store_outlined,
                                      size: 16,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ],
                ),
              ),
            ),
            sliverBox(const SectionTitle('Historial de compras')),
            sliverBox(
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Esta tienda')),
                  ButtonSegment(value: true, label: Text('Todas las tiendas')),
                ],
                selected: {allHistory},
                onSelectionChanged: (v) =>
                    setState(() => allHistory = v.single),
              ),
            ),
            if (history.isEmpty)
              sliverBox(
                const EmptyState(
                  'Sin compras en esta vista',
                  'Aquí podrás consultar cada proveedor, precio y lote recibido.',
                ),
              ),
            SliverList.list(
              children: [
                for (final r in history)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(r.text('supplier_name')),
                        subtitle: Text(
                          '${r.text('branch_name')} · ${dateTimeLabel(r.text('created_at'))}\nC-${r.integer('id')} / RC-${r.integer('receipt_id')} / L-${r.integer('lot_id')}\n${r.integer('quantity')} ${r.text('unit')} · ${money(r.integer('unit_cost'))} c/u',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailsPage(
                              controller: c,
                              branchId: r.integer('branch_id'),
                              orderId: r.integer('order_id'),
                            ),
                          ),
                        ),
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
