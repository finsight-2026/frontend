import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final path = Platform.environment['FINSIGHT_E2E_SCREENSHOTS'];
  if (path == null) throw StateError('Set FINSIGHT_E2E_SCREENSHOTS');
  final folder = await Directory(path).create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${folder.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
