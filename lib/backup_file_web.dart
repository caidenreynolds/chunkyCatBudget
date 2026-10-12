// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

Future<String?> pickBackupFile() async {
  final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
  final result = Completer<String?>();
  input.onChange.first.then((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      result.complete(null);
      return;
    }
    if (files.first.size > 10000000) {
      result.completeError(StateError('Backup must be smaller than 10 MB.'));
      return;
    }
    final reader = html.FileReader()..readAsText(files.first);
    reader.onLoad.first.then((_) => result.complete(reader.result as String));
    reader.onError.first.then(
      (_) => result.completeError(StateError('Could not read backup.')),
    );
  });
  input.addEventListener('cancel', (_) {
    if (!result.isCompleted) result.complete(null);
  });
  input.click();
  return result.future;
}

void downloadBackup(String filename, String contents) {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([contents], 'text/csv;charset=utf-8'),
  );
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}
