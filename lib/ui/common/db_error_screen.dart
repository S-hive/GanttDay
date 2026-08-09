import 'package:flutter/material.dart';

/// Shown when the database cannot be opened. Never recreates silently: the
/// user chooses between backing up the broken file (then starting fresh) and
/// quitting (spec section 8).
class DbErrorScreen extends StatelessWidget {
  const DbErrorScreen({
    super.key,
    required this.message,
    required this.path,
    required this.onBackupAndContinue,
    required this.onQuit,
  });

  final String message;
  final String path;
  final VoidCallback onBackupAndContinue;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 32),
                    SizedBox(width: 12),
                    Text('无法打开数据库',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('数据库文件可能已损坏或被其他程序占用。\n\n文件位置：$path\n\n错误详情：$message'),
                const SizedBox(height: 24),
                const Text('你可以将损坏的文件另存到旁边，然后新建一个空数据库继续使用；'
                    '原文件会保留，以便日后尝试恢复。'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onQuit,
                      child: const Text('退出'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: onBackupAndContinue,
                      child: const Text('备份损坏文件并新建'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
