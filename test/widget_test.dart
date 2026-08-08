import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/db_error_screen.dart';

void main() {
  testWidgets('db error screen shows message, path and both actions',
      (tester) async {
    var backup = false;
    var quit = false;
    await tester.pumpWidget(MaterialApp(
      home: DbErrorScreen(
        message: 'disk I/O error',
        path: r'C:\data\gantday.db',
        onBackupAndContinue: () => backup = true,
        onQuit: () => quit = true,
      ),
    ));
    expect(find.textContaining('disk I/O error'), findsOneWidget);
    expect(find.textContaining(r'C:\data\gantday.db'), findsOneWidget);
    await tester.tap(find.text('备份损坏文件并新建'));
    await tester.tap(find.text('退出'));
    expect(backup, true);
    expect(quit, true);
  });
}
