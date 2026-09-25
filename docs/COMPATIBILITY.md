# 写入兼容性实测

> 每次修改 `Sources/SayKuku/TextInteraction.swift` 后，都要在真机上重跑下表的全部应用并更新结果。表中只能填写真机实测结果，没测过的格子保持「待测」。

应用列表来自 [SayKuku.md](../SayKuku.md) 第 18.6 节的兼容性矩阵。

## 结果

测试日期：待测　SayKuku 提交：待测

| 应用 | macOS 版本 | 插入路径（AX / 粘贴） | 是否 verified | 撤销是否可用 | 纠错检测是否触发 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| TextEdit | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Notes | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Mail（写邮件正文） | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Safari（网页 textarea） | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Chrome（网页 textarea） | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Slack（消息输入框） | 待测 | 待测 | 待测 | 待测 | 待测 | |
| VS Code（编辑器） | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Microsoft Word | 待测 | 待测 | 待测 | 待测 | 待测 | |
| Terminal | 待测 | 待测 | 待测 | 待测 | 待测 | |
| 密码输入框（Secure Text Field） | 待测 | 待测 | 待测 | 待测 | 待测 | 预期拒绝写入，提示不支持密码输入框 |

各列含义：

- **插入路径**：日志里的 `route`。`accessibility` 记为 AX，`paste` 记为粘贴。
- **是否 verified**：日志里的 `result`。`verified` 记「是」，`deliveredUnverified` 记「否」；失败时照抄 `result` 的值。
- **撤销是否可用**：写入后浮层是否出现「撤销」按钮，点击后是否恰好还原为写入前的文本。
- **纠错检测是否触发**：写入后在 5 秒内手动改掉一个词，「记忆」页是否出现对应的纠正建议。
- **备注**：重复插入、光标位置异常、剪贴板没有恢复等任何异常。

## 如何跑

1. 在 Mac 上构建开发包并启动：

   ```bash
   Scripts/package-app.sh debug
   open Build/SayKuku.app
   ```

   确认已授予麦克风与辅助功能权限，并在「记忆」页打开「从纠正中学习」。

2. 在另一个终端窗口里看写入日志（开发包的 subsystem 是 `com.saykuku.dev`）：

   ```bash
   log stream --level info \
     --predicate 'subsystem == "com.saykuku.dev" AND category == "TextInteraction" AND eventMessage BEGINSWITH "Text write"'
   ```

   每次写入结束会打印一行 `Text write bundle=… route=… result=…`，日志不含文本内容。

3. 对表中每个应用依次做下面几步：
   1. 在一段已有文字的中间放好光标，用语音输入说一句中英混合的短句。
   2. 核对文本只插入了一次、位置正确，并记下日志中的 `route` 与 `result`。
   3. 选中一个词再说一句，确认替换选区时同样只插入一次。
   4. 再说一句，写入后立刻把其中一个词改掉，5 秒后到「记忆」页查看是否出现纠正建议。
   5. 再说一句，点击浮层上的「撤销」，确认文本恢复原样；没有「撤销」按钮就记「否」。
   6. 在「关于本机」里查看 macOS 版本号并填表；有应用版本差异时写进备注。

4. 把测试日期和 SayKuku 的提交哈希（`git rev-parse --short HEAD`）填到表格上方，连同结果一起提交。
