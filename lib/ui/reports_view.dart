import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/controller.dart';
import '../core/format.dart';
import '../domain/models.dart';
import '../services/reports.dart';
import 'theme.dart';
import 'widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.controller, this.branchId});
  final AppController controller;
  final int? branchId;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late int? branchId = widget.branchId;
  ReportPeriod period = ReportPeriod.month;
  bool generating = false;
  String? error;
  Future<void> generate() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final snapshot = ReportSnapshot.capture(
        widget.controller.workspace!,
        branchId: branchId,
        period: period,
        generatedAt: widget.controller.now,
        timezone:
            widget.controller.reminders?.timezone ??
            DateTime.now().timeZoneName,
      );
      final bytes = await ReportService.generate(snapshot);
      final path = await widget.controller.mutate(
        () => ReportService.save(widget.controller.repository, snapshot, bytes),
      );
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfDocumentPage(
              bytes: bytes,
              title: snapshot.scopeName,
              filename: File(path).uri.pathSegments.last,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'No se pudo generar el PDF. ${humanError(e)}');
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final w = widget.controller.workspace!,
          window = period.window(widget.controller.now);
      if (branchId != null && !w.branches.any((b) => b.id == branchId)) {
        branchId = null;
      }
      final reports = w.scoped(w.reports, branchId);
      return AppScroll(
        slivers: [
          sliverBox(
            const SectionTitle(
              'Reportes',
              subtitle: 'Del pedido al lote, cada movimiento en un PDF',
            ),
          ),
          sliverBox(
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xffffd197), Color(0xffef9d76)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, size: 34),
                  const SizedBox(height: 16),
                  Text(
                    'Tu historial,\nsiempre a mano.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pedidos, compras, consumos y descartes. Generado y guardado en tu dispositivo.',
                  ),
                ],
              ),
            ),
          ),
          sliverBox(
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey(branchId),
                    initialValue: branchId ?? 0,
                    decoration: const InputDecoration(labelText: 'Alcance'),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Todas las tiendas'),
                      ),
                      for (final b in w.branches)
                        DropdownMenuItem(value: b.id, child: Text(b.name)),
                    ],
                    onChanged: generating
                        ? null
                        : (v) => setState(() => branchId = v == 0 ? null : v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<ReportPeriod>(
                    initialValue: period,
                    decoration: const InputDecoration(labelText: 'Período'),
                    items: ReportPeriod.values
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.label)),
                        )
                        .toList(),
                    onChanged: generating
                        ? null
                        : (v) => setState(() => period = v!),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${dateTimeLabel(window.start.toIso8601String())}\n${dateTimeLabel(window.end.toIso8601String())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  const SmallLabel('Compras recibidas en el período'),
                  const SizedBox(height: 6),
                  Text(
                    money(w.spending(window, branchId)),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: generating || widget.controller.busy
                          ? null
                          : generate,
                      icon: generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined, size: 20),
                      label: Text(
                        generating ? 'Generando PDF…' : 'Generar y ver PDF',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            sliverBox(
              Text(error!, style: const TextStyle(color: AppColors.red)),
            ),
          sliverBox(
            const SectionTitle(
              'Exportaciones guardadas',
              subtitle: 'Conservan los datos del momento en que se generaron',
            ),
          ),
          if (reports.isEmpty)
            sliverBox(
              const EmptyState(
                'Tu primer reporte está por llegar',
                'Elige el alcance y el período. Los PDF también se generan sin conexión.',
                icon: Icons.description_outlined,
              ),
            ),
          SliverList.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final r = reports[index];
              final selectedPeriod = ReportPeriod.values
                  .where((p) => p.name == r.text('period'))
                  .firstOrNull;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: AppColors.orange,
                      ),
                    ),
                    title: Text(r.text('scope_name')),
                    subtitle: Text(
                      '${selectedPeriod?.label ?? r.text('period')}\n${dateTimeLabel(r.text('generated_at'))}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => perform(context, () async {
                      final file = File(r.text('file_path'));
                      if (!await file.exists()) {
                        throw const AppFailure(
                          'Este archivo ya no está en el dispositivo. Genera un nuevo reporte.',
                        );
                      }
                      final bytes = await file.readAsBytes();
                      if (context.mounted) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfDocumentPage(
                              bytes: bytes,
                              title: r.text('scope_name'),
                              filename: file.uri.pathSegments.last,
                            ),
                          ),
                        );
                      }
                      return null;
                    }),
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

class PdfDocumentPage extends StatelessWidget {
  const PdfDocumentPage({
    super.key,
    required this.bytes,
    required this.title,
    required this.filename,
  });
  final Uint8List bytes;
  final String title, filename;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PdfPreview(
      build: (_) => bytes,
      pdfFileName: filename,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: true,
    ),
  );
}
