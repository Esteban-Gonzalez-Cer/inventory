import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';
import 'theme.dart';
import 'widgets.dart';

const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

TileLayer alacenaTiles({void Function()? onError}) => TileLayer(
  urlTemplate: tileUrl,
  userAgentPackageName: 'mx.alacena.inventory',
  maxNativeZoom: 19,
  tileProvider: NetworkTileProvider(
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 100000000,
    ),
  ),
  errorTileCallback: (tile, error, stackTrace) => onError?.call(),
);

Widget mapAttribution() => Align(
  alignment: Alignment.topRight,
  child: Padding(
    padding: const EdgeInsets.all(8),
    child: Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => launchUrl(
          Uri.parse('https://www.openstreetmap.org/copyright'),
          mode: LaunchMode.externalApplication,
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: 10, color: AppColors.ink),
          ),
        ),
      ),
    ),
  ),
);

class BranchMap extends StatefulWidget {
  const BranchMap({
    super.key,
    required this.workspace,
    required this.onOpen,
    required this.onCreate,
  });
  final Workspace workspace;
  final void Function(int) onOpen;
  final VoidCallback onCreate;
  @override
  State<BranchMap> createState() => _BranchMapState();
}

class _BranchMapState extends State<BranchMap> {
  final map = MapController();
  int? selected;
  bool failed = false;
  int retry = 0;
  @override
  void dispose() {
    map.dispose();
    super.dispose();
  }

  void tileFailed() {
    if (!failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !failed) setState(() => failed = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = widget.workspace.branches;
    if (branches.isEmpty) {
      return AppScroll(
        slivers: [
          sliverBox(
            EmptyState(
              'Ubica tus tiendas',
              'Registra tu primera tienda y selecciona su ubicación en el mapa.',
              icon: Icons.map_outlined,
              action: 'Agregar tienda',
              onAction: widget.onCreate,
            ),
          ),
        ],
      );
    }
    final current =
        branches.where((b) => b.id == selected).firstOrNull ?? branches.first;
    final points = branches
        .map((b) => LatLng(b.latitude, b.longitude))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(retry),
              mapController: map,
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 13,
                initialCameraFit: points.length > 1
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.fromLTRB(50, 65, 50, 260),
                        maxZoom: 15,
                      )
                    : null,
              ),
              children: [
                alacenaTiles(onError: tileFailed),
                MarkerLayer(
                  markers: branches
                      .map(
                        (branch) => Marker(
                          point: LatLng(branch.latitude, branch.longitude),
                          width: 60,
                          height: 64,
                          child: Tooltip(
                            message: branch.name,
                            child: GestureDetector(
                              onTap: () => setState(() => selected = branch.id),
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: branch.id == current.id
                                          ? AppColors.orange
                                          : AppColors.ink,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.12,
                                          ),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.storefront_outlined,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: branch.id == current.id
                                        ? AppColors.orange
                                        : AppColors.ink,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            mapAttribution(),
            Positioned(
              top: 48,
              left: 12,
              child: Column(
                children: [
                  _mapButton(
                    Icons.center_focus_strong,
                    'Ver todas',
                    () => map.fitCamera(
                      CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.fromLTRB(50, 80, 50, 260),
                        maxZoom: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _mapButton(
                    Icons.add,
                    'Acercar',
                    () => map.move(map.camera.center, map.camera.zoom + 1),
                  ),
                  const SizedBox(height: 8),
                  _mapButton(
                    Icons.remove,
                    'Alejar',
                    () => map.move(map.camera.center, map.camera.zoom - 1),
                  ),
                ],
              ),
            ),
            if (failed)
              Positioned(
                top: 50,
                left: 70,
                right: 10,
                child: Panel(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No se pudo cargar el mapa',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'Las direcciones y tus tiendas siguen disponibles.',
                        style: TextStyle(fontSize: 11),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          failed = false;
                          retry++;
                        }),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            DraggableScrollableSheet(
              initialChildSize: .38,
              minChildSize: .24,
              maxChildSize: .8,
              builder: (context, scroll) => Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    sliverBox(
                      Center(
                        child: Container(
                          width: 35,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    ),
                    sliverBox(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SmallLabel('Tienda seleccionada'),
                          const SizedBox(height: 6),
                          Text(
                            current.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            current.address,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${current.latitude.toStringAsFixed(5)}, ${current.longitude.toStringAsFixed(5)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => widget.onOpen(current.id),
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: const Text('Abrir tienda'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    sliverBox(const SectionTitle('Todas las tiendas')),
                    SliverList.builder(
                      itemCount: branches.length,
                      itemBuilder: (context, index) {
                        final branch = branches[index];
                        return ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(branch.name),
                          subtitle: Text(branch.address, maxLines: 2),
                          selected: branch.id == current.id,
                          onTap: () {
                            setState(() => selected = branch.id);
                            map.move(
                              LatLng(branch.latitude, branch.longitude),
                              14,
                            );
                          },
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
        ),
      );
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initial});
  final LatLng? initial;
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  LatLng? point;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    point = widget.initial;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ubicación de la tienda')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text(
            'Toca el mapa para colocar el marcador. También puedes capturar las coordenadas en el formulario.',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: point ?? const LatLng(0, 0),
                      initialZoom: point == null ? 2 : 15,
                      onTap: (_, p) => setState(() => point = p),
                    ),
                    children: [
                      alacenaTiles(
                        onError: () {
                          if (!failed) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => failed = true);
                            });
                          }
                        },
                      ),
                      if (point != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point!,
                              width: 48,
                              height: 48,
                              child: const Icon(
                                Icons.location_on,
                                color: AppColors.orange,
                                size: 48,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  mapAttribution(),
                  if (failed)
                    const Positioned(
                      left: 12,
                      bottom: 12,
                      right: 12,
                      child: Panel(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Mapa no disponible. Vuelve y captura latitud y longitud manualmente.',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (point != null)
                  Text(
                    '${point!.latitude.toStringAsFixed(6)}, ${point!.longitude.toStringAsFixed(6)}',
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: point == null
                        ? null
                        : () => Navigator.pop(context, point),
                    child: const Text('Usar ubicación'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
