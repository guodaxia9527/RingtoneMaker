import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/widgets/tail_filename.dart';

void main() {
  testWidgets('long names retain their suffix and full accessible name', (
    tester,
  ) async {
    const name = '很长的文件夹前缀_录音_资料🧑‍💻_会议记录_整理版本_ending.m4a';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: TailFilename(name: name, style: TextStyle(fontSize: 17)),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text, startsWith('…'));
    expect(text, endsWith('ending.m4a'));
    expect(find.byTooltip(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('short names are displayed unchanged', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TailFilename(name: '录音.m4a', style: TextStyle(fontSize: 17)),
        ),
      ),
    );
    expect(find.text('录音.m4a'), findsOneWidget);
  });
}
