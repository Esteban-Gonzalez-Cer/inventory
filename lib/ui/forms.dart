import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'map_view.dart';
import 'theme.dart';
import 'widgets.dart';

String masterTitle(String table) => switch (table) {
  'Sucursal' => 'Tienda',
  'Tienda' => 'Proveedor',
  'Categoria' => 'Categoría',
  _ => 'Artículo',
};

Future<int?> editMaster(
  BuildContext context,
  AppController controller,
  String table, {
  DbRow? row,
  int? branchId,
}) => Navigator.push<int>(
  context,
  MaterialPageRoute(
    builder: (_) => MasterEditor(
      controller: controller,
      table: table,
      row: row,
      branchId: branchId,
    ),
  ),
);

class MasterEditor extends StatefulWidget {
  const MasterEditor({
    super.key,
    required this.controller,
    required this.table,
    this.row,
    this.branchId,
  });
  final AppController controller;
  final String table;
  final DbRow? row;
  final int? branchId;
  @override
  State<MasterEditor> createState() => _MasterEditorState();
}

class _MasterEditorState extends State<MasterEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController name, address, latitude, longitude, unit;
  int? categoryId;
  String imageAsset = 'assets/products/grocery.svg';
  String? imagePath;
  XFile? photo;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final row = widget.row ?? {};
    name = TextEditingController(text: row.text('name'));
    address = TextEditingController(text: row.text('address'));
    latitude = TextEditingController(text: row['latitude']?.toString() ?? '');
    longitude = TextEditingController(text: row['longitude']?.toString() ?? '');
    unit = TextEditingController(
      text: row.text('unit').isEmpty ? 'pieza' : row.text('unit'),
    );
    categoryId = row['category_id'] as int?;
    imagePath = row['image_path'] as String?;
    if (row.text('image_asset').isNotEmpty) {
      imageAsset = row.text('image_asset');
    }
  }

  @override
  void dispose() {
    for (final c in [name, address, latitude, longitude, unit]) {
      c.dispose();
    }
    super.dispose();
  }

  String? requiredText(String? value) => value == null || value.trim().isEmpty
      ? 'Este dato es obligatorio.'
      : null;
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final values = <String, Object?>{'name': name.text.trim()};
      if (widget.table == 'Sucursal') {
        values.addAll({
          'address': address.text.trim(),
          'latitude': double.parse(latitude.text),
          'longitude': double.parse(longitude.text),
        });
      }
      if (widget.table == 'Tienda') values['address'] = address.text.trim();
      if (widget.table == 'Producto') {
        final categories = widget.controller.workspace!.categories;
        if (categories.isEmpty) {
          throw const AppFailure('Registra una categoría antes de guardar.');
        }
        if (photo != null) {
          final dir = Directory(
            p.join((await getApplicationDocumentsDirectory()).path, 'imagenes'),
          );
          await dir.create(recursive: true);
          final destination = p.join(
            dir.path,
            '${const Uuid().v4()}${p.extension(photo!.path).isEmpty ? '.jpg' : p.extension(photo!.path)}',
          );
          await photo!.saveTo(destination);
          imagePath = destination;
          photo = null;
        }
        values.addAll({
          'category_id': categoryId ?? categories.first.integer('id'),
          'unit': unit.text.trim(),
          'image_path': imagePath,
          'image_asset': imageAsset,
        });
      }
      final id = await widget.controller.mutate(
        () => widget.table == 'Producto' && widget.row == null
            ? widget.controller.repository.createProduct(
                values,
                branchId: widget.branchId,
              )
            : widget.controller.repository.saveMaster(
                widget.table,
                values,
                id: widget.row?.integer('id'),
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
      final categories = widget.controller.workspace!.categories;
      return PopScope(
        canPop: !saving,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${widget.row == null ? 'Agregar' : 'Editar'} ${masterTitle(widget.table).toLowerCase()}',
            ),
          ),
          body: Form(
            key: form,
            child: AppScroll(
              slivers: [
                sliverBox(
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SmallLabel(
                          widget.table == 'Producto'
                              ? 'Catálogo compartido'
                              : widget.table == 'Sucursal'
                              ? 'Tu red de tiendas'
                              : 'Datos del registro',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                          validator: requiredText,
                          maxLength: widget.table == 'Producto' ? 120 : 100,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        if (widget.table == 'Sucursal' ||
                            widget.table == 'Tienda') ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: address,
                            decoration: InputDecoration(
                              labelText: widget.table == 'Sucursal'
                                  ? 'Dirección'
                                  : 'Dirección (opcional)',
                            ),
                            validator: widget.table == 'Sucursal'
                                ? requiredText
                                : null,
                            maxLines: 2,
                          ),
                        ],
                        if (widget.table == 'Sucursal') ...[
                          const SizedBox(height: 18),
                          const Text(
                            'Ubicación',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: latitude,
                                  decoration: const InputDecoration(
                                    labelText: 'Latitud',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  validator: (v) {
                                    final n = double.tryParse(v ?? '');
                                    return n == null ||
                                            !n.isFinite ||
                                            n.abs() > 90
                                        ? 'Entre -90 y 90'
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: longitude,
                                  decoration: const InputDecoration(
                                    labelText: 'Longitud',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  validator: (v) {
                                    final n = double.tryParse(v ?? '');
                                    return n == null ||
                                            !n.isFinite ||
                                            n.abs() > 180
                                        ? 'Entre -180 y 180'
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final lat = double.tryParse(latitude.text),
                                  lng = double.tryParse(longitude.text);
                              final initial =
                                  lat != null &&
                                      lng != null &&
                                      lat.isFinite &&
                                      lng.isFinite &&
                                      lat.abs() <= 90 &&
                                      lng.abs() <= 180
                                  ? LatLng(lat, lng)
                                  : null;
                              final point = await Navigator.push<LatLng>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      LocationPickerPage(initial: initial),
                                ),
                              );
                              if (point != null && mounted) {
                                setState(() {
                                  latitude.text = point.latitude
                                      .toStringAsFixed(6);
                                  longitude.text = point.longitude
                                      .toStringAsFixed(6);
                                });
                              }
                            },
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Elegir ubicación en el mapa'),
                          ),
                        ],
                        if (widget.table == 'Producto') ...[
                          const SizedBox(height: 12),
                          if (categories.isNotEmpty)
                            DropdownButtonFormField<int>(
                              key: ValueKey(
                                categoryId ?? categories.first.integer('id'),
                              ),
                              initialValue:
                                  categoryId ?? categories.first.integer('id'),
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                              ),
                              items: categories
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.integer('id'),
                                      child: Text(c.text('name')),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => categoryId = v),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              final id = await editMaster(
                                context,
                                widget.controller,
                                'Categoria',
                              );
                              if (mounted && id != null) {
                                setState(() => categoryId = id);
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Nueva categoría'),
                          ),
                          TextFormField(
                            controller: unit,
                            decoration: const InputDecoration(
                              labelText: 'Unidad (pieza, cartón, paquete…)',
                            ),
                            validator: requiredText,
                            maxLength: 30,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Imagen del artículo',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (var i = 0; i < productAssets.length; i++)
                                Semantics(
                                  label: productAssetLabels[i],
                                  button: true,
                                  selected:
                                      imageAsset.endsWith(
                                        '${productAssets[i]}.svg',
                                      ) &&
                                      imagePath == null,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      imageAsset =
                                          'assets/products/${productAssets[i]}.svg';
                                      imagePath = null;
                                      photo = null;
                                    }),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color:
                                              imageAsset.endsWith(
                                                    '${productAssets[i]}.svg',
                                                  ) &&
                                                  imagePath == null
                                              ? AppColors.orange
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: ProductPicture({
                                        'image_asset':
                                            'assets/products/${productAssets[i]}.svg',
                                      }),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (photo != null || imagePath != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Image.file(
                                File(photo?.path ?? imagePath!),
                                height: 100,
                                width: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, s) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final source in [
                                ImageSource.gallery,
                                ImageSource.camera,
                              ])
                                OutlinedButton.icon(
                                  onPressed: () => perform(context, () async {
                                    final selected = await ImagePicker()
                                        .pickImage(
                                          source: source,
                                          maxWidth: 1000,
                                          imageQuality: 85,
                                        );
                                    if (selected != null && mounted) {
                                      setState(() => photo = selected);
                                    }
                                    return null;
                                  }),
                                  icon: Icon(
                                    source == ImageSource.gallery
                                        ? Icons.photo_library_outlined
                                        : Icons.camera_alt_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    source == ImageSource.gallery
                                        ? 'Galería'
                                        : 'Cámara',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.row == null && widget.branchId != null
                                ? 'Se asignará a esta tienda con existencias en cero. Registra una recepción para agregar stock.'
                                : 'Los cambios de nombre, imagen y categoría se comparten entre tiendas.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  sliverBox(
                    Text(error!, style: const TextStyle(color: AppColors.red)),
                  ),
                sliverBox(
                  FilledButton.icon(
                    onPressed: saving || widget.controller.busy ? null : save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Guardar'),
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

Future<void> assignProduct(
  BuildContext context,
  AppController controller,
  int branchId,
) async {
  final w = controller.workspace!;
  final assigned = w.inventory(branchId).map((i) => i.productId).toSet();
  final products = w.products
      .where((p) => !assigned.contains(p.integer('id')))
      .toList();
  final id = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .75,
      child: AppScroll(
        slivers: [
          sliverBox(
            const SectionTitle('Agregar del catálogo'),
            padding: const EdgeInsets.all(20),
          ),
          if (products.isEmpty)
            sliverBox(
              const EmptyState(
                'No hay artículos por asignar',
                'Crea un artículo nuevo o revisa el catálogo compartido.',
              ),
            ),
          SliverList.builder(
            itemCount: products.length,
            itemBuilder: (context, index) => ListTile(
              leading: ProductPicture(products[index], size: 46),
              title: Text(products[index].text('name')),
              subtitle: Text(products[index].text('category_name')),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () =>
                  Navigator.pop(context, products[index].integer('id')),
            ),
          ),
        ],
      ),
    ),
  );
  if (id != null && context.mounted) {
    await perform(
      context,
      () => controller.mutate(
        () => controller.repository.assignProduct(branchId, id),
      ),
      success: 'Artículo asignado a la tienda.',
    );
  }
}

class ProductSettingsPage extends StatefulWidget {
  const ProductSettingsPage({
    super.key,
    required this.controller,
    required this.item,
  });
  final AppController controller;
  final InventoryItem item;
  @override
  State<ProductSettingsPage> createState() => _ProductSettingsPageState();
}

class _ProductSettingsPageState extends State<ProductSettingsPage> {
  late final minimum = TextEditingController(text: '${widget.item.minimum}');
  late final days = TextEditingController(text: '${widget.item.warningDays}');
  late bool reminders = widget.item.row.integer('reminders') == 1;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    minimum.dispose();
    days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alertas del artículo')),
    body: AppScroll(
      slivers: [
        sliverBox(
          Panel(
            child: Column(
              children: [
                Text(
                  widget.item.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  widget.item.branchName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Avisar con estas unidades o menos',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Días de anticipación a la caducidad',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recordatorios de caducidad'),
                  value: reminders,
                  onChanged: (v) => setState(() => reminders = v),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          sliverBox(Text(error!, style: const TextStyle(color: AppColors.red))),
        sliverBox(
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await widget.controller.mutate(
                        () => widget.controller.repository.configureProduct(
                          widget.item.branchId,
                          widget.item.id,
                          minimum: int.tryParse(minimum.text) ?? -1,
                          warningDays: int.tryParse(days.text) ?? -1,
                          reminders: reminders,
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => error = humanError(e));
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            child: const Text('Guardar configuración'),
          ),
        ),
      ],
    ),
  );
}

class StockActionPage extends StatefulWidget {
  const StockActionPage({
    super.key,
    required this.controller,
    required this.itemId,
    required this.branchId,
    this.lotId,
  });
  final AppController controller;
  final int itemId, branchId;
  final int? lotId;
  @override
  State<StockActionPage> createState() => _StockActionPageState();
}

class _StockActionPageState extends State<StockActionPage> {
  final quantity = TextEditingController(text: '1'),
      reason = TextEditingController(text: 'Caducidad');
  bool saving = false;
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.controller.workspace!.item(widget.itemId);
    final discard = widget.lotId != null;
    final lots = [...item.lots.where((l) => l.quantity > 0)]
      ..sort((a, b) {
        if (a.expiry == null) {
          return b.expiry == null ? a.id.compareTo(b.id) : 1;
        }
        if (b.expiry == null) return -1;
        final dates = a.expiry!.compareTo(b.expiry!);
        return dates == 0 ? a.id.compareTo(b.id) : dates;
      });
    var left = int.tryParse(quantity.text) ?? 0;
    final preview = <String>[];
    for (final lot in lots) {
      if (left <= 0) break;
      final used = math.min(left, lot.quantity);
      preview.add(
        '${lot.reference}: $used ${item.unit} · ${lot.expiry == null ? 'Sin caducidad' : shortDate(lot.expiry!)}',
      );
      left -= used;
    }
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(discard ? 'Descartar unidades' : 'Consumir con FEFO'),
        ),
        body: AppScroll(
          slivers: [
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      item.branchName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      discard
                          ? 'Lote L-${widget.lotId}'
                          : '${item.stock} ${item.unit} en existencia',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantity,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                    if (discard) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: reason,
                        decoration: const InputDecoration(
                          labelText: 'Motivo del descarte',
                        ),
                        maxLines: 2,
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      const SmallLabel('Lotes a descontar'),
                      const SizedBox(height: 8),
                      ...preview.map(
                        (text) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(text),
                        ),
                      ),
                      if (item
                          .alerts(widget.controller.now)
                          .contains(AlertKind.expired))
                        const Text(
                          'Primero debes descartar los lotes caducados.',
                          style: TextStyle(color: AppColors.red),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (error != null)
              sliverBox(
                Text(error!, style: const TextStyle(color: AppColors.red)),
              ),
            sliverBox(
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          await widget.controller.mutate(
                            () => discard
                                ? widget.controller.repository.discard(
                                    widget.branchId,
                                    widget.itemId,
                                    widget.lotId!,
                                    int.tryParse(quantity.text) ?? 0,
                                    reason.text,
                                  )
                                : widget.controller.repository.consume(
                                    widget.branchId,
                                    widget.itemId,
                                    int.tryParse(quantity.text) ?? 0,
                                  ),
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted) setState(() => error = humanError(e));
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                child: Text(
                  discard ? 'Registrar descarte' : 'Confirmar consumo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
