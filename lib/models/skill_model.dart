import 'dart:io';
import 'package:yaml/yaml.dart';

/// 技能数据模型，对应 AgentHub 的 SKILL.md 规范
class SkillModel {
  final String name;
  final String description;
  final String version;
  final List<String> requiredBins;
  final List<String> requiredEnvs;
  final String instructions;
  final String directoryPath;
  bool isEnabled;
  List<String> missingBins;
  List<String> missingEnvs;

  SkillModel({
    required this.name,
    required this.description,
    required this.version,
    required this.requiredBins,
    required this.requiredEnvs,
    required this.instructions,
    required this.directoryPath,
    this.isEnabled = true,
    this.missingBins = const [],
    this.missingEnvs = const [],
  });

  /// 检查技能依赖是否全部满足
  bool get isReady => missingBins.isEmpty && missingEnvs.isEmpty;

  /// 从 SKILL.md 文件内容解析生成模型
  static SkillModel? fromSkillFile(File file) {
    if (!file.existsSync()) {
      return null;
    }

    final content = file.readAsStringSync();
    final parts = content.split('---');
    if (parts.length < 3) {
      return null;
    }

    final yamlContent = parts[1];
    final markdownBody = parts.sublist(2).join('---').trim();

    final dynamic yamlMap = loadYaml(yamlContent);
    if (yamlMap is! Map) {
      return null;
    }

    final name = yamlMap['name']?.toString() ?? file.parent.path.split(Platform.pathSeparator).last;
    final description = yamlMap['description']?.toString() ?? '';
    final version = yamlMap['version']?.toString() ?? '1.0.0';

    final List<String> requiredBins = [];
    final List<String> requiredEnvs = [];

    final metadata = yamlMap['metadata'];
    Map? requiresMap;

    if (metadata is Map) {
      final pluginMeta = metadata['openclaw'] ?? metadata['agenthub'];
      if (pluginMeta is Map && pluginMeta['requires'] is Map) {
        requiresMap = pluginMeta['requires'] as Map;
      } else if (metadata['requires'] is Map) {
        requiresMap = metadata['requires'] as Map;
      }
    } else if (yamlMap['requires'] is Map) {
      requiresMap = yamlMap['requires'] as Map;
    }

    if (requiresMap != null) {
      final bins = requiresMap['bins'];
      if (bins is List) {
        for (final item in bins) {
          requiredBins.add(item.toString());
        }
      }
      final envs = requiresMap['env'];
      if (envs is List) {
        for (final item in envs) {
          requiredEnvs.add(item.toString());
        }
      }
    }

    return SkillModel(
      name: name,
      description: description,
      version: version,
      requiredBins: requiredBins,
      requiredEnvs: requiredEnvs,
      instructions: markdownBody,
      directoryPath: file.parent.path,
    );
  }

  /// 转换为 JSON 格式
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'version': version,
      'requiredBins': requiredBins,
      'requiredEnvs': requiredEnvs,
      'instructions': instructions,
      'directoryPath': directoryPath,
      'isEnabled': isEnabled,
    };
  }
}
