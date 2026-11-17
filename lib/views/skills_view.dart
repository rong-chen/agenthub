import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/skill_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// 插件与技能管理视图
class SkillsView extends StatefulWidget {
  const SkillsView({super.key});

  @override
  State<SkillsView> createState() => _SkillsViewState();
}

class _SkillsViewState extends State<SkillsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showInstallDialog(BuildContext context) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OpenClawTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OpenClawTheme.border)),
          title: Text('安装插件', style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('安装来源', style: TextStyle(color: OpenClawTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: OpenClawTheme.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: OpenClawTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: OpenClawTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: OpenClawTheme.primaryRed)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('取消', style: TextStyle(color: OpenClawTheme.textSecondary))),
            ElevatedButton(
              onPressed: () async {
                final source = textController.text.trim();
                if (source.isEmpty) return;
                Navigator.of(ctx).pop();
                final provider = context.read<AppStateProvider>();
                await provider.installSkill(source);
              },
              style: ElevatedButton.styleFrom(backgroundColor: OpenClawTheme.primaryRed, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('安装'),
            ),
          ],
        );
      },
    );
  }

  /// 显示插件详情
  void _showSkillDetail(BuildContext context, SkillModel skill) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OpenClawTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OpenClawTheme.border)),
          title: Text(skill.name, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (skill.description.isNotEmpty) ...[
                    Text(skill.description, style: TextStyle(color: OpenClawTheme.textSecondary, fontSize: 13, height: 1.5)),
                    const SizedBox(height: 12),
                  ],
                  Text(skill.instructions.isNotEmpty ? skill.instructions : '无说明内容', style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13, height: 1.5)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('关闭', style: TextStyle(color: OpenClawTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  /// 运行插件
  Future<void> _handleRunSkill(BuildContext context, AppStateProvider provider, SkillModel skill) async {
    final result = await provider.executeSkill(skill);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OpenClawTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OpenClawTheme.border)),
          title: Text(skill.name, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(result, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13, height: 1.5)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('关闭', style: TextStyle(color: OpenClawTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    OpenClawTheme.isDark = provider.isDarkTheme;
    final allSkills = provider.skills;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = allSkills.where((s) {
      if (query.isNotEmpty && !s.name.toLowerCase().contains(query) && !s.description.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    return Container(
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('插件', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: OpenClawTheme.titleRed)),
            const SizedBox(height: 8),
            Text('已加载 ${allSkills.length} 项  已激活 ${allSkills.where((s) => s.isEnabled).length} 项', style: TextStyle(fontSize: 13, color: OpenClawTheme.textSecondary)),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                IconButton(icon: Icon(Icons.refresh, size: 20, color: OpenClawTheme.textSecondary), onPressed: () => provider.reloadSkills()),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showInstallDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('安装'),
                  style: ElevatedButton.styleFrom(backgroundColor: OpenClawTheme.primaryRed, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 38,
              decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: OpenClawTheme.border)),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索',
                  hintStyle: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary),
                  prefixIcon: Icon(Icons.search, size: 18, color: OpenClawTheme.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: OpenClawTheme.border)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
                    child: Row(children: [
                      Expanded(flex: 4, child: Text('名称', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                      Expanded(flex: 2, child: Text('版本', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                      Expanded(flex: 3, child: Text('依赖', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                      SizedBox(width: 120, child: Text('操作', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                    ]),
                  ),
                  if (filtered.isEmpty)
                    Container(padding: const EdgeInsets.symmetric(vertical: 40), alignment: Alignment.center, child: Text('暂无插件', style: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary)))
                  else
                    ...filtered.map((skill) => _buildSkillRow(context, provider, skill)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: OpenClawTheme.divider))),
                    child: Align(alignment: Alignment.centerLeft, child: Text('共 ${filtered.length} 项', style: TextStyle(fontSize: 12, color: OpenClawTheme.textTertiary))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillRow(BuildContext context, AppStateProvider provider, SkillModel skill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: InkWell(
            onTap: () => _showSkillDetail(context, skill),
            child: Row(children: [
              Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: skill.isEnabled ? OpenClawTheme.statusGreen : OpenClawTheme.statusGray, shape: BoxShape.circle)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(skill.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: OpenClawTheme.textPrimary), overflow: TextOverflow.ellipsis),
                  if (skill.description.isNotEmpty)
                    Text(skill.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary)),
                ]),
              ),
            ]),
          ),
        ),
        Expanded(flex: 2, child: Text('v${skill.version}', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
        Expanded(flex: 3, child: Text(skill.requiredBins.isNotEmpty ? skill.requiredBins.join(', ') : '-', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary), overflow: TextOverflow.ellipsis)),
        SizedBox(
          width: 120,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(
              icon: Icon(Icons.play_arrow_outlined, size: 18, color: OpenClawTheme.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _handleRunSkill(context, provider, skill),
            ),
            const SizedBox(width: 6),
            SizedBox(width: 36, height: 20, child: FittedBox(child: Switch(value: skill.isEnabled, activeColor: OpenClawTheme.primaryRed, onChanged: (val) => provider.toggleSkill(skill, val)))),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 16, color: OpenClawTheme.primaryRed),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () async {
                await provider.uninstallSkill(skill.name);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
