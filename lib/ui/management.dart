import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../domain/models.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class ManagementPage extends StatelessWidget {
  const ManagementPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final w = controller.workspace!;
    return AppScroll(
      slivers: [
        sliverBox(
          const SectionTitle(
            'Gestión',
            subtitle: 'Todo lo que da forma a tu inventario',
          ),
        ),
        SliverList.list(
          children: [
            for (final entry in [
              (
                table: 'Sucursal',
                name: 'Mis tiendas',
                subtitle: 'Direcciones y ubicaciones',
                icon: Icons.storefront_outlined,
                count: w.branches.length,
              ),
              (
                table: 'Producto',
                name: 'Catálogo compartido',
                subtitle: 'Artículos e imágenes',
                icon: Icons.inventory_2_outlined,
                count: w.products.length,
              ),
              (
                table: 'Categoria',
                name: 'Categorías',
                subtitle: 'Organiza tus artículos',
                icon: Icons.category_outlined,
                count: w.categories.length,
              ),
              (
                table: 'Tienda',
                name: 'Proveedores',
                subtitle: 'Dónde compras tus productos',
                icon: Icons.local_shipping_outlined,
                count: w.suppliers.length,
              ),
            ])
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(entry.icon, color: AppColors.ink),
                    ),
                    title: Text(
                      entry.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text('${entry.subtitle} · ${entry.count}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MasterListPage(
                          controller: controller,
                          table: entry.table,
                          title: entry.name,
                        ),
                      ),
                    ),
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
                const SmallLabel('En tu dispositivo'),
                const SizedBox(height: 10),
                const Text(
                  'Tus datos se guardan localmente.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Las tiendas comparten el catálogo y conservan sus propias existencias. Los mapas utilizan conexión a internet.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Configurar recordatorios'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MasterListPage extends StatelessWidget {
  const MasterListPage({
    super.key,
    required this.controller,
    required this.table,
    required this.title,
  });
  final AppController controller;
  final String table, title;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final w = controller.workspace!;
      final List<DbRow> rows = switch (table) {
        'Sucursal' => w.branches.map((b) => b.row).toList(),
        'Producto' => w.products,
        'Categoria' => w.categories,
        _ => w.suppliers,
      };
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: AppScroll(
          slivers: [
            sliverBox(
              FilledButton.icon(
                onPressed: () => editMaster(context, controller, table),
                icon: const Icon(Icons.add),
                label: Text('Agregar ${masterTitle(table).toLowerCase()}'),
              ),
            ),
            if (rows.isEmpty)
              sliverBox(
                EmptyState(
                  'Comienza con un registro',
                  'Agrega ${masterTitle(table).toLowerCase()} para organizar tus operaciones.',
                ),
              ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      leading: table == 'Producto'
                          ? ProductPicture(row, size: 48)
                          : Icon(
                              table == 'Sucursal'
                                  ? Icons.storefront_outlined
                                  : table == 'Categoria'
                                  ? Icons.category_outlined
                                  : Icons.local_shipping_outlined,
                            ),
                      title: Text(row.text('name')),
                      subtitle: table == 'Producto'
                          ? Text(row.text('category_name'))
                          : row.text('address').isNotEmpty
                          ? Text(row.text('address'))
                          : null,
                      onTap: () =>
                          editMaster(context, controller, table, row: row),
                      trailing: PopupMenuButton<String>(
                        onSelected: (choice) async {
                          if (choice == 'edit') {
                            await editMaster(
                              context,
                              controller,
                              table,
                              row: row,
                            );
                          }
                          if (choice == 'delete' &&
                              context.mounted &&
                              await confirm(
                                context,
                                'Eliminar ${masterTitle(table).toLowerCase()}',
                                'Se eliminará ${row.text('name')} si no tiene registros relacionados.',
                              )) {
                            if (context.mounted) {
                              await perform(
                                context,
                                () => controller.mutate(
                                  () => controller.repository.deleteMaster(
                                    table,
                                    row.integer('id'),
                                  ),
                                ),
                                success: 'Registro eliminado.',
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final settings = controller.workspace!.settings;
      final time = TimeOfDay(
        hour: int.tryParse(settings['reminder_hour'] ?? '') ?? 9,
        minute: int.tryParse(settings['reminder_minute'] ?? '') ?? 0,
      );
      return Scaffold(
        appBar: AppBar(title: const Text('Recordatorios')),
        body: AppScroll(
          slivers: [
            sliverBox(
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.orange,
                      size: 32,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Un aviso, todas tus tiendas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Recibe un recordatorio en los días con productos que caducan. Al tocarlo verás los artículos agrupados por tienda.',
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => perform(context, () async {
                        final granted =
                            await controller.reminders?.requestPermission() ??
                            false;
                        await controller.resume();
                        if (context.mounted) {
                          message(
                            context,
                            granted ? 'Notificaciones habilitadas.' : 'No se otorgó permiso. Puedes cambiarlo en los ajustes del dispositivo.',
                          );
                        }
                        return null;
                      }),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Habilitar notificaciones'),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hora del recordatorio'),
                      subtitle: Text(
                        '${time.format(context)} · hora local del dispositivo',
                      ),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final selected = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (selected != null && context.mounted) {
                          await perform(
                            context,
                            () => controller.mutate(
                              () => controller.repository.saveReminderTime(
                                selected.hour,
                                selected.minute,
                              ),
                            ),
                            success: 'Hora actualizada.',
                          );
                        }
                      },
                    ),
                    const Text(
                      'Los avisos se actualizan al abrir la app y al cambiar el inventario. Se programan hasta 60 fechas; el sistema puede ajustar la hora de entrega.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    if (controller.reminderError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        controller.reminderError!,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            sliverBox(
              const Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SmallLabel('Valores iniciales'),
                    SizedBox(height: 10),
                    Text(
                      'Stock mínimo: 2 unidades\nAviso de caducidad: 7 días',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Puedes cambiar estos valores y activar recordatorios para cada artículo dentro de su tienda.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
