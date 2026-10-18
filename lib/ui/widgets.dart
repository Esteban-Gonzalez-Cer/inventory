import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import 'theme.dart';

const productAssets = ['grocery', 'milk', 'produce', 'bread', 'can', 'bottle'];
const productAssetLabels = [
  'Despensa',
  'Lácteos',
  'Frutas',
  'Pan',
  'Conservas',
  'Bebidas',
];

Future<bool> perform(
  BuildContext context,
  Future<Object?> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) message(context, success);
    return true;
  } catch (e) {
    if (context.mounted) message(context, humanError(e), error: true);
    return false;
  }
}

void message(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.red : AppColors.ink,
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;

Widget sliverBox(
  Widget child, {
  EdgeInsets padding = const EdgeInsets.fromLTRB(20, 0, 20, 18),
}) => SliverPadding(
  padding: padding,
  sliver: SliverToBoxAdapter(child: child),
);

class AppScroll extends StatelessWidget {
  const AppScroll({super.key, required this.slivers, this.controller});
  final List<Widget> slivers;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: controller,
    slivers: [
      ...slivers,
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ],
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.description, {
    super.key,
    this.icon = Icons.inventory_2_outlined,
    this.action,
    this.onAction,
  });
  final String title, description;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: AppColors.orange),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class ProductPicture extends StatelessWidget {
  const ProductPicture(this.row, {super.key, this.size = 56});
  final DbRow row;
  final double size;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => SvgPicture.asset(
      row.text('image_asset').isEmpty
          ? 'assets/products/grocery.svg'
          : row.text('image_asset'),
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    final path = row.text('image_path');
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: path.isEmpty
          ? fallback()
          : Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => fallback(),
            ),
    );
  }
}

Color alertColor(AlertKind kind) => switch (kind) {
  AlertKind.expired => AppColors.red,
  AlertKind.empty => AppColors.ink,
  AlertKind.today || AlertKind.expiring => AppColors.amber,
  AlertKind.low => AppColors.orange,
};
IconData alertIcon(AlertKind kind) => switch (kind) {
  AlertKind.expired => Icons.event_busy_outlined,
  AlertKind.empty => Icons.remove_shopping_cart_outlined,
  AlertKind.today || AlertKind.expiring => Icons.schedule,
  AlertKind.low => Icons.battery_1_bar,
};

class StatusTags extends StatelessWidget {
  const StatusTags(this.alerts, {super.key});
  final Set<AlertKind> alerts;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 5,
    children: alerts.isEmpty
        ? [tag('En orden', AppColors.teal, Icons.check_circle_outline)]
        : AlertKind.values
              .where(alerts.contains)
              .map((a) => tag(a.label, alertColor(a), alertIcon(a)))
              .toList(),
  );
  Widget tag(String text, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.item,
    required this.now,
    this.showBranch = false,
    this.onTap,
    this.onCart,
  });
  final InventoryItem item;
  final DateTime now;
  final bool showBranch;
  final VoidCallback? onTap, onCart;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductPicture(item.row),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (showBranch)
                      Text(
                        item.branchName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.teal,
                        ),
                      ),
                    Text(
                      '${item.stock} ${item.unit} · ${item.nearestExpiry == null ? 'Sin fecha' : shortDate(item.nearestExpiry!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    StatusTags(item.alerts(now)),
                  ],
                ),
              ),
              if (onCart != null)
                IconButton(
                  tooltip: 'Agregar ${item.name} al carrito',
                  onPressed: onCart,
                  icon: const Icon(Icons.add_shopping_cart_outlined, size: 21),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SmallLabel extends StatelessWidget {
  const SmallLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
      letterSpacing: 1.3,
    ),
  );
}
