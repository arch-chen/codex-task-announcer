# Codex Task Announcer

Windows 上的 Codex 任务完成语音播报插件。每当手动 Codex 任务结束一个代理回合，它会先播放提示音，再用可切换的中文神经语音播报当前项目名称，例如“本地设备项目已完成”。自动化任务默认静音。

## 功能

- 支持 6 种中文神经语音：晓晓、晓伊、云希、云扬、云健、云夏
- 支持全局默认音色和按项目覆盖音色
- 自动识别 Codex 自动化及心跳任务并跳过响铃和语音
- 未配置项目时自动使用工作目录名称
- 在线语音失败时自动回退到 Windows 本地语音
- 相同文本和音色生成的 MP3 会缓存在本机，避免重复请求
- 保留并转发安装前已有的 Codex `notify` 通知命令
- 安装前自动备份 Codex 配置、个人插件市场和旧版插件
- 提供完整性校验与一键回滚脚本

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1
- 已安装支持 `codex plugin` 命令的 Codex
- Codex 自带 Node.js，或系统中存在可用的 `node.exe`
- 使用自然神经语音时可以访问 Microsoft Edge 在线语音服务

## 安装

下载或克隆本仓库后，在仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ValidateOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装器默认使用“晓晓”音色。要同时登记当前项目：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 `
  -Voice xiaoxiao `
  -ProjectPath "D:\Projects\Example" `
  -ProjectName "示例项目"
```

安装完成后，需要完全退出并重新打开 Codex，再从一个新任务验证播报。

## 切换音色

查看所有音色：

```powershell
powershell.exe -NoProfile -File "$HOME\plugins\codex-task-announcer\scripts\set-voice.ps1" -List
```

切换全局默认音色：

```powershell
powershell.exe -NoProfile -File "$HOME\plugins\codex-task-announcer\scripts\set-voice.ps1" -Voice xiaoyi
```

| 别名 | 音色 | 类型 |
| --- | --- | --- |
| `xiaoxiao` | 晓晓 | 自然女声，默认 |
| `xiaoyi` | 晓伊 | 清亮女声 |
| `yunxi` | 云希 | 青年男声 |
| `yunyang` | 云扬 | 专业男声 |
| `yunjian` | 云健 | 沉稳男声 |
| `yunxia` | 云夏 | 少年男声 |

可以双击 `双击试听全部语音.cmd` 依次试听仓库中附带的示例音频。

## 回滚

安装输出会显示备份目录。使用该目录恢复安装前状态：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restore.ps1 `
  -BackupPath "$HOME\.codex\backups\codex-task-announcer\YYYYMMDD-HHMMSS"
```

恢复完成后同样需要完全重启 Codex。

## 隐私与边界

自然语音通过 Microsoft Edge 在线语音服务生成，不需要 API 密钥。插件只发送“项目名称 + 已完成”这一句播报文本，不发送任务内容或代码。生成的音频和运行日志保存在 `%LOCALAPPDATA%\CodexTaskAnnouncer`。

自动化过滤默认由 `project-names.json` 中的 `suppressAutomationAnnouncements: true` 开启。插件优先识别事件的自动化元数据，并使用 `%CODEX_HOME%\automations\*\automation.toml` 中的 `target_thread_id` 作为回退。只有明确命中自动化任务时才静音；原有通知转发不受影响。将该设置改为 `false` 可恢复自动化任务播报。

Codex 当前提供的是 `agent-turn-complete` 通知，而不是业务结果的“成功”事件。因此，普通任务的最终回复、澄清问题和阻塞报告都可能触发播报。

## 仓库结构

- `plugin/`：插件本体与固定版本运行依赖
- `previews/`：6 种音色的示例 MP3
- `install.ps1`：校验、备份、安装和 Codex 配置接入
- `restore.ps1`：恢复安装前状态
- `VERIFY_PACKAGE.ps1`：按 `SHA256SUMS.txt` 校验发布文件
- `tests/announce-routing.tests.ps1`：自动化与普通任务路由回归测试
- `DEPLOYMENT_GUIDE.md`：完整部署说明

本项目与 Microsoft、OpenAI 无隶属或背书关系。

## License

[MIT](LICENSE)
