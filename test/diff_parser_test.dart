import 'package:agenthub/views/components/diff_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test diff parsing with hunk and numbers', () {
    const rawDiff = '''
diff --git a/test.txt b/test.txt
--- a/test.txt
+++ b/test.txt
@@ -124,8 +124,83 @@
 测试文本文件
+Line 6: appended content one
+Line 7: appended content two
+Line 8: 追加的第三行内容
''';

    final files = DiffParser.parse(rawDiff);
    expect(files.length, 1);
    final f = files.first;
    expect(f.filePath, 'test.txt');
    expect(f.additions, 3);
    expect(f.deletions, 0);

    // 检查第 1 行是 hunkHeader，并且记录了 skippedCount
    expect(f.lines[0].type, DiffLineType.hunkHeader);
    expect(f.lines[0].skippedCount, 123);
    // 检查第 2 行是普通上下文行
    expect(f.lines[1].type, DiffLineType.context);
    expect(f.lines[1].oldLineNumber, 124);
    expect(f.lines[1].newLineNumber, 124);
    expect(f.lines[1].text, '测试文本文件');
    // 检查新增行，剥除了加号
    expect(f.lines[2].type, DiffLineType.add);
    expect(f.lines[2].oldLineNumber, isNull);
    expect(f.lines[2].newLineNumber, 125);
    expect(f.lines[2].text, 'Line 6: appended content one');
  });
}
