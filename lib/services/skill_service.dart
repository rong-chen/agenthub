import 'dart:io';
import '../models/skill_model.dart';
import '../utils/path_utils.dart';

/// 技能管理服务，负责扫描、下载安装、解析与执行 AgentHub 技能
class SkillService {
  /// 获取全局默认技能存放目录 (~/.agenthub/skills)
  String get globalSkillsPath => PathUtils.agentHubSkillsDir;

  /// 扫描并获取所有已安装技能
  Future<List<SkillModel>> loadAllSkills({String? customPath}) async {
    final searchDirs = _resolveSkillDirectories(customPath: customPath);
    final List<SkillModel> results = [];
    final Set<String> loadedSkillNames = {};

    for (final dirPath in searchDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        continue;
      }

      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is! Directory) {
          continue;
        }

        final skill = _loadSingleSkillFromDir(entity);
        if (skill == null) {
          continue;
        }

        if (loadedSkillNames.contains(skill.name)) {
          continue;
        }

        await _checkSkillDependencies(skill);
        results.add(skill);
        loadedSkillNames.add(skill.name);
      }
    }

    return results;
  }

  /// 解析技能搜索路径
  List<String> _resolveSkillDirectories({String? customPath}) {
    final List<String> paths = [];

    if (customPath != null && customPath.trim().isNotEmpty) {
      paths.add(customPath.trim());
    }

    final globalDir = Directory(globalSkillsPath);
    if (!globalDir.existsSync()) {
      globalDir.createSync(recursive: true);
    }
    paths.add(globalSkillsPath);

    return paths;
  }

  /// 从指定文件夹解析单个技能
  SkillModel? _loadSingleSkillFromDir(Directory dir) {
    final skillMdFile = File('${dir.path}/SKILL.md');
    if (skillMdFile.existsSync()) {
      return SkillModel.fromSkillFile(skillMdFile);
    }

    final lowerSkillMdFile = File('${dir.path}/skill.md');
    if (lowerSkillMdFile.existsSync()) {
      return SkillModel.fromSkillFile(lowerSkillMdFile);
    }

    return null;
  }

  /// 检查技能依赖的命令行工具与环境变量
  Future<void> _checkSkillDependencies(SkillModel skill) async {
    final List<String> missingBins = [];
    final List<String> missingEnvs = [];

    for (final bin in skill.requiredBins) {
      final isFound = await _isBinaryAvailable(bin);
      if (!isFound) {
        missingBins.add(bin);
      }
    }

    for (final env in skill.requiredEnvs) {
      final val = Platform.environment[env];
      if (val == null || val.isEmpty) {
        missingEnvs.add(env);
      }
    }

    skill.missingBins = missingBins;
    skill.missingEnvs = missingEnvs;
  }

  /// 校验系统是否存在特定可执行命令
  Future<bool> _isBinaryAvailable(String binName) async {
    final checker = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(checker, [binName]);
      if (result.exitCode == 0) {
        return true;
      }
      // Windows 环境下系统信息命令兼容处理
      if (Platform.isWindows && binName == 'uname') {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 安装技能到 AgentHub 技能目录 (~/.agenthub/skills)
  Future<String> installSkill({required String source}) async {
    final cleanSource = source.trim();
    if (cleanSource.isEmpty) {
      return '安装源不可为空';
    }

    final globalDir = Directory(globalSkillsPath);
    if (!globalDir.existsSync()) {
      globalDir.createSync(recursive: true);
    }

    // 判断是否为本地目录
    final localDir = Directory(cleanSource);
    if (localDir.existsSync()) {
      return _installFromLocalDirectory(localDir);
    }

    // 远程 Git 仓库或短地址
    return _installFromGit(cleanSource);
  }

  /// 从本地文件夹复制安装
  Future<String> _installFromLocalDirectory(Directory sourceDir) async {
    final skillName = sourceDir.path.split(Platform.pathSeparator).last;
    final targetPath = '$globalSkillsPath/$skillName';
    final targetDir = Directory(targetPath);

    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    await _copyDirectory(sourceDir, targetDir);

    final skillMd = File('$targetPath/SKILL.md');
    final lowerSkillMd = File('$targetPath/skill.md');
    if (!skillMd.existsSync() && !lowerSkillMd.existsSync()) {
      return '安装完成，但目录中缺少 SKILL.md 文件';
    }

    return '技能 $skillName 已成功安装到 $targetPath';
  }

  /// 从 Git 仓库拉取安装
  Future<String> _installFromGit(String gitUrl) async {
    String cloneUrl = gitUrl;
    if (!gitUrl.startsWith('http://') && !gitUrl.startsWith('https://') && !gitUrl.startsWith('git@')) {
      cloneUrl = 'https://github.com/$gitUrl.git';
    }

    final rawName = cloneUrl.split('/').last.replaceAll('.git', '');
    final targetPath = '$globalSkillsPath/$rawName';
    final targetDir = Directory(targetPath);

    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }

    try {
      final result = await Process.run('git', [
        'clone',
        '--depth=1',
        cloneUrl,
        targetPath,
      ]);

      if (result.exitCode != 0) {
        return 'Git 拉取失败: ${result.stderr}';
      }

      final skillMd = File('$targetPath/SKILL.md');
      final lowerSkillMd = File('$targetPath/skill.md');
      if (!skillMd.existsSync() && !lowerSkillMd.existsSync()) {
        return '拉取成功，但目标目录中未找到 SKILL.md 规范文件';
      }

      return '技能 $rawName 安装成功';
    } catch (e) {
      return '执行 Git 命令出错: $e';
    }
  }

  /// 卸载技能
  Future<bool> uninstallSkill(String skillName) async {
    final targetPath = '$globalSkillsPath/$skillName';
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      return false;
    }

    try {
      targetDir.deleteSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 递归复制目录
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    final entities = source.listSync(recursive: false);
    for (final entity in entities) {
      final newPath = '${destination.path}/${entity.path.split(Platform.pathSeparator).last}';
      if (entity is Directory) {
        final subDir = Directory(newPath);
        subDir.createSync(recursive: true);
        await _copyDirectory(entity, subDir);
        continue;
      }

      if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }

  /// 执行技能
  Future<String> runSkill(SkillModel skill, [String? customCommand]) async {
    try {
      final String cmd;
      if (customCommand != null && customCommand.trim().isNotEmpty) {
        cmd = customCommand.trim();
      } else if (skill.name == 'system_info') {
        cmd = Platform.isWindows
            ? 'powershell -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object Caption, OSArchitecture, Version | Format-List"'
            : 'uname -a';
      } else {
        // 从说明中提取首个命令，或使用默认命令
        final match = RegExp(r'`([^`]+)`').firstMatch(skill.instructions);
        cmd = match != null ? match.group(1)!.trim() : 'echo "ok"';
      }

      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'cmd.exe',
          ['/c', cmd],
          workingDirectory: skill.directoryPath,
          environment: Platform.environment,
        );
      } else {
        result = await Process.run(
          'sh',
          ['-c', cmd],
          workingDirectory: skill.directoryPath,
          environment: Platform.environment,
        );
      }

      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();

      if (result.exitCode != 0) {
        return stderrText.isNotEmpty ? stderrText : '执行未完成';
      }

      return stdoutText.isNotEmpty ? stdoutText : '执行完成';
    } catch (_) {
      return '执行未完成';
    }
  }

  /// 创建新本地插件
  Future<bool> createSkill({
    required String name,
    required String description,
    required String instructions,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;

    final targetPath = '$globalSkillsPath/$cleanName';
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final skillMd = File('$targetPath/SKILL.md');
    final content = '''---
name: $cleanName
description: $description
version: 1.0.0
---

# $cleanName

$instructions
''';
    await skillMd.writeAsString(content);
    return true;
  }

  /// 执行技能命令
  Future<String> executeSkillCommand({
    required SkillModel skill,
    required String command,
    List<String> args = const [],
  }) async {
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'cmd.exe',
          ['/c', command, ...args],
          workingDirectory: skill.directoryPath,
          environment: Platform.environment,
        );
      } else {
        result = await Process.run(
          command,
          args,
          workingDirectory: skill.directoryPath,
          environment: Platform.environment,
        );
      }

      final stdoutText = result.stdout.toString().trim();
      final stderrText = result.stderr.toString().trim();

      if (result.exitCode != 0) {
        return stderrText.isNotEmpty ? stderrText : '执行未完成';
      }

      return stdoutText.isNotEmpty ? stdoutText : '执行完成';
    } catch (_) {
      return '执行未完成';
    }
  }
}
