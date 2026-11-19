/// Claude Code 环境信息模型
class ClaudeEnvInfo {
  final bool isInstalled;
  final String? version;
  final String? executablePath;
  final String? nodeVersion;
  final String configDir;

  const ClaudeEnvInfo({
    required this.isInstalled,
    this.version,
    this.executablePath,
    this.nodeVersion,
    this.configDir = '',
  });

  ClaudeEnvInfo copyWith({
    bool? isInstalled,
    String? version,
    String? executablePath,
    String? nodeVersion,
    String? configDir,
  }) {
    return ClaudeEnvInfo(
      isInstalled: isInstalled ?? this.isInstalled,
      version: version ?? this.version,
      executablePath: executablePath ?? this.executablePath,
      nodeVersion: nodeVersion ?? this.nodeVersion,
      configDir: configDir ?? this.configDir,
    );
  }
}
