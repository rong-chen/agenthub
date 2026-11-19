import 'dart:io';
import '../models/claude_env_info.dart';

/// Claude Code 运行环境检测服务
class ClaudeEnvService {
  static final ClaudeEnvService instance = ClaudeEnvService._internal();
  ClaudeEnvService._internal();

  /// 探测本机 Claude Code 及 Node.js 安装状态与路径
  Future<ClaudeEnvInfo> detectEnvironment() async {
    final execPath = await _findExecutablePath();
    final isInstalled = execPath != null && execPath.isNotEmpty;

    String? version;
    if (isInstalled) {
      version = await _getVersion(execPath);
    }

    final nodeVersion = await _getNodeVersion();
    final defaultClaudeDir = '${Platform.environment['HOME'] ?? ''}/.claude';

    return ClaudeEnvInfo(
      isInstalled: isInstalled,
      version: version,
      executablePath: execPath,
      nodeVersion: nodeVersion,
      configDir: defaultClaudeDir,
    );
  }

  /// 检索 claude 命令完整路径
  Future<String?> _findExecutablePath() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final arg = 'claude';

    try {
      final res = await Process.run(cmd, [arg], runInShell: true);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().split('\n').first.trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      }
    } catch (_) {}

    // 备用常见路径检测
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '/usr/local/bin/claude',
      '/opt/homebrew/bin/claude',
      '$home/.nvm/versions/node/*/bin/claude',
      '$home/.npm-global/bin/claude',
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }

    return null;
  }

  /// 获取版本信息
  Future<String?> _getVersion(String executablePath) async {
    try {
      final res = await Process.run(executablePath, ['--version'], runInShell: true);
      if (res.exitCode == 0) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  /// 获取 Node.js 版本信息
  Future<String?> _getNodeVersion() async {
    try {
      final res = await Process.run('node', ['-v'], runInShell: true);
      if (res.exitCode == 0) {
        return res.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }
}
