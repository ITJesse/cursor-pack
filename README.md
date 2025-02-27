# Cursor 安装脚

这个仓库包含了用于安装和构建 Cursor 编辑器的脚本工具。

## 功能

- 自动下载并安装最新版本的 Cursor 编辑器
- 支持 Debian/Ubuntu 系统的 DEB 包构建
- 简单易用的命令行界面

## 使用方法

### 一键安装

使用以下命令可以直接从网络下载并执行安装脚本：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ITJesse/cursor-pack/main/install_cursor.sh)"
```

### 安装 Cursor

运行以下命令来下载并安装最新版本的 Cursor：

```bash
bash install_cursor.sh
```

### 构建 DEB 包
如果你想为 Debian/Ubuntu 系统构建 DEB 包，可以使用：

```bash
bash build_deb.sh
```

## 系统要求

- Linux 操作系统 (Debian/Ubuntu 系列优先支持)
- bash 环境
- curl 或 wget (用于下载)

## 贡献

欢迎提交问题报告和改进建议！请通过 GitHub Issues 或 Pull Requests 参与项目。

## 许可证

MIT