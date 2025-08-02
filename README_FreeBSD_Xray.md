# FreeBSD Xray 安装脚本

这是一个专为 FreeBSD 14.1 amd64 架构设计的 Xray 安装脚本，无需 root 权限即可运行。该脚本基于 v2ray-agent-master 项目进行了重新设计，以适应 FreeBSD 环境的特殊需求。

## 特性

- **无需 root 权限**：在普通用户权限下即可安装和运行
- **适用于 FreeBSD 14.1 amd64**：针对 FreeBSD 系统优化
- **自动配置**：自动生成 UUID、端口、Reality 密钥等
- **VLESS + Reality + TLS**：使用高性能、高安全性的协议组合
- **完整的管理菜单**：提供图形化管理界面
- **支持卸载**：完整的卸载功能

## 安装方法

1. 下载安装脚本：

```sh
curl -O https://raw.githubusercontent.com/yourusername/freebsd-xray/main/freebsd_xray_installer.sh
```

或者直接使用已下载的脚本。

2. 赋予执行权限：

```sh
chmod +x freebsd_xray_installer.sh
```

3. 运行安装脚本：

```sh
./freebsd_xray_installer.sh
```

## 使用方法

安装完成后，可以使用管理脚本进行操作：

```sh
sh ~/xray-freebsd/menu.sh
```

管理菜单提供以下功能：

1. 启动 Xray
2. 停止 Xray
3. 重启 Xray
4. 查看 Xray 状态
5. 查看客户端连接信息
6. 查看日志
7. 卸载 Xray

## 客户端配置

安装完成后，脚本会生成一个客户端连接链接，格式如下：

```
vless://UUID@SERVER_IP:PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#FreeBSD-VLESS-Reality
```

您可以使用以下客户端连接：

- **Windows**: v2rayN
- **macOS**: V2RayXS
- **Android**: v2rayNG
- **iOS**: Shadowrocket

## 文件结构

- `~/xray-freebsd/` - 主工作目录
  - `bin/` - 二进制文件目录
  - `config/` - 配置文件目录
  - `logs/` - 日志文件目录
  - `run/` - 运行时文件目录
  - `menu.sh` - 管理脚本

## 注意事项

1. 此脚本在用户目录下安装 Xray，不会影响系统文件
2. 默认使用 Reality 协议，提供更好的抗干扰能力
3. 脚本会自动检测并安装必要的依赖
4. 如果无法获取服务器 IP，请在客户端连接信息中手动替换 SERVER_IP

## 故障排除

如果遇到问题，请检查以下日志文件：

- `~/xray-freebsd/logs/error.log` - Xray 错误日志
- `~/xray-freebsd/logs/access.log` - Xray 访问日志
- `~/xray-freebsd/logs/stdout.log` - Xray 标准输出日志

## 卸载

使用管理菜单中的卸载选项，或直接删除工作目录：

```sh
rm -rf ~/xray-freebsd
```

## 免责声明

本脚本仅供学习和研究网络技术使用，请遵守当地法律法规。作者不对使用此脚本导致的任何问题负责。
