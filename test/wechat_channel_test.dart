import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/models/chat_session_model.dart';
import 'package:agenthub/models/gateway_config.dart';
import 'package:agenthub/services/wechat_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('微信通道与未读已读状态测试', () {
    test('ChatSessionModel 未读数与渠道字段正确序列化', () {
      final now = DateTime.now();
      final session = ChatSessionModel(
        id: 'wx_user_001',
        title: '测试微信会话',
        createdAt: now,
        updatedAt: now,
        unreadCount: 3,
        channel: 'wechat',
      );

      final jsonMap = session.toJson();
      expect(jsonMap['id'], 'wx_user_001');
      expect(jsonMap['unreadCount'], 3);
      expect(jsonMap['channel'], 'wechat');

      final reconstructed = ChatSessionModel.fromJson(jsonMap);
      expect(reconstructed.id, 'wx_user_001');
      expect(reconstructed.unreadCount, 3);
      expect(reconstructed.channel, 'wechat');
    });

    test('GatewayConfig 微信通道与自动回复配置测试', () {
      final config = GatewayConfig.initial();
      expect(config.wechatChannelEnabled, false);
      expect(config.wechatAutoReply, false);

      final updated = config.copyWith(
        wechatChannelEnabled: true,
        wechatAutoReply: true,
      );
      expect(updated.wechatChannelEnabled, true);
      expect(updated.wechatAutoReply, true);

      final json = updated.toJson();
      expect(json['wechatChannelEnabled'], true);
      expect(json['wechatAutoReply'], true);
    });

    test('WechatChannelService 状态与自动回复控制', () async {
      final service = WechatChannelService.instance;
      expect(service.status, WechatChannelStatus.stopped);
      expect(service.isRunning, false);

      service.setAutoReply(true);
      expect(service.autoReply, true);

      service.setAutoReply(false);
      expect(service.autoReply, false);

      await service.stop();
      expect(service.status, WechatChannelStatus.stopped);
    });
  });
}
