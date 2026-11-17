import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/models/skill_model.dart';
import 'package:agenthub/services/skill_service.dart';

void main() {
  test('验证 AgentHub SKILL.md 解析与加载', () async {
    final tempDir = await Directory.systemTemp.createTemp('agenthub_skill_test_');
    try {
      final sampleDir = Directory('${tempDir.path}/sample_skill');
      sampleDir.createSync(recursive: true);
      final skillFile = File('${sampleDir.path}/SKILL.md');
      await skillFile.writeAsString('''---
name: sample_skill
description: 获取当前主机系统与环境状态
version: 1.0.0
metadata:
  agenthub:
    requires:
      bins:
        - uname
---
# 示例说明
''');

      final skill = SkillModel.fromSkillFile(skillFile);
      expect(skill, isNotNull);
      expect(skill!.name, 'sample_skill');
      expect(skill.description, '获取当前主机系统与环境状态');
      expect(skill.version, '1.0.0');
      expect(skill.requiredBins, contains('uname'));

      final service = SkillService();
      final skills = await service.loadAllSkills(customPath: tempDir.path);
      expect(skills.any((s) => s.name == 'sample_skill'), true);
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });
}
