# 修复代码模式下回复空白与目录名缺失问题

## 原因排查

1. 缺少必要命令行参数
- Claude Code 的 --output-format=stream-json 模式必须配合 --verbose 参数运行，此前缺少 --verbose 导致 CLI 启动即报错退出。

2. 会话 ID 误传问题
- 之前实例初始化时将 App 的会话 ID 误作为 Claude Code 的会话 ID 传入了 --resume，导致 CLI 因找不到该会话而退出。
- 修复后初始不带 --resume，等待 Claude 进程初次返回真实 UUID 后再记录并复用。

3. 输出流事件未派发
- executeTask 未使用 StreamController 向调用者分发事件，导致消息消费端收不到输出文本。
- 完善了 StreamController 分发体系及 ClaudeStreamEvent 对 message.content 数组与工具调用的解析。

4. 目录名截取与空白气泡交互优化
- 路径末尾斜杠导致目录名为空的问题已修复。
- 空白气泡增加加载状态与思考提示，杜绝无响应小方框现象。
