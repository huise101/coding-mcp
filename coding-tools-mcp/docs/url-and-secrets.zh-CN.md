# Coding MCP 网址和密钥规则

这个仓库可以上传代码、脚本和说明，但不能上传本机运行时身份。

## 一台电脑一个网址

不要让两台正在运行的电脑共用同一个 MCP URL。正确做法是给每台电脑一个独立子域名：

```text
https://mcp-main.example.com/mcp
https://mcp-laptop.example.com/mcp
https://mcp-lab.example.com/mcp
```

每台电脑也应该使用自己的 Cloudflare Tunnel name，例如：

```text
coding-tools-mcp-main
coding-tools-mcp-laptop
coding-tools-mcp-lab
```

旧电脑关掉、新电脑接管时，才可以临时复用同一个 hostname。两台同时开着时不要复用。

## 不上传的文件

这些文件已经通过 `.gitignore` 屏蔽：

```text
.runtime/
tools/
.codex-remote/
*.credential.xml
*.pem
*.key
id_rsa*
*.log
*.pid
```

它们可能包含 MCP URL、OAuth password、OAuth token secret、Cloudflare tunnel credentials、SSH 凭据或本机路径。

## 新电脑配置

1. clone 仓库。
2. 打开 Cloudflare Named Tunnel 设置入口。
3. Hostname 填这台电脑自己的子域名，例如 `mcp-laptop.example.com`。
4. Tunnel name 使用窗口自动生成的值，或者自己填一个只属于这台电脑的名字。
5. 配好后启动 Coding MCP，把窗口显示的 MCP URL 和密码填到 ChatGPT。

不要把真实 MCP URL、密码、token 或 Cloudflare 凭据写进 GitHub。
