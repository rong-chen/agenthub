import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/skill_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// OpenClaw 风格插件与技能管理视图
class SkillsView extends StatefulWidget {
  const SkillsView({super.key});

  @override
  State<SkillsView> createState() => _SkillsViewState();
}

class _SkillsViewState extends State<SkillsView> {
  final TextEditingController _searchController = TextEditingController();
  int _activeTab = 0; // 0: 已安装, 1: 发现

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 打开安装新插件弹窗
  void _showInstallDialog(BuildContext context) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: OpenClawTheme.border),
          ),
          title: const Text(
            '安装新插件',
            style: TextStyle(
              color: OpenClawTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '输入 Git 仓库地址或本地文件夹路径，将自动安装至 ~/.agenthub/skills 目录：',
                  style: TextStyle(color: OpenClawTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: OpenClawTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: OpenClawTheme.border),
                  ),
                  child: TextField(
                    controller: textController,
                    style: const TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'https://github.com/owner/skill-name.git',
                      hintStyle: TextStyle(color: OpenClawTheme.textTertiary, fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消', style: TextStyle(color: OpenClawTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final source = textController.text.trim();
                if (source.isEmpty) {
                  return;
                }
                Navigator.of(ctx).pop();
                final provider = context.read<AppStateProvider>();
                final result = await provider.installSkill(source);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result), duration: const Duration(seconds: 3)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OpenClawTheme.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('下载并安装'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final allSkills = provider.skills;

    final query = _searchController.text.trim().toLowerCase();
    final filteredSkills = allSkills.where((s) {
      if (query.isNotEmpty &&
          !s.name.toLowerCase().contains(query) &&
          !s.description.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      color: OpenClawTheme.background,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow(),
                  const SizedBox(height: 12),
                  _buildStatsRow(allSkills),
                  const SizedBox(height: 16),
                  _buildTabsAndActionRow(context, provider),
                  const SizedBox(height: 16),
                  _buildSearchBar(),
                  const SizedBox(height: 16),
                  _buildSkillsTableCard(context, provider, filteredSkills, allSkills.length),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部标题
  Widget _buildHeaderRow() {
    return const Text(
      '插件',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: OpenClawTheme.titleRed,
      ),
    );
  }

  /// 统计行
  Widget _buildStatsRow(List<SkillModel> skills) {
    final enabledCount = skills.where((s) => s.isEnabled).length;
    return Text(
      '已加载 ${skills.length} 项插件  已激活 $enabledCount 项  存储目录: ~/.agenthub/skills',
      style: const TextStyle(
        fontSize: 13,
        color: OpenClawTheme.textSecondary,
      ),
    );
  }

  /// 选项卡与操作按钮
  Widget _buildTabsAndActionRow(BuildContext context, AppStateProvider provider) {
    return Row(
      children: [
        InkWell(
          onTap: () => setState(() => _activeTab = 0),
          child: Column(
            children: [
              Text(
                '已安装',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.normal,
                  color: _activeTab == 0 ? OpenClawTheme.textPrimary : OpenClawTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 44,
                color: _activeTab == 0 ? OpenClawTheme.primaryRed : Colors.transparent,
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        InkWell(
          onTap: () => setState(() => _activeTab = 1),
          child: Column(
            children: [
              Text(
                '发现更多',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.normal,
                  color: _activeTab == 1 ? OpenClawTheme.textPrimary : OpenClawTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 56,
                color: _activeTab == 1 ? OpenClawTheme.primaryRed : Colors.transparent,
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20, color: OpenClawTheme.textSecondary),
          tooltip: '重新扫描技能目录',
          onPressed: () => provider.reloadSkills(),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _showInstallDialog(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('安装插件'),
          style: ElevatedButton.styleFrom(
            backgroundColor: OpenClawTheme.primaryRed,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  /// 搜索框
  Widget _buildSearchBar() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: OpenClawTheme.border),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: '搜索已安装插件...',
          hintStyle: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary),
          prefixIcon: Icon(Icons.search, size: 18, color: OpenClawTheme.textTertiary),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 9),
        ),
      ),
    );
  }

  /// 纯白卡片表格
  Widget _buildSkillsTableCard(
    BuildContext context,
    AppStateProvider provider,
    List<SkillModel> skills,
    int totalCount,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OpenClawTheme.border),
      ),
      child: Column(
        children: [
          // 表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: OpenClawTheme.divider)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    '插件名称与描述',
                    style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '版本',
                    style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '依赖环境',
                    style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    '操作',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (skills.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: const Text(
                '暂未发现已安装的插件',
                style: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: skills.length,
              separatorBuilder: (_, index) => const Divider(height: 1, color: OpenClawTheme.divider),
              itemBuilder: (ctx, index) {
                final skill = skills[index];
                return _buildSkillRow(context, provider, skill);
              },
            ),
          // 表尾
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: OpenClawTheme.divider)),
            ),
            child: Row(
              children: [
                Text(
                  '${skills.length}项中的 $totalCount项',
                  style: const TextStyle(fontSize: 12, color: OpenClawTheme.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 单个插件行
  Widget _buildSkillRow(
    BuildContext context,
    AppStateProvider provider,
    SkillModel skill,
  ) {
    final bins = skill.requiredBins.isNotEmpty ? skill.requiredBins.join(', ') : '无特殊依赖';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // 插件名称与描述
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: skill.isEnabled ? OpenClawTheme.statusGreen : OpenClawTheme.statusGray,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skill.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: OpenClawTheme.textPrimary,
                        ),
                      ),
                      if (skill.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          skill.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: OpenClawTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 版本
          Expanded(
            flex: 2,
            child: Text(
              'v${skill.version}',
              style: const TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
            ),
          ),
          // 依赖环境
          Expanded(
            flex: 3,
            child: Text(
              bins,
              style: const TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
            ),
          ),
          // 操作开关与删除
          SizedBox(
            width: 90,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: skill.isEnabled,
                    activeThumbColor: OpenClawTheme.primaryRed,
                    onChanged: (val) => provider.toggleSkill(skill, val),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: OpenClawTheme.primaryRed),
                  tooltip: '卸载插件',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    final ok = await provider.uninstallSkill(skill.name);
                    if (!context.mounted) {
                      return;
                    }
                    final msg = ok ? '已卸载插件 ${skill.name}' : '该插件位于工程内置目录，无法直接删除';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
