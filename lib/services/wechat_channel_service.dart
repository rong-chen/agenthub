import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 微信通道运行状态枚举
enum WechatChannelStatus {
  stopped,
  gettingQr,
  waitingScan,
  connected,
  error,
}

/// 微信消息回调定义
typedef WechatMessageHandler = Future<String?> Function(
  String senderId,
  String senderName,
  String messageText,
);

/// 微信登录授权成功回调定义
typedef WechatAuthSuccessHandler = Future<void> Function(
  String botToken,
  String botName,
);

/// 微信通道服务，对接腾讯官方 iLink 机器人协议
class WechatChannelService {
  static final WechatChannelService instance = WechatChannelService._internal();
  WechatChannelService._internal();

  static const String _ilinkBaseUrl = 'https://ilinkai.weixin.qq.com';
  static const String _botType = '3';

  WechatChannelStatus _status = WechatChannelStatus.stopped;
  String? _qrCodeUrl;
  String? _qrCodeText;
  String? _botToken;
  String? _accountName;
  String? _lastError;
  bool _autoReply = false;

  Timer? _pollTimer;
  bool _isDisposed = false;
  WechatMessageHandler? _messageHandler;
  WechatAuthSuccessHandler? onAuthenticated;
  String _getUpdatesBuf = '';
  final Map<String, String> _userContextTokens = {};
  DateTime? _qrCodeGeneratedAt;

  WechatChannelStatus get status => _status;
  String? get qrCodeUrl => _qrCodeUrl;
  String? get qrCodeText => _qrCodeText;
  String? get accountName => _accountName;
  String? get lastError => _lastError;
  bool get isRunning => _status == WechatChannelStatus.connected;
  bool get autoReply => _autoReply;

  /// 二维码剩余有效秒数
  int get qrCodeRemainingSeconds {
    if (_qrCodeGeneratedAt == null) return 0;
    final passed = DateTime.now().difference(_qrCodeGeneratedAt!).inSeconds;
    final remain = 180 - passed;
    return remain > 0 ? remain : 0;
  }

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// 更新自动回复开关
  void setAutoReply(bool enabled) {
    _autoReply = enabled;
    _notifyListeners();
  }

  /// 使用持久化凭证直接恢复微信连接
  Future<void> restoreSession({
    required String botToken,
    required String botName,
    required bool autoReply,
    required WechatMessageHandler onMessage,
  }) async {
    _isDisposed = false;
    _botToken = botToken;
    _accountName = botName;
    _autoReply = autoReply;
    _messageHandler = onMessage;
    _status = WechatChannelStatus.connected;
    _qrCodeText = null;
    _qrCodeUrl = null;
    _qrCodeGeneratedAt = null;
    _notifyListeners();
    _startMessagePolling();
  }

  /// 启动微信通道
  Future<void> start({
    required bool autoReply,
    required WechatMessageHandler onMessage,
  }) async {
    if (_status == WechatChannelStatus.connected) {
      return;
    }

    _autoReply = autoReply;
    _messageHandler = onMessage;
    await refreshQrCode();
  }

  /// 强制刷新并获取全新二维码
  Future<void> refreshQrCode() async {
    _isDisposed = false;
    _qrCodeUrl = null;
    _qrCodeText = null;
    _qrCodeGeneratedAt = null;
    _lastError = null;
    _status = WechatChannelStatus.gettingQr;
    _notifyListeners();

    try {
      await _requestQrCode();
    } catch (_) {
      _status = WechatChannelStatus.error;
      _lastError = '获取微信登录二维码失败，请检查网络后重试';
      _notifyListeners();
    }
  }

  /// 请求微信登录二维码
  Future<void> _requestQrCode() async {
    final uri = Uri.parse('$_ilinkBaseUrl/ilink/bot/get_bot_qrcode?bot_type=$_botType');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'local_token_list': []}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      _status = WechatChannelStatus.error;
      _lastError = '接口响应异常，状态码: ${response.statusCode}';
      _notifyListeners();
      return;
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final qrcodeKey = data['qrcode']?.toString() ?? data['token']?.toString() ?? '';
    final qrImgContent = data['qrcode_img_content']?.toString() ?? '';
    final qrUrl = data['qrcode_img_url']?.toString();

    _qrCodeUrl = qrUrl;
    _qrCodeText = qrImgContent.isNotEmpty ? qrImgContent : qrcodeKey;
    _qrCodeGeneratedAt = DateTime.now();
    _status = WechatChannelStatus.waitingScan;
    _notifyListeners();

