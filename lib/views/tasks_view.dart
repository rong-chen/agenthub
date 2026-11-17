import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_task_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// 定时计划任务视图
class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  final TextEditingController _searchController = TextEditingController();
  int _activeTab = 0; // 0: 自动化, 1: 运行历史
  String _filterStatus = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatRelativeTime(DateTime? dt) {
    if (dt == null) return '不适用';
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) {
      final past = now.difference(dt);
      if (past.inSeconds < 60) return '${past.inSeconds}秒前';
      if (past.inMinutes < 60) return '${past.inMinutes}分钟前';
      if (past.inHours < 24) return '${past.inHours}小时前';
      return '${past.inDays}天前';
    }
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒后';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟后';
    if (diff.inHours < 24) return '${diff.inHours}小时后';
    return '${diff.inDays}天后';
  }

  void _showCreateTaskDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final scheduleCtrl = TextEditingController();
    final commandCtrl = TextEditingController();
    String actionType = 'gateway_check';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: OpenClawTheme.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OpenClawTheme.border)),
            title: Text('新建任务', style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogLabel('任务名称'),
                  const SizedBox(height: 6),
                  _dialogField(nameCtrl, ''),
                  const SizedBox(height: 14),
                  _dialogLabel('执行周期'),
                  const SizedBox(height: 6),
                  _dialogField(scheduleCtrl, ''),
                  const SizedBox(height: 14),
                  _dialogLabel('任务类型'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: actionType,
                    dropdownColor: OpenClawTheme.cardBackground,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: OpenClawTheme.border)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 'gateway_check', child: Text('网关检测')),
                      DropdownMenuItem(value: 'skills_reload', child: Text('插件扫描')),
                      DropdownMenuItem(value: 'shell_cmd', child: Text('系统命令')),
                    ],
                    onChanged: (val) => setDialogState(() => actionType = val ?? 'gateway_check'),
                  ),
                  if (actionType == 'shell_cmd') ...[
                    const SizedBox(height: 14),
                    _dialogLabel('执行内容'),
                    const SizedBox(height: 6),
                    _dialogField(commandCtrl, ''),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('取消', style: TextStyle(color: OpenClawTheme.textSecondary))),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(ctx).pop();
                  final provider = context.read<AppStateProvider>();
                  await provider.addTask(ScheduledTaskModel(
                    id: 'task_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    schedule: scheduleCtrl.text.trim().isNotEmpty ? scheduleCtrl.text.trim() : '*/30 * * * *',
                    actionType: actionType,
                    command: commandCtrl.text.trim(),
                    isEnabled: true,
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: OpenClawTheme.primaryRed, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('新建'),
              ),
            ],
          );
        });
      },
    );
  }

  /// 显示日志详情
  void _showLogDetail(BuildContext context, dynamic log) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: OpenClawTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: OpenClawTheme.border)),
          title: Text(log.taskName, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                log.output.toString().trim().isNotEmpty ? log.output.toString() : '无输出内容',
                style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13, height: 1.5),
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

  Widget _dialogLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 13, color: OpenClawTheme.textSecondary));
  }

  Widget _dialogField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary),
        filled: true,
        fillColor: OpenClawTheme.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: OpenClawTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: OpenClawTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: OpenClawTheme.primaryRed),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final allTasks = provider.tasks;
    final query = _searchController.text.trim().toLowerCase();
    final filteredTasks = allTasks.where((t) {
      if (query.isNotEmpty && !t.name.toLowerCase().contains(query)) return false;
      if (_filterStatus == 'active' && !t.isEnabled) return false;
      if (_filterStatus == 'paused' && t.isEnabled) return false;
      return true;
    }).toList();

    return Container(
      color: OpenClawTheme.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('定时任务', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: OpenClawTheme.titleRed)),
            const SizedBox(height: 8),
            Text(
              '${allTasks.length} 任务  ${allTasks.where((t) => t.lastStatus == 'error').length} 失败  活跃 ${allTasks.where((t) => t.isEnabled).length} 项',
              style: TextStyle(fontSize: 13, color: OpenClawTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            _buildTabsRow(context, provider),
            const SizedBox(height: 16),
            if (_activeTab == 0) ...[
              _buildSearchRow(),
              const SizedBox(height: 16),
              _buildTaskTable(context, provider, filteredTasks, allTasks.length),
            ] else
              _buildRunHistoryTable(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildTabsRow(BuildContext context, AppStateProvider provider) {
    return Row(
      children: [
        _tabItem('自动化', 0),
        const SizedBox(width: 20),
        _tabItem('运行历史', 1),
        const Spacer(),
        IconButton(icon: Icon(Icons.refresh, size: 20, color: OpenClawTheme.textSecondary), onPressed: () => provider.reloadTasks()),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _showCreateTaskDialog(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新建'),
          style: ElevatedButton.styleFrom(backgroundColor: OpenClawTheme.primaryRed, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ],
    );
  }

  Widget _tabItem(String label, int index) {
    final sel = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? OpenClawTheme.textPrimary : OpenClawTheme.textSecondary)),
          const SizedBox(height: 6),
          Container(height: 2, width: label.length * 14.0, color: sel ? OpenClawTheme.primaryRed : Colors.transparent),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: OpenClawTheme.border)),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
              decoration: InputDecoration(hintText: '搜索', hintStyle: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary), prefixIcon: Icon(Icons.search, size: 18, color: OpenClawTheme.textTertiary), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 9)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: OpenClawTheme.pillBackground, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [_filterPill('全部', 'all'), _filterPill('活跃', 'active'), _filterPill('已暂停', 'paused')]),
        ),
      ],
    );
  }

  Widget _filterPill(String label, String value) {
    final sel = _filterStatus == value;
    return InkWell(
      onTap: () => setState(() => _filterStatus = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? OpenClawTheme.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.normal, color: sel ? OpenClawTheme.textPrimary : OpenClawTheme.textSecondary)),
      ),
    );
  }

  Widget _buildTaskTable(BuildContext context, AppStateProvider provider, List<ScheduledTaskModel> tasks, int totalCount) {
    return Container(
      decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: OpenClawTheme.border)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
            child: Row(children: [
              Expanded(flex: 3, child: Text('名称', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('周期', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('类型', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('下次执行', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('上次执行', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              SizedBox(width: 90, child: Text('操作', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
            ]),
          ),
          if (tasks.isEmpty)
            Container(padding: const EdgeInsets.symmetric(vertical: 40), alignment: Alignment.center, child: Text('暂无匹配的任务', style: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary)))
          else
            ...tasks.map((task) => _buildTaskRow(provider, task)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: OpenClawTheme.divider))),
            child: Align(alignment: Alignment.centerLeft, child: Text('共 $totalCount 项', style: TextStyle(fontSize: 12, color: OpenClawTheme.textTertiary))),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(AppStateProvider provider, ScheduledTaskModel task) {
    final statusLabel = {
      'gateway_check': '网关检测',
      'skills_reload': '插件扫描',
      'shell_cmd': '系统命令',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: task.isEnabled ? OpenClawTheme.statusGreen : OpenClawTheme.statusGray, shape: BoxShape.circle)),
            Expanded(child: Text(task.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: OpenClawTheme.textPrimary), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Expanded(flex: 2, child: Text(task.schedule, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary), overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Text(statusLabel[task.actionType] ?? task.actionType, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
        Expanded(flex: 2, child: Text(_formatRelativeTime(task.nextRun), style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary), overflow: TextOverflow.ellipsis)),
        Expanded(
          flex: 2,
          child: Row(children: [
            if (task.lastStatus == 'success') Icon(Icons.check, size: 14, color: OpenClawTheme.statusGreen),
            if (task.lastStatus == 'error') Icon(Icons.close, size: 14, color: OpenClawTheme.primaryRed),
            const SizedBox(width: 4),
            Expanded(child: Text(_formatRelativeTime(task.lastRun), style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary), overflow: TextOverflow.ellipsis)),
          ]),
        ),
        SizedBox(
          width: 90,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(icon: Icon(Icons.play_arrow_outlined, size: 18, color: OpenClawTheme.textSecondary), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => provider.triggerTask(task.id)),
            const SizedBox(width: 4),
            SizedBox(
              width: 36,
              height: 20,
              child: FittedBox(
                child: Switch(value: task.isEnabled, activeColor: OpenClawTheme.primaryRed, onChanged: (val) => provider.toggleTask(task.id, val)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(icon: Icon(Icons.delete_outline, size: 16, color: OpenClawTheme.textTertiary), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => provider.removeTask(task.id)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildRunHistoryTable(AppStateProvider provider) {
    final logs = provider.taskLogs;
    return Container(
      decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: OpenClawTheme.border)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
            child: Row(children: [
              Expanded(flex: 3, child: Text('任务', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 3, child: Text('执行时间', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('耗时', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
              Expanded(flex: 2, child: Text('状态', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
            ]),
          ),
          if (logs.isEmpty)
            Container(padding: const EdgeInsets.symmetric(vertical: 40), alignment: Alignment.center, child: Text('暂无运行记录', style: TextStyle(fontSize: 13, color: OpenClawTheme.textTertiary)))
          else
            ...logs.take(50).map((log) {
              return InkWell(
                onTap: () => _showLogDetail(context, log),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: OpenClawTheme.divider))),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(log.taskName, style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary), overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text(_formatRelativeTime(log.executedAt), style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                    Expanded(flex: 2, child: Text('${log.durationMs}ms', style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary))),
                    Expanded(
                      flex: 2,
                      child: Row(children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: log.isSuccess ? OpenClawTheme.statusGreen : OpenClawTheme.primaryRed, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(log.isSuccess ? '成功' : '失败', style: TextStyle(fontSize: 12, color: log.isSuccess ? OpenClawTheme.statusGreen : OpenClawTheme.primaryRed)),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: OpenClawTheme.divider))),
            child: Align(alignment: Alignment.centerLeft, child: Text('共 ${logs.length} 条记录', style: TextStyle(fontSize: 12, color: OpenClawTheme.textTertiary))),
          ),
        ],
      ),
    );
  }
}
