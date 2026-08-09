import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../platform/file_gateway.dart';

class WindowsFileGateway implements FileGateway {
  @override
  Future<String?> pickOpenPath({List<String> extensions = const []}) async {
    final result = await FilePicker.platform.pickFiles(
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  @override
  Future<String?> pickSavePath({
    required String suggestedName,
    List<String> extensions = const [],
  }) {
    return FilePicker.platform.saveFile(
      fileName: suggestedName,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
    );
  }

  @override
  Future<String> readText(String path) => File(path).readAsString();

  @override
  Future<void> writeText(String path, String contents) =>
      File(path).writeAsString(contents, flush: true);
}
