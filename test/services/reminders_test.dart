import 'package:flutter_test/flutter_test.dart';
import 'package:inventory/domain/models.dart';
import 'package:inventory/services/reminders.dart';

import '../data/fixtures.dart';

void main() {
  test(
    'expiry reminders group dates across stores and deduplicate lots',
    () async {
      final f = Fixture();
      await f.open();
      await f.seed();
      addTearDown(f.repo.db.close);
      final north = await f.order(f.north, f.itemNorth, 5);
      final south = await f.order(f.south, f.itemSouth, 1);
      await f.deliver(f.north, north, 2, 'n1', expiry: DateTime(2026, 10, 20));
      await f.deliver(f.north, north, 3, 'n2', expiry: DateTime(2026, 10, 20));
      await f.deliver(f.south, south, 1, 's1', expiry: DateTime(2026, 10, 20));
      var groups = expiryReminders(await f.repo.load(), f.time);
      expect(groups.single.items.length, 2);
      expect(groups.single.id, 20261020);
      await f.repo.configureProduct(
        f.south,
        f.itemSouth,
        minimum: 2,
        warningDays: 7,
        reminders: false,
      );
      groups = expiryReminders(await f.repo.load(), f.time);
      expect(groups.single.items.single.branchId, f.north);
      await f.repo.consume(f.north, f.itemNorth, 5);
      expect(expiryReminders(await f.repo.load(), f.time), isEmpty);
    },
  );

  test(
    'saved alarm date is used and scheduling is bounded to 60 dates',
    () async {
      final f = Fixture();
      await f.open();
      await f.seed();
      addTearDown(f.repo.db.close);
      final w = await f.repo.load();
      final item = w.item(f.itemNorth);
      item.lots.addAll([
        for (var i = 70; i >= -2; i--)
          Lot({
            'id': i + 100,
            'cantidad': 1,
            'expiry_date': '2027-12-31',
            'fecha_alarma': DateTime(
              2026,
              10,
              17 + i,
            ).toIso8601String().substring(0, 10),
          }),
      ]);
      final groups = expiryReminders(w, f.time);
      expect(groups.length, 60);
      expect(groups.first.date, DateTime(2026, 10, 17));
      expect(groups.last.date, DateTime(2026, 10, 17 + 59));
    },
  );
}
