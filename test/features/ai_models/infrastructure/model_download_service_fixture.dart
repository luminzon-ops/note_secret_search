part of 'model_download_service_test.dart';

String _checksumFor(List<int> bytes) {
  return 'sha256:${sha256.convert(bytes).toString()}';
}

ModelDownloadService _serviceFor(Directory tempDir) {
  return ModelDownloadService(
    dio: Dio(),
    logger: const AppLogger(),
    applicationSupportDirectoryProvider: () async => tempDir,
  );
}

Future<Directory> _createTempDir() {
  return Directory.systemTemp.createTemp('model-download-service');
}
