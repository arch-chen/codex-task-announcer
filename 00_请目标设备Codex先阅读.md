# 给目标设备 Codex 的部署指令

你正在处理一个可移植的 Codex 任务完成语音播报插件。请不要重新设计，也不要从网络寻找另一套插件；直接按本包执行。

1. 完整阅读本文件和 `DEPLOYMENT_GUIDE.md`。
2. 先运行只读校验：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -ValidateOnly
```

3. 校验通过后安装。用户没有指定音色时使用默认的 `xiaoxiao`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Voice xiaoxiao
```

4. 如果当前任务位于用户希望播报的项目目录，可同时登记项目名称：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Voice xiaoxiao -ProjectPath "项目绝对路径" -ProjectName "播报名称"
```

5. 检查安装输出中的备份目录、插件版本、Node 路径和 Codex 插件状态。不要输出目标设备的密钥或其他无关配置。
6. 安装后让用户完全退出并重新打开 Codex，再从新任务验证播报。

允许的音色别名：`xiaoxiao`、`xiaoyi`、`yunxi`、`yunyang`、`yunjian`、`yunxia`。试听文件位于 `previews`。
