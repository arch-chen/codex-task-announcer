# Codex Task Announcer 便携部署包

## 包含内容

- `plugin`：完整插件本体及固定版本依赖
- `previews`：六种音色的离线试听 MP3
- `install.ps1`：带备份、路径发现、个人市场注册和 Codex 配置接入的安装器
- `restore.ps1`：使用安装器生成的备份回滚
- `VERIFY_PACKAGE.ps1`：校验所有文件 SHA256
- `SHA256SUMS.txt`：逐文件校验值

双击 `双击试听全部语音.cmd` 可依次试听六种音色，详细对应关系见 `语音试听与选择.md`。

## 目标设备要求

- Windows 10/11
- Windows PowerShell 5.1
- 已安装支持 `codex plugin` 命令的 Codex
- Codex 自带 Node.js，或系统中有可用的 `node.exe`
- 使用自然神经语音时可访问 Microsoft Edge 在线语音服务

部署包不包含账号、API 密钥或本机路径。安装器会读取目标设备自己的路径并生成目标设备配置。

## 常用安装命令

只校验：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ValidateOnly
```

按默认“晓晓”音色安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装并登记项目：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ProjectPath "D:\Projects\Example" -ProjectName "示例项目" -Voice xiaoxiao
```

## 安装行为

安装器会：

1. 校验部署包完整性。
2. 定位目标设备的 Codex、Node.js 和用户目录。
3. 备份现有 `config.toml`、个人市场文件及旧版插件。
4. 保留目标设备原有 `notify` 命令，并由新插件继续转发。
5. 默认开启自动化任务静音，并在升级时保留用户已有的开关选择。
6. 安装插件到 `%USERPROFILE%\plugins\codex-task-announcer`。
7. 更新默认个人市场并运行 `codex plugin add`。
8. 写出安装结果 JSON 和备份位置。

安装后应完全退出并重新打开 Codex。在线语音只发送“项目名称 + 已完成”这一句，不发送任务内容或代码；生成的音频会缓存在 `%LOCALAPPDATA%\CodexTaskAnnouncer\audio-cache`。自动化识别依赖事件元数据和 `%CODEX_HOME%\automations` 中的目标线程配置；未明确识别的普通任务会继续播报。
