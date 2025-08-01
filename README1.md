# FreeBSD Xray 安装项目

这是一个为 FreeBSD 14.1 amd64 架构设计的 Xray 安装项目，特别适合无 root 权限的环境。本项目基于 v2ray-agent-master 项目重构，提供了简化的安装流程和完整的管理功能。

## 项目文件

- `remote_install.sh` - 远程安装脚本，用于通过SSH从Windows连接到FreeBSD系统并安装Xray
- `SSH连接指南.md` - 详细的SSH连接和安装指南
- `freebsd_xray_installer.sh` - 完整的FreeBSD Xray安装脚本（由远程安装脚本自动下载）

## 特性

- 支持 FreeBSD 14.1 amd64 架构
- 无需 root 权限运行
- 支持 VLESS + Reality + TLS 协议组合
- 自动生成 UUID 和 Reality 密钥对
- 自动检测可用端口
- 完整的管理菜单（启动/停止/重启、状态查看、日志查看、卸载等）
- 在用户目录下安装，不影响系统文件

## 快速开始

1. 将 `remote_install.sh` 脚本上传到 FreeBSD 服务器
2. 赋予脚本执行权限：`chmod +x remote_install.sh`
3. 运行脚本：`sh remote_install.sh`
4. 按照提示完成安装

详细的安装和使用说明请参考 `SSH连接指南.md`。

## 管理 Xray

安装完成后，可以使用管理菜单来控制 Xray：

```bash
sh ~/xray-freebsd/menu.sh
```

管理菜单提供以下功能：
- 启动/停止/重启 Xray
- 查看 Xray 状态
- 查看客户端连接信息
- 查看日志
- 卸载 Xray

## 客户端配置

安装完成后，客户端连接信息会显示在终端上，您也可以随时通过以下命令查看：

```bash
cat ~/xray-freebsd/config/client_link.txt
```

这个链接可以直接在支持 VLESS+Reality 的客户端中使用，如 v2rayN、v2rayNG、Shadowrocket 等。

## 注意事项

- 此安装方法在用户目录下安装 Xray，不会影响系统文件
- 安装过程中生成的所有文件都位于 `~/xray-freebsd` 目录下
- 如需卸载，可以使用管理菜单中的卸载选项，或直接删除整个 `~/xray-freebsd` 目录

## 免责声明

本项目仅供学习和研究使用，请遵守当地法律法规。作者不对使用本项目产生的任何后果负责。
