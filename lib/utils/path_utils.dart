import 'dart:io';

/// 跨平台用户主路径工具
class PathUtils {
  /// 获取用户真实主目录
  static String get userHomeDir {
    final envHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (envHome.contains('/Library/Containers/')) {
      final parts = envHome.split('/Library/Containers/');
      return parts.first;
    }
    if (envHome.isNotEmpty) {
      return envHome;
    }
    final user = Platform.environment['USER'] ?? '';
    if (user.isNotEmpty && Platform.isMacOS) {
      return '/Users/$user';
    }
    return Directory.current.path;
  }

  /// 获取 AgentHub 全局存储目录 (~/.agenthub)
  static String get agentHubRootDir {
    final dir = Directory('$userHomeDir/.agenthub');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// 获取 AgentHub 全局技能目录 (~/.agenthub/skills)
  static String get agentHubSkillsDir {
    final dir = Directory('$agentHubRootDir/skills');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }
}
