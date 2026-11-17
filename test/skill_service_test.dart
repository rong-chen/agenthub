import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/models/skill_model.dart';
import 'package:agenthub/services/skill_service.dart';

void main() {
  test('验证 OpenClaw SKILL.md 解析与加载', () async {
    final skillFile = File('skills/system_info/SKILL.md');
    expect(skillFile.existsSync(), true);

    final skill = SkillModel.fromSkillFile(skillFile);
    expect(skill, isNotNull);
    expect(skill!.name, 'system_info');
    expect(skill.description, '获取当前主机系统与环境状态');
    expect(skill.version, '1.0.0');
    expect(skill.requiredBins, contains('uname'));

    final service = SkillService();
    final skills = await service.loadAllSkills();
    expect(skills.any((s) => s.name == 'system_info'), true);

    final systemInfoSkill = skills.firstWhere((s) => s.name == 'system_info');
    expect(systemInfoSkill.isReady, true);
  });
}
