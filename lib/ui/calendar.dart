import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'inventory.dart';
import 'theme.dart';
import 'widgets.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.controller,
    required this.branchId,
  });
  final AppController controller;
  final int branchId;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime focused = widget.controller.now,
      selected = widget.controller.now;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        items = c.workspace!.inventory(widget.branchId);
    List<InventoryItem> events(DateTime day) =>
        items.where((i) => i.alertsOn(day, c.now)).toList();
    final todayEvents = events(c.now);
    return AppScroll(
      slivers: [
        sliverBox(
          const SectionTitle(
            'Calendario',
            subtitle: 'Toca un día para ver todos sus artículos',
          ),
        ),
        sliverBox(
          Panel(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = constraints.maxWidth / 7;
                final columns = math.max(1, ((cellWidth - 8) / 6).floor());
                final first = DateTime(focused.year, focused.month, 1);
                final start = first.subtract(Duration(days: first.weekday - 1));
                var most = 0;
                for (var index = 0; index < 42; index++) {
                  most = math.max(
                    most,
                    events(DateTime(start.year, start.month, start.day + index))
                        .length,
                  );
                }
                final rows = (most / columns).ceil();
                final rowHeight = math.max(60, 38 + rows * 6).toDouble();
                Widget cell(
                  BuildContext context,
                  DateTime day,
                  DateTime ignored,
                ) => CalendarDayCell(
                  day: day,
                  events: events(day),
                  selected: isSameDay(day, selected),
                  today: isSameDay(day, c.now),
                );
                return TableCalendar<InventoryItem>(
                  locale: 'es_MX',
                  firstDay: DateTime(2000),
                  lastDay: DateTime(2200, 12, 31),
                  focusedDay: focused,
                  rowHeight: rowHeight,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
                  eventLoader: events,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selectedDayPredicate: (day) => isSameDay(day, selected),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: cell,
                    selectedBuilder: cell,
                    todayBuilder: cell,
                    outsideBuilder: cell,
                    markerBuilder: (_, day, events) => const SizedBox.shrink(),
                  ),
                  onPageChanged: (day) => setState(() => focused = day),
                  onDaySelected: (day, focus) {
                    setState(() {
                      selected = day;
                      focused = focus;
                    });
                    showDayAlerts(context, c, day, branchId: widget.branchId);
                  },
                );
              },
            ),
          ),
        ),
        sliverBox(
          const Text(
            'Cada punto representa un artículo. Hoy también aparecen los agotados, por agotarse y caducados; los próximos días muestran avisos de caducidad según los lotes actuales.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        sliverBox(
          SectionTitle(
            'Alertas de hoy',
            subtitle: '${todayEvents.length} artículos',
          ),
        ),
        if (todayEvents.isEmpty)
          sliverBox(
            const EmptyState(
              'Todo en orden hoy',
              'Las próximas caducidades aparecerán en el calendario.',
              icon: Icons.event_available_outlined,
            ),
          ),
        SliverList.builder(
          itemCount: todayEvents.length,
          itemBuilder: (context, index) => ProductTile(
            item: todayEvents[index],
            now: c.now,
            onTap: () => openProduct(context, c, todayEvents[index]),
            onCart: c.busy
                ? null
                : () => perform(
                    context,
                    () => c.mutate(
                      () => c.repository.setCart(
                        widget.branchId,
                        todayEvents[index].id,
                        1,
                        add: true,
                      ),
                    ),
                    success: 'Agregado al carrito.',
                  ),
          ),
        ),
      ],
    );
  }
}

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.day,
    required this.events,
    this.selected = false,
    this.today = false,
  });
  final DateTime day;
  final List<InventoryItem> events;
  final bool selected, today;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${dayKey(day)}, ${events.length} artículos con alerta',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.ink : Colors.transparent,
              border: today && !selected
                  ? Border.all(color: AppColors.orange)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final item in events)
                Container(
                  key: ValueKey('calendar-dot-${dayKey(day)}-${item.id}'),
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> showDayAlerts(
  BuildContext context,
  AppController controller,
  DateTime day, {
  int? branchId,
  bool expiryOnly = false,
}) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (_) => Dialog.fullscreen(
    child: DayAlertsPage(
      controller: controller,
      day: day,
      branchId: branchId,
      expiryOnly: expiryOnly,
    ),
  ),
);

class DayAlertsPage extends StatelessWidget {
  const DayAlertsPage({
    super.key,
    required this.controller,
    required this.day,
    this.branchId,
    this.expiryOnly = false,
  });
  final AppController controller;
  final DateTime day;
  final int? branchId;
  final bool expiryOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final w = controller.workspace!;
      final items = w
          .inventory(branchId)
          .where(
            (i) => expiryOnly
                ? i.lots.any((l) => l.quantity > 0 && l.expiry == dateOnly(day))
                : i.alertsOn(day, controller.now),
          )
          .toList();
      final groups = w.branches
          .where((b) => items.any((i) => i.branchId == b.id))
          .toList();
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(shortDate(day)),
          actions: [
            IconButton(
              tooltip: 'Cerrar día',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
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
                    SmallLabel(
                      branchId == null
                          ? 'Todas las tiendas'
                          : w.branch(branchId!).name,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      expiryOnly ? 'Caducan este día' : 'Artículos con alerta',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${items.length} artículos · cantidades actuales',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              sliverBox(
                const EmptyState(
                  'Sin artículos para este día',
                  'Los lotes consumidos o descartados dejan de generar alertas.',
                  icon: Icons.event_available_outlined,
                ),
              ),
            for (final branch in groups) ...[
              if (branchId == null) sliverBox(SectionTitle(branch.name)),
              SliverList.list(
                children: [
                  for (final item in items.where(
                    (i) => i.branchId == branch.id,
                  ))
                    ProductTile(
                      item: item,
                      now: controller.now,
                      showBranch: branchId == null,
                      onTap: () => openProduct(context, controller, item),
                      onCart: controller.busy
                          ? null
                          : () => perform(
                              context,
                              () => controller.mutate(
                                () => controller.repository.setCart(
                                  item.branchId,
                                  item.id,
                                  1,
                                  add: true,
                                ),
                              ),
                              success:
                                  'Agregado al carrito de ${item.branchName}.',
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
