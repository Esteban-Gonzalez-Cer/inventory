import 'package:intl/intl.dart';

String money(int cents) => NumberFormat.currency(
  locale: 'es_MX',
  symbol: '\$',
  decimalDigits: 2,
).format(cents / 100);
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
String shortDate(DateTime date) =>
    DateFormat('d MMM yyyy', 'es_MX').format(date);
String dateTimeLabel(String value) => DateFormat(
  'd MMM yyyy · HH:mm',
  'es_MX',
).format(DateTime.parse(value).toLocal());
int? parseCents(String value) {
  final clean = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(clean)) return null;
  final parts = clean.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
