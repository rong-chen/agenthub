import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:agenthub/services/skill_service.dart';
import 'package:agenthub/services/agent_service.dart';
import 'package:agenthub/services/gateway_server.dart';
import 'package:agenthub/services/storage_service.dart';

void main(List<String> arguments) async {
  final runner = CommandRunner(
    'agenthub',
    'AgentHub CLI 桌面与后台智能体网关管理工具',
  )
    ..addCommand(SkillsCommand())
    ..addCommand(GatewayCommand());

  try {
    await runner.run(arguments);
  } catch (error) {
    stdout.writeln('执行错误: $error');
    exit(1);
  }
}

/// 技能管理子命令
class SkillsCommand extends Command {
  @override
  final String name = 'skills';
  @override
  final String description = '管理 AgentHub 本地技能';

  SkillsCommand() {
    addSubcommand(SkillsListCommand());
    addSubcommand(SkillsInstallCommand());
    addSubcommand(SkillsRemoveCommand());
  }
}

/// 列出所有技能
class SkillsListCommand extends Command {
  @override
  final String name = 'list';
  @override
  final String description = '查看已安装的本地技能';

  @override
  Future<void> run() async {
    final skillService = SkillService();
    stdout.writeln('正在扫描 AgentHub 技能目录...');
    final skills = await skillService.loadAllSkills();

    if (skills.isEmpty) {
      stdout.writeln('暂无已安装技能。存放目录: ${skillService.globalSkillsPath}');
      return;
    }

    stdout.writeln('已安装技能列表 (${skills.length} 项):');
    for (final skill in skills) {
      final status = skill.isReady ? '就绪' : '缺少依赖';
      stdout.writeln(' - ${skill.name} (v${skill.version}) [$status]');
      stdout.writeln('   说明: ${skill.description}');
      stdout.writeln('   路径: ${skill.directoryPath}');
    }
  }
}

/// 安装技能命令
class SkillsInstallCommand extends Command {
  @override
  final String name = 'install';
  @override
  final String description = '下载并安装技能到 ~/.agenthub/skills';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      stdout.writeln('请提供安装源，例如: agenthub skills install <git-url 或 本地路径>');
      exit(1);
    }

    final source = argResults!.rest.first;
    final skillService = SkillService();
    stdout.writeln('正在下载安装技能: $source ...');
    final result = await skillService.installSkill(source: source);
    stdout.writeln(result);
  }
}

/// 移除技能命令
class SkillsRemoveCommand extends Command {
  @override
  final String name = 'remove';
  @override
  final String description = '卸载指定的技能';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      stdout.writeln('请提供需要卸载的技能名称');
      exit(1);
    }

    final name = argResults!.rest.first;
    final skillService = SkillService();
    final ok = await skillService.uninstallSkill(name);
    if (ok) {
      stdout.writeln('技能 $name 已成功卸载');
    } else {
      stdout.writeln('未找到或无法卸载技能 $name');
    }
  }
}

/// 网关管理子命令
class GatewayCommand extends Command {
  @override
  final String name = 'gateway';
  @override
  final String description = '管理 AgentHub 本地网关服务';

  GatewayCommand() {
    addSubcommand(GatewayStartCommand());
  }
}

/// 启动网关命令
class GatewayStartCommand extends Command {
  @override
  final String name = 'start';
  @override
  final String description = '在当前终端启动本地网关服务';

  GatewayStartCommand() {
    argParser.addOption('port', abbr: 'p', defaultsTo: '18789');
  }

  @override
  Future<void> run() async {
    final portStr = argResults?['port'] as String? ?? '18789';
    final port = int.tryParse(portStr) ?? 18789;

    final skillService = SkillService();
    final agentService = AgentService();
    final storageService = StorageService();
    final config = await storageService.loadConfig();

    final server = GatewayServer(
      skillService: skillService,
      agentService: agentService,
    );

    final skills = await skillService.loadAllSkills();
    stdout.writeln('正在启动 AgentHub 本地网关，端口: $port ...');
    final result = await server.start(
      port: port,
      getConfig: () => config,
      getSkills: () => skills,
    );

    if (!result.isSuccess) {
      stdout.writeln('网关启动失败: ${result.message}');
      exit(1);
    }

    stdout.writeln('AgentHub 本地网关已启动: http://127.0.0.1:$port');
    stdout.writeln('已加载技能: ${skills.length} 项');
    stdout.writeln('按 Ctrl+C 停止服务');

    await ProcessSignal.sigint.watch().first;
    stdout.writeln('正在停止网关服务...');
    await server.stop();
    exit(0);
  }
}
