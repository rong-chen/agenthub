import 'database_service.dart';

/// 安全凭证存储服务
/// 基于本地 SQLite 数据库存储敏感凭证，彻底杜绝 macOS 系统钥匙串频繁弹窗拦截
class CredentialService {
  static final CredentialService instance = CredentialService._internal();
  CredentialService._internal();

  final DatabaseService _db = DatabaseService.instance;

  /// 存储凭证
  Future<void> save(String key, String value) async {
    await _db.saveCredential(key, value);
  }

  /// 读取凭证
  Future<String?> read(String key) async {
    return await _db.getCredential(key);
  }

  /// 删除凭证
  Future<void> delete(String key) async {
    await _db.deleteCredential(key);
  }

  /// 存储指定 Profile 的授权密钥
  Future<void> saveProfileApiKey(String profileId, String apiKey) async {
    await save('claude_profile_key_$profileId', apiKey);
  }

  /// 读取指定 Profile 的授权密钥
  Future<String?> readProfileApiKey(String profileId) async {
    return await read('claude_profile_key_$profileId');
  }

  /// 删除指定 Profile 的授权密钥
  Future<void> deleteProfileApiKey(String profileId) async {
    await delete('claude_profile_key_$profileId');
  }
}
