import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final directory = Directory('build/qa');
    await directory.create(recursive: true);
    await File('${directory.path}/android-$name.png').writeAsBytes(bytes);
    return bytes.isNotEmpty;
  },
  // Image bytes are already written above; keep the response compact.
  responseDataCallback: (data) async {},
);
