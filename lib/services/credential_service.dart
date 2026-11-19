import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全凭证存储服务
class CredentialService {
  static final CredentialService instance = CredentialService._internal();
  CredentialService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
    ),
  );

  /// 存储凭证
  Future<void> save(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// 读取凭证
  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  /// 删除凭证
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
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
