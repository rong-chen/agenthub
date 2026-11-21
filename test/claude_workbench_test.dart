import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/models/attachment.dart';
import 'package:agenthub/models/claude_env_info.dart';
import 'package:agenthub/models/claude_profile.dart';
import 'package:agenthub/services/attachment_service.dart';

void main() {
  group('账号管理模型与服务测试', () {
    test('ClaudeEnvInfo 初始与 copyWith 测试', () {
      const info = ClaudeEnvInfo(
        isInstalled: true,
        version: '1.0.33',
        executablePath: '/usr/local/bin/claude',
        nodeVersion: 'v20.10.0',
      );

      expect(info.isInstalled, isTrue);
      expect(info.version, '1.0.33');

      final updated = info.copyWith(version: '1.0.34');
      expect(updated.version, '1.0.34');
      expect(updated.executablePath, '/usr/local/bin/claude');
    });

    test('ClaudeProfile toMap 与 fromMap 序列化测试', () {
      final now = DateTime.now();
      final profile = ClaudeProfile(
        id: 'prof_test_1',
        name: 'mimo',
        remark: '公司账号',
        websiteUrl: 'https://api.xiaomimimo.com',
        authType: 'api_key',
        apiKeyRef: 'key_123',
        apiBaseUrl: 'https://api.xiaomimimo.com/anthropic',
        configDir: '/path/to/config',
        sonnetMapping: ClaudeModelRoleMapping(displayName: 'mimo-v2.6-pro', actualModel: 'mimo-v2.6-pro', is1M: true),
        maxThinking: true,
        enableToolSearch: true,
        createdAt: now,
        lastUsedAt: now,
      );

      final map = profile.toMap();
      expect(map['id'], 'prof_test_1');
      expect(map['name'], 'mimo');
      expect(map['api_base_url'], 'https://api.xiaomimimo.com/anthropic');

      final restored = ClaudeProfile.fromMap(map);
      expect(restored.id, 'prof_test_1');
      expect(restored.name, 'mimo');
      expect(restored.sonnetMapping.actualModel, 'mimo-v2.6-pro');
      expect(restored.sonnetMapping.is1M, isTrue);

      final settings = restored.generateSettingsJson('test_token');
      expect(settings['env']['ANTHROPIC_BASE_URL'], 'https://api.xiaomimimo.com/anthropic');
      expect(settings['env']['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'mimo-v2.6-pro[1M]');
      expect(settings['env']['MAX_THINKING_TOKENS'], '31999');
      expect(settings['enableToolSearch'], isTrue);
    });

    test('AttachmentService 文件分类与 Prompt 拼接测试', () {
      final service = AttachmentService.instance;

      expect(service.resolveType('photo.png'), AttachmentType.image);
      expect(service.resolveType('code.dart'), AttachmentType.code);
      expect(service.resolveType('notes.md'), AttachmentType.document);
      expect(service.resolveType('data.txt'), AttachmentType.document);

      const attImage = Attachment(
        id: '1',
        originalPath: '/tmp/ui.png',
        stagedPath: '/work/.agenthub_assets/ui.png',
        fileName: 'ui.png',
        fileSize: 2048,
        type: AttachmentType.image,
      );

      const attDoc = Attachment(
        id: '2',
        originalPath: '/tmp/spec.md',
        stagedPath: '/work/.agenthub_assets/spec.md',
        fileName: 'spec.md',
        fileSize: 1024,
        type: AttachmentType.document,
      );

      final prompt = service.buildPromptWithAttachments(
        userText: '请实现该需求',
        attachments: [attImage, attDoc],
      );

      expect(prompt.contains('请实现该需求'), isTrue);
      expect(prompt.contains('/work/.agenthub_assets/ui.png'), isTrue);
      expect(prompt.contains('/work/.agenthub_assets/spec.md'), isTrue);
    });
  });
}
