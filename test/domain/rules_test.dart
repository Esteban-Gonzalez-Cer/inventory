import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/core/format.dart';
import 'package:inventory/domain/models.dart';

void main() {
  test('money parsing is exact cents and rejects malformed values', () {
    expect(parseCents('12.99'), 1299);
    expect(parseCents('0,10'), 10);
    expect(parseCents('-1'), null);
    expect(parseCents('1.001'), null);
  });
  test(
    'rolling windows clamp month ends, preserve leap years and exclude end',
    () {
      final time = DateTime(2024, 3, 31, 12, 23);
      final range = ReportPeriod.month.window(time);
      expect(range.start.toLocal(), DateTime(2024, 2, 29, 12, 23));
      expect(range.includes(range.start.toIso8601String()), true);
      expect(range.includes(range.end.toIso8601String()), false);
      expect(
        ReportPeriod.year.window(DateTime(2024, 2, 29, 9)).start.toLocal(),
        DateTime(2023, 2, 28, 9),
      );
      expect(
        ReportPeriod.day
            .window(time)
            .end
            .difference(ReportPeriod.day.window(time).start),
        const Duration(hours: 24),
      );
      expect(
        ReportPeriod.week
            .window(time)
            .end
            .difference(ReportPeriod.week.window(time).start),
        const Duration(days: 7),
      );
    },
  );
  test('alerts overlap and calendar produces one event per product', () {
    final item = InventoryItem(
      {'id': 1, 'minimum_stock': 2, 'warning_days': 7},
      [
        Lot({'id': 1, 'cantidad': 1, 'expiry_date': '2026-10-16'}),
        Lot({'id': 2, 'cantidad': 1, 'expiry_date': '2026-10-20'}),
      ],
    );
    expect(
      item.alerts(DateTime(2026, 10, 17)),
      containsAll([AlertKind.expired, AlertKind.expiring, AlertKind.low]),
    );
    expect(item.alertsOn(DateTime(2026, 10, 18), DateTime(2026, 10, 17)), true);
    expect(item.alertsOn(DateTime(2026, 10, 16), DateTime(2026, 10, 17)), true);
    expect(item.alertsOn(DateTime(2026, 11, 1), DateTime(2026, 10, 17)), false);
  });

  test('all six windows handle year and month boundaries', () {
    final end = DateTime(2025, 1, 31, 14, 45);
    final starts = {
      ReportPeriod.day: end.subtract(const Duration(hours: 24)),
      ReportPeriod.week: end.subtract(const Duration(days: 7)),
      ReportPeriod.month: DateTime(2024, 12, 31, 14, 45),
      ReportPeriod.quarter: DateTime(2024, 10, 31, 14, 45),
      ReportPeriod.halfYear: DateTime(2024, 7, 31, 14, 45),
      ReportPeriod.year: DateTime(2024, 1, 31, 14, 45),
    };
    for (final entry in starts.entries) {
      final window = entry.key.window(end);
      expect(window.start, entry.value.toUtc());
      expect(window.end, end.toUtc());
      expect(window.includes(window.start.toIso8601String()), isTrue);
      expect(window.includes(window.end.toIso8601String()), isFalse);
      expect(
        window.includes(
          window.start
              .subtract(const Duration(microseconds: 1))
              .toIso8601String(),
        ),
        isFalse,
      );
    }
    expect(
      ReportPeriod.quarter.window(DateTime(2025, 5, 31)).start.toLocal(),
      DateTime(2025, 2, 28),
    );
    expect(
      ReportPeriod.halfYear.window(DateTime(2025, 8, 31)).start.toLocal(),
      DateTime(2025, 2, 28),
    );
  });
}
