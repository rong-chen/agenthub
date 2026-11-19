# 修复拼音输入法回车键冲突、内容覆盖与思考状态卡片

## 修改项

1. 拼音输入状态下 Enter 键选词支持
- 在 TextField 的 Focus.onKeyEvent 中检测 `_inputController.value.isComposingRangeValid`。
- 当处于拼音输入法组合候选词阶段时，忽略 Enter 键分发，交由系统输入法完成第一候选词上屏，彻底解决打拼音时回车直接触发发送的体验问题。

2. 去除生硬提示并保障内容完整性
- 彻底移除“任务已执行完成”等无意义死板气泡占位。
- 任务执行成功时直接把 Claude Code 真实返回的 Markdown 正文完整渲染给用户。
- 优化了流式文本拼接逻辑，对于前后发出的多个文本段落采用段落追加策略，杜绝后置消息盲目覆盖前置消息。

3. 增加思考过程状态卡片
- ChatMessageModel 与 ClaudeStreamEvent 支持 thinking 字段与 isThinking 状态。
- 在消息气泡上方以可折叠卡片呈现思考过程（深度思考中... / 已完成思考），点击可展开查阅思考细节。

4. 彻底支持任务取消
- 优化了停止/取消操作，点击停止时彻底终止底层的 Claude Code 进程实例，打断数据流并重置状态。
