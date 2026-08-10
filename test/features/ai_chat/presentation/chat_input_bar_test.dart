import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_secret_search/features/ai_chat/presentation/chat_input_bar.dart';

void main() {
  testWidgets('sending state exposes stop and does not submit again', (
    tester,
  ) async {
    var sendCount = 0;
    var stopCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            sending: true,
            onSend: (_) async => sendCount++,
            onStop: () async => stopCount++,
          ),
        ),
      ),
    );

    expect(find.text('停止生成'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    await tester.tap(find.text('停止生成'));
    await tester.pump();

    expect(stopCount, 1);
    expect(sendCount, 0);
  });

  testWidgets('idle state submits the entered message', (tester) async {
    String? sent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(onSend: (value) async => sent = value),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  hello  ');
    await tester.tap(find.text('发送'));
    await tester.pump();

    expect(sent, 'hello');
  });
}