    // 启动长轮询等待扫码结果
    _pollQrScanStatus(qrcodeKey);
  }

  /// 轮询检测二维码扫描状态
  Future<void> _pollQrScanStatus(String tempToken) async {
    while (!_isDisposed && _status == WechatChannelStatus.waitingScan) {
      if (qrCodeRemainingSeconds <= 0 && _qrCodeGeneratedAt != null) {
        _status = WechatChannelStatus.error;
        _lastError = '二维码已过期，请点击下方按钮重新获取';
        _qrCodeText = null;
        _qrCodeGeneratedAt = null;
        _notifyListeners();
        return;
      }

      try {
        final uri = Uri.parse(
          '$_ilinkBaseUrl/ilink/bot/get_qrcode_status?qrcode=${Uri.encodeComponent(tempToken)}&token=${Uri.encodeComponent(tempToken)}&bot_type=$_botType',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 35));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final statusVal = data['status']?.toString();

          if (statusVal == 'confirmed' || statusVal == 'success' || data.containsKey('bot_token')) {
            _botToken = data['bot_token']?.toString() ?? tempToken;
            _accountName = data['bot_name']?.toString() ?? '微信助手';
            _status = WechatChannelStatus.connected;
            _qrCodeText = null;
            _qrCodeUrl = null;
            _qrCodeGeneratedAt = null;
            _notifyListeners();
            if (onAuthenticated != null) {
              await onAuthenticated!(_botToken!, _accountName!);
            }
            // 开始接收微信消息
            _startMessagePolling();
            return;
          }

          if (statusVal == 'expired') {
            _status = WechatChannelStatus.error;
            _lastError = '二维码已过期，请重新获取';
            _qrCodeText = null;
            _qrCodeGeneratedAt = null;
            _notifyListeners();
            return;
          }
        }
      } catch (_) {
        // 网络超时，继续下一轮检测
      }

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  /// 开启长轮询接收微信消息
  void _startMessagePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isDisposed || _status != WechatChannelStatus.connected || _botToken == null) {
        timer.cancel();
        return;
      }
      await _fetchUpdates();
    });
  }

  /// 构建 iLink 鉴权请求头
  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'AuthorizationType': 'ilink_bot_token',
      'Authorization': 'Bearer $_botToken',
      'X-WECHAT-UIN': base64Encode(utf8.encode('100001')),
      'iLink-App-Id': 'bot',
      'iLink-App-ClientVersion': '1',
    };
  }

  /// 提取入站消息文本
  String _extractMessageText(Map item) {
    if (item['text'] != null && item['text'].toString().isNotEmpty) {
      return item['text'].toString();
    }
    if (item['content'] != null && item['content'].toString().isNotEmpty) {
      return item['content'].toString();
    }
    if (item['item_list'] is List) {
      final buffer = StringBuffer();
      for (final sub in item['item_list']) {
        if (sub is Map) {
          if (sub['text_item'] is Map && sub['text_item']['text'] != null) {
            buffer.write(sub['text_item']['text'].toString());
          } else if (sub['text'] != null) {
            buffer.write(sub['text'].toString());
          }
        }
      }
      return buffer.toString();
    }
    return '';
  }

  /// 拉取最新微信消息
  Future<void> _fetchUpdates() async {
    try {
      final uri = Uri.parse('$_ilinkBaseUrl/ilink/bot/getupdates');
      final body = <String, dynamic>{
        'timeout': 5,
      };
      if (_getUpdatesBuf.isNotEmpty) {
        body['get_updates_buf'] = _getUpdatesBuf;
      }

      final res = await http
          .post(
            uri,
            headers: _buildHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map) {
          if (data['get_updates_buf'] != null && data['get_updates_buf'].toString().isNotEmpty) {
            _getUpdatesBuf = data['get_updates_buf'].toString();
          }

          final list = (data['msgs'] as List?) ?? (data['messages'] as List?) ?? [];
          for (final item in list) {
            if (item is Map) {
              final senderId = item['from_user_id']?.toString() ?? 'wx_user';
              final senderName = item['from_user_name']?.toString() ?? '微信用户';
              final contextToken = item['context_token']?.toString() ?? '';
              if (contextToken.isNotEmpty) {
                _userContextTokens[senderId] = contextToken;
              }
              final content = _extractMessageText(item);

              if (content.isNotEmpty && _messageHandler != null) {
                final replyText = await _messageHandler!(senderId, senderName, content);
                if (_autoReply && replyText != null && replyText.isNotEmpty) {
                  await sendReply(senderId, replyText);
                }
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  /// 向微信用户发送回复
  Future<bool> sendReply(String toUserId, String text) async {
    if (_botToken == null || text.trim().isEmpty) {
      return false;
    }

    try {
      final uri = Uri.parse('$_ilinkBaseUrl/ilink/bot/sendmessage');
      final contextToken = _userContextTokens[toUserId] ?? '';

      final body = <String, dynamic>{
        'to': toUserId,
        'to_user_id': toUserId,
        'msg': {
          'from_user_id': '',
          'to_user_id': toUserId,
          'client_id': 'agenthub_${DateTime.now().millisecondsSinceEpoch}',
          'message_type': 2,
          'message_state': 2,
          if (contextToken.isNotEmpty) 'context_token': contextToken,
          'item_list': [
            {
              'type': 1,
              'text_item': {'text': text},
            }
          ],
        },
        if (contextToken.isNotEmpty) 'context_token': contextToken,
        'item_list': [
          {
            'type': 1,
            'text_item': {'text': text},
          }
        ],
        'base_info': {
          'channel_version': '1.0.3',
          'bot_agent': 'AgentHub-Wechat/1.0.0',
        },
      };

      final res = await http.post(
        uri,
        headers: _buildHeaders(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 停止微信通道
  Future<void> stop() async {
    _isDisposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _status = WechatChannelStatus.stopped;
    _qrCodeUrl = null;
    _qrCodeText = null;
    _getUpdatesBuf = '';
    _notifyListeners();
  }
}
