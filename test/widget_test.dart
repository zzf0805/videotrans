import 'package:flutter_test/flutter_test.dart';
import 'package:videotrans/main.dart';

void main() {
  testWidgets('shows desktop video tool title', (tester) async {
    await tester.pumpWidget(const VideoTransApp(prepareBundle: false));

    expect(find.text('在线视频标准化工具'), findsOneWidget);
    expect(find.textContaining('拖入视频'), findsOneWidget);
  });
}
