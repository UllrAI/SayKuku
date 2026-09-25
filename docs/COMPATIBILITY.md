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
- **纠错检测是否触发**：写入后在 5 秒内手动改掉一个词，浮层是否出现「把“X”记为“Y”？」及「以后再说 / 记住」按钮。
- **备注**：重复插入、光标位置异常、剪贴板没有恢复等任何异常。

## 如何跑

1. 在 Mac 上构建开发包并启动：

   ```bash
   Scripts/package-app.sh debug
   open Build/SayKuku.app
   ```

   确认已授予麦克风与辅助功能权限，并在「设置 › 语音输入」打开「从纠正中学习」。再到「设置 › 历史」确认「保留历史」没有选「不保存」，否则不会产生记录。

2. 在另一个终端窗口里看写入日志（开发包的 subsystem 是 `com.saykuku.dev`）：

   ```bash
   log stream --level info \
     --predicate 'subsystem == "com.saykuku.dev" AND category == "TextInteraction" AND eventMessage BEGINSWITH "Text write"'
   ```

   每次写入结束会打印一行 `Text write bundle=… route=… result=…`，日志不含文本内容。去掉 `category` 和 `eventMessage` 两个条件，就能看到音频引擎、Qwen 连接、本地存储、快捷键和权限等全部子系统的日志。

3. 对表中每个应用依次做下面几步：
   1. 在一段已有文字的中间放好光标，用语音输入说一句中英混合的短句。
   2. 核对文本只插入了一次、位置正确，并记下日志中的 `route` 与 `result`。
   3. 选中一个词再说一句，确认替换选区时同样只插入一次。
   4. 再说一句，写入后立刻把其中一个词改掉，约 5 秒后看浮层是否问「把“X”记为“Y”？」；点「以后再说」或等它消失后，到「记忆」页的「建议」区确认它还在。
   5. 再说一句，点击浮层上的「撤销」，确认文本恢复原样；没有「撤销」按钮就记「否」。
   6. 在「关于本机」里查看 macOS 版本号并填表；有应用版本差异时写进备注。

4. 把测试日期和 SayKuku 的提交哈希（`git rev-parse --short HEAD`）填到表格上方，连同结果一起提交。

## Fn 到 Pill 延迟

> SayKuku.md 第 18.6 节要求「Fn UI 首次反馈 P95 < 100 ms」；按 issue #64 的验收标准，蓝牙麦克风下为 < 300 ms。修改 `VoiceWorkflow.beginVoiceWorkflow`、`AudioCapture` 或 `TextInteraction.captureTarget` 后要重测。同样只填真机结果，没测过的格子保持「待测」。

测试日期：待测　SayKuku 提交：待测　macOS 版本：待测

每格填 P95，单位 ms。

| 应用 | 麦克风类型 | captureTarget | audio start | realtime connect | Fn→Pill 总计 |
| --- | --- | --- | --- | --- | --- |
| TextEdit | 内建 | 待测 | 待测 | 待测 | 待测 |
| TextEdit | 蓝牙 | 待测 | 待测 | 待测 | 待测 |
| Notes | 内建 | 待测 | 待测 | 待测 | 待测 |
| Mail（写邮件正文） | 内建 | 待测 | 待测 | 待测 | 待测 |
| Safari（网页 textarea） | 内建 | 待测 | 待测 | 待测 | 待测 |
| Safari（网页 textarea） | 蓝牙 | 待测 | 待测 | 待测 | 待测 |
| Chrome（网页 textarea） | 内建 | 待测 | 待测 | 待测 | 待测 |
| Slack（消息输入框） | 内建 | 待测 | 待测 | 待测 | 待测 |
| Slack（消息输入框） | 蓝牙 | 待测 | 待测 | 待测 | 待测 |
| VS Code（编辑器） | 内建 | 待测 | 待测 | 待测 | 待测 |
| Microsoft Word | 内建 | 待测 | 待测 | 待测 | 待测 |
| Terminal | 内建 | 待测 | 待测 | 待测 | 待测 |

各列对应的 signpost 区间（subsystem 是 Bundle ID，category 是 `Performance`）：

- **captureTarget**：主线程读取目标 App 的焦点元素、窗口和文本框。
- **audio start**：在采集队列上新建音频引擎并 `prepare`、`start`，和 captureTarget 同时进行。
- **realtime connect**：Pill 出现后建立 Realtime 连接，不计入 Fn→Pill；连上之前录到的音频先缓冲，不会丢。没填业务空间 ID 时听写走整段识别，没有这一段。
- **Fn→Pill 总计**：区间 `Fn to Pill`，从手势或快捷键触发语音输入，到 Pill 切到「正在听」。按住 Fn 时要先等 150 ms 才算按住，这 150 ms 不在区间内。

### 如何测

1. 按上文「如何跑」第 1 步构建并启动开发包（subsystem 是 `com.saykuku.dev`），并在「设置 › Qwen 连接」填好业务空间 ID。测蓝牙那几行前，先在「系统设置 › 声音 › 输入」里切到蓝牙耳机。
2. 打开 Instruments，选 **Blank** 模板，点右上角 **+** 加入 **os_signpost** 工具，目标选正在运行的 SayKuku，开始录制。
3. 在目标应用的输入框里按住 Fn，说一句话再松开，重复十次；每次等 Pill 消失再按下一次。
4. 停止录制。选中 os_signpost 轨道，在下方详情里切到 **Summary: Intervals**，找到 subsystem `com.saykuku.dev`、category `Performance` 下的 `captureTarget`、`audio start`、`realtime connect` 和 `Fn to Pill`，确认每个的 Count 是 10。
5. 十个样本按最近秩法取 P95 就是最大值，所以每格填 **Max Duration**。连同测试日期、macOS 版本和提交哈希一起填表并提交。
