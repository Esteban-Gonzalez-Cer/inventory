import 'dart:async';

import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/controller.dart';
import 'ui/calendar.dart';
import 'ui/dashboard.dart';
import 'ui/forms.dart';
import 'ui/history.dart';
import 'ui/inventory.dart';
import 'ui/management.dart';
import 'ui/map_view.dart';
import 'ui/orders.dart';
import 'ui/reports_view.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class AlacenaApp extends StatefulWidget {
  const AlacenaApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<AlacenaApp> createState() => _AlacenaAppState();
}

class _AlacenaAppState extends State<AlacenaApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  Timer? midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_notification);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notification());
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    midnight?.cancel();
    final now = DateTime.now();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now) +
          const Duration(seconds: 1),
      () {
        unawaited(widget.controller.resume());
        _scheduleMidnight();
      },
    );
  }

  void _notification() {
    final pending = widget.controller.pendingNotificationDate;
    if (pending == null || widget.controller.workspace == null) return;
    widget.controller.acknowledgeNotification();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigator.currentContext;
      if (context != null && mounted) {
        final date = DateTime.tryParse(pending);
        if (date != null) {
          showDayAlerts(context, widget.controller, date, expiryOnly: true);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.resume());
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    widget.controller.removeListener(_notification);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alacena',
    debugShowCheckedModeBanner: false,
    navigatorKey: navigator,
    theme: alacenaTheme(),
    locale: const Locale('es', 'MX'),
    supportedLocales: const [Locale('es', 'MX')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.workspace == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Alacena',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 20),
                    if (widget.controller.loadError == null)
                      const CircularProgressIndicator()
                    else ...[
                      Text(
                        widget.controller.loadError!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: widget.controller.initialize,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return WorkspaceShell(controller: widget.controller);
      },
    ),
  );
}

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int globalIndex = 0, branchIndex = 0;
  int? lastBranch;
  @override
  void initState() {
    super.initState();
    lastBranch = widget.controller.selectedBranchId;
    widget.controller.addListener(_scopeChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scopeChanged);
    super.dispose();
  }

  void _scopeChanged() {
    if (lastBranch != widget.controller.selectedBranchId && mounted) {
      setState(() {
        lastBranch = widget.controller.selectedBranchId;
        branchIndex = 0;
      });
    }
  }

  void openBranch(int id) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.controller.selectBranch(id);
  }

  Future<void> switchBranch() async {
    final c = widget.controller;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .65,
        child: AppScroll(
          slivers: [
            sliverBox(
              const SectionTitle('Cambiar tienda'),
              padding: const EdgeInsets.all(20),
            ),
            sliverBox(
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 0),
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Volver a vista general'),
              ),
            ),
            SliverList.list(
              children: [
                for (final b in c.workspace!.branches)
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(b.name),
                    subtitle: Text(b.address),
                    selected: b.id == c.selectedBranchId,
                    onTap: () => Navigator.pop(context, b.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      if (selected == 0) {
        c.selectBranch(null);
      } else {
        openBranch(selected);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, w = c.workspace!, branch = c.selectedBranch;
    final inBranch = branch != null;
    final Widget body;
    if (branch != null) {
      body = switch (branchIndex) {
        0 => DashboardPage(
          key: ValueKey('summary-${branch.id}'),
          controller: c,
          branchId: branch.id,
          onOpenBranch: openBranch,
          onInventory: () => setState(() => branchIndex = 1),
          onOrders: () => setState(() => branchIndex = 3),
        ),
        1 => InventoryPage(
          key: ValueKey('inventory-${branch.id}'),
          controller: c,
          branchId: branch.id,
        ),
        2 => CalendarPage(
          key: ValueKey('calendar-${branch.id}'),
          controller: c,
          branchId: branch.id,
        ),
        3 => OrdersPage(
          key: ValueKey('orders-${branch.id}'),
          controller: c,
          branchId: branch.id,
        ),
        _ => HistoryPage(
          key: ValueKey('history-${branch.id}'),
          controller: c,
          branchId: branch.id,
        ),
      };
    } else {
      body = switch (globalIndex) {
        0 => DashboardPage(
          key: const ValueKey('global-dashboard'),
          controller: c,
          onOpenBranch: openBranch,
        ),
        1 => BranchMap(
          workspace: w,
          onOpen: openBranch,
          onCreate: () => editMaster(context, c, 'Sucursal'),
        ),
        2 => ReportsPage(controller: c),
        _ => ManagementPage(controller: c),
      };
    }
    return PopScope(
      canPop: !inBranch,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && inBranch && !c.busy) c.selectBranch(null);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 82,
          leading: inBranch
              ? IconButton(
                  tooltip: 'Vista general',
                  onPressed: c.busy ? null : () => c.selectBranch(null),
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: inBranch
              ? InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: c.busy ? null : switchBranch,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SmallLabel('Tienda seleccionada'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              branch.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 20),
                        ],
                      ),
                    ],
                  ),
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alacena',
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.4,
                      ),
                    ),
                    Text(
                      'GESTIONA EL INVENTARIO DE TUS TIENDAS',
                      style: TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.7,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: badges.Badge(
                  showBadge: c.cartCount > 0,
                  position: badges.BadgePosition.topEnd(top: -3, end: -3),
                  badgeStyle: const badges.BadgeStyle(
                    badgeColor: AppColors.orange,
                    padding: EdgeInsets.all(5),
                  ),
                  badgeContent: Text(
                    '${c.cartCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  child: IconButton(
                    tooltip: 'Abrir carrito',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CartPage(controller: c, branchId: branch?.id),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 23),
                  ),
                ),
              ),
            ),
          ],
          bottom: c.busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.orange,
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            if (c.loadError != null)
              MaterialBanner(
                content: Text(
                  'La vista puede estar desactualizada. ${c.loadError}',
                ),
                actions: [
                  TextButton(
                    onPressed: c.refresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: FloatingNavigation(
          index: inBranch ? branchIndex : globalIndex,
          branch: inBranch,
          onChanged: (value) {
            if (c.busy) return;
            setState(() {
              if (inBranch) {
                branchIndex = value;
              } else {
                globalIndex = value;
              }
            });
          },
        ),
      ),
    );
  }
}

class FloatingNavigation extends StatelessWidget {
  const FloatingNavigation({
    super.key,
    required this.index,
    required this.branch,
    required this.onChanged,
  });
  final int index;
  final bool branch;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final destinations = branch
        ? [
            (Icons.home_outlined, 'Resumen'),
            (Icons.inventory_2_outlined, 'Inventario'),
            (Icons.calendar_month_outlined, 'Calendario'),
            (Icons.receipt_long_outlined, 'Pedidos'),
            (Icons.history, 'Historial'),
          ]
        : [
            (Icons.home_outlined, 'Inicio'),
            (Icons.map_outlined, 'Mapa'),
            (Icons.description_outlined, 'Reportes'),
            (Icons.grid_view_outlined, 'Gestión'),
          ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: .04),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  label: destinations[i].$2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onChanged(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: i == index
                                  ? AppColors.ink
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              destinations[i].$1,
                              size: 21,
                              color: i == index ? Colors.white : AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destinations[i].$2,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: i == index
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == index
                                  ? AppColors.ink
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
