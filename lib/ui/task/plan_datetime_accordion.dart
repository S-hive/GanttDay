import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PlanEditorTarget { none, start, end }

/// Plan start/end rows with an optional inline digit editor + 确定.
class PlanDatetimeAccordion extends StatelessWidget {
  const PlanDatetimeAccordion({
    super.key,
    required this.startLabel,
    required this.endLabel,
    required this.target,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    this.error,
    required this.onTapStart,
    required this.onTapEnd,
    required this.onConfirm,
  });

  final String startLabel;
  final String endLabel;
  final PlanEditorTarget target;
  final TextEditingController year;
  final TextEditingController month;
  final TextEditingController day;
  final TextEditingController hour;
  final TextEditingController minute;
  final String? error;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('计划开始'),
          subtitle: Text(startLabel),
          trailing: const Icon(Icons.schedule),
          onTap: onTapStart,
        ),
        if (target == PlanEditorTarget.start) _editorStrip(context),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('计划结束'),
          subtitle: Text(endLabel),
          trailing: const Icon(Icons.schedule),
          onTap: onTapEnd,
        ),
        if (target == PlanEditorTarget.end) _editorStrip(context),
      ],
    );
  }

  Widget _editorStrip(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DigitBox(controller: year, maxLength: 4, width: 56, hint: '年'),
              const SizedBox(width: 6),
              _DigitBox(controller: month, maxLength: 2, width: 40, hint: '月'),
              const SizedBox(width: 6),
              _DigitBox(controller: day, maxLength: 2, width: 40, hint: '日'),
              const SizedBox(width: 12),
              _DigitBox(controller: hour, maxLength: 2, width: 40, hint: '时'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(':', style: theme.textTheme.titleMedium),
              ),
              _DigitBox(controller: minute, maxLength: 2, width: 40, hint: '分'),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onConfirm,
                child: const Text('确定'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({
    required this.controller,
    required this.maxLength,
    required this.width,
    required this.hint,
  });

  final TextEditingController controller;
  final int maxLength;
  final double width;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(maxLength),
        ],
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
