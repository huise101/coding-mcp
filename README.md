# Coding MCP Portable Kit

这是一个 Windows 上给 ChatGPT / Codex 使用的 Coding MCP 便携包。目标是：换电脑后 clone 公开仓库，再导入私密 runtime，就能继续使用稳定 MCP URL、本地文件夹模式、远程 SSH 文件夹模式和 Cloudflare Named Tunnel。

## 目录说明

```text
coding-tools-mcp/                 MCP 服务端源码
skills/coding-tools-mcp-remote/   启动、保活、Cloudflare/DevTunnel 配置脚本
skills/windows-remote-server/     SSH profile、远程命令、上传下载脚本
launchers/                        双击启动/停止/配置的 Windows GUI
Start-CodingMCP.vbs               启动 GUI
Stop-CodingMCP.vbs                停止 GUI
Setup-CloudflareNamedTunnel.vbs   配置固定域名 tunnel
Add-RemoteServerProfile.vbs       添加 SSH 远程服务器 profile
Import-PrivateRuntime.ps1         导入私密 runtime 迁移包
```

## 不能上传 GitHub 的内容

这些文件只允许私密迁移，不要提交到 GitHub：

```text
coding-tools-mcp/.runtime/
.codex-remote/
private-runtime-packages/
*.credential.xml
*.pem
*.key
id_rsa*
*.log
*.pid
```

它们可能包含 Cloudflare tunnel 凭据、OAuth password、OAuth token secret、SSH 密码、私钥、本机路径或运行日志。

## 新电脑快速使用

在新电脑上先 clone：

```powershell
git clone https://github.com/huise101/coding-mcp.git F:\codingmcp
cd F:\codingmcp
```

如果你有私密 runtime zip，比如：

```text
mcp-pc2-private-runtime.zip
```

导入它：

```powershell
powershell -ExecutionPolicy Bypass -File .\Import-PrivateRuntime.ps1 -ZipPath "D:\path\to\mcp-pc2-private-runtime.zip"
```

然后双击：

```text
Start-CodingMCP.vbs
```

启动窗口里选择本地文件夹或远程 SSH 文件夹，点 `Start / Restart`。窗口会显示：

```text
MCP URL
Password
```

把这两个填到 ChatGPT 的 MCP 连接器里。

## 当前推荐的两台电脑 URL 方案

当前电脑示例：

```text
https://mcp-main.<your-domain>/mcp
```

另一台电脑示例：

```text
https://mcp-pc2.<your-domain>/mcp
```

两台电脑不要同时共用同一个 MCP URL。一个电脑一个子域名，一个电脑一个 Cloudflare tunnel。

## 如果没有私密 runtime

双击：

```text
Setup-CloudflareNamedTunnel.vbs
```

填写这台电脑自己的 hostname，例如：

```text
mcp-laptop.<your-domain>
```

Tunnel name 用窗口自动生成的，或者自己填：

```text
coding-tools-mcp-laptop
```

完成 Cloudflare 登录和 DNS 创建后，再双击 `Start-CodingMCP.vbs`。

## SSH 远程服务器模式

双击：

```text
Add-RemoteServerProfile.vbs
```

创建本机 SSH profile。密码会保存到本机 Windows DPAPI 加密文件，不会进入 GitHub。

启动 `Start-CodingMCP.vbs` 后，可以切换：

```text
Use Local Folder
Use Remote Folder
```

远程模式下需要填写：

```text
SSH connection: ssh -p 端口 user@host
Remote folder: /path/to/project
```

`Remote folder` 是工作区边界。不要填 `/`，也不要填空。你约定哪个目录，MCP 就把哪个目录当工作区。

## 私密 runtime 包

私密包只负责身份，不是公开代码。示例结构：

```text
mcp-pc2-private-runtime.zip
  coding-tools-mcp/
    .runtime/
      chatgpt-mcp-config.json
      cloudflared/
        config.yml
        <tunnel-id>.json
```

导入后，启动脚本会自动修复 `.runtime/cloudflared/config.yml` 里的本机绝对路径，所以新电脑路径不同也可以用。

## 常用操作

启动：

```text
Start-CodingMCP.vbs
```

停止：

```text
Stop-CodingMCP.vbs
```

配置固定域名：

```text
Setup-CloudflareNamedTunnel.vbs
```

添加远程服务器 profile：

```text
Add-RemoteServerProfile.vbs
```

## 故障排查

如果 ChatGPT 连接失败：

1. 打开 `Start-CodingMCP.vbs`，确认状态是 `running`。
2. 确认 ChatGPT 里填的是窗口显示的完整 MCP URL。
3. 确认 password 用的是窗口显示的 password。
4. 如果用了私密 runtime，确认 `.runtime` 已经放在 `coding-tools-mcp/.runtime/`。
5. 如果用了远程 SSH，先点 `Test Remote`，确认能连接并能访问你填的远程目录。

如果换电脑后 Cloudflare tunnel 不工作，重新双击 `Start-CodingMCP.vbs`。启动脚本会自动修复 tunnel config 里的本机路径。
