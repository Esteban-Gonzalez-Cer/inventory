import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../domain/models.dart';

class ExpiryReminder {
  const ExpiryReminder(this.date, this.items);
  final DateTime date;
  final List<InventoryItem> items;
  int get id => int.parse(dayKey(date).replaceAll('-', ''));
}

List<ExpiryReminder> expiryReminders(Workspace workspace, DateTime now) {
  final groups = <String, Map<int, InventoryItem>>{};
  for (final item in workspace.items.where(
    (i) => i.row.integer('reminders') == 1,
  )) {
    for (final lot in item.lots) {
      final alarmDate = lot.alarmDate;
      if (lot.quantity <= 0 ||
          alarmDate == null ||
          alarmDate.isBefore(dateOnly(now))) {
        continue;
      }
      groups.putIfAbsent(dayKey(alarmDate), () => {})[item.id] = item;
    }
  }
  final keys = groups.keys.toList()..sort();
  return keys
      .map(
        (key) =>
            ExpiryReminder(DateTime.parse(key), groups[key]!.values.toList()),
      )
      .take(60)
      .toList();
}

class ReminderService {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  String timezone = DateTime.now().timeZoneName;
  String? initialDate;
  void Function(String)? onOpen;
  Future<void> _queue = Future.value();

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    tzdata.initializeTimeZones();
    await _timezone();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) onOpen?.call(response.payload!);
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      initialDate = launch!.notificationResponse?.payload;
    }
    initialized = true;
  }

  Future<void> _timezone() async {
    timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(timezone));
  }

  Future<bool> requestPermission() async {
    if (!initialized) await initialize();
    if (Platform.isAndroid) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> synchronize(Workspace workspace) {
    _queue = _queue.then((_) async {
      if (!initialized) return;
      await _timezone();
      final now = tz.TZDateTime.now(tz.local);
      final hour = int.tryParse(workspace.settings['reminder_hour'] ?? '') ?? 9;
      final minute =
          int.tryParse(workspace.settings['reminder_minute'] ?? '') ?? 0;
      await plugin.cancelAllPendingNotifications();
      for (final group in expiryReminders(workspace, DateTime.now())) {
        final date = group.date;
        final scheduled = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          hour,
          minute,
        );
        if (!scheduled.isAfter(now)) continue;
        final branchCount = group.items.map((p) => p.branchId).toSet().length;
        await plugin.zonedSchedule(
          id: group.id,
          title: '${group.items.length} artículos caducan hoy',
          body:
              'Revisa los lotes de $branchCount ${branchCount == 1 ? 'tienda' : 'tiendas'} en Alacena.',
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'expiry',
              'Caducidad',
              channelDescription: 'Productos que caducan en tus tiendas',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: dayKey(date),
        );
      }
    });
    final result = _queue;
    _queue = result.catchError((Object error) {});
    return result;
  }
}
