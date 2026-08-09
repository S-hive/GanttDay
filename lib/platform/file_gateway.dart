abstract class FileGateway {
  Future<String?> pickOpenPath({List<String> extensions});

  Future<String?> pickSavePath({
    required String suggestedName,
    List<String> extensions,
  });

  Future<String> readText(String path);

  Future<void> writeText(String path, String contents);
}
