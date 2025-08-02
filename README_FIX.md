# Xray FreeBSD 安装脚本修复说明

## 问题描述

在原始的 Xray FreeBSD 安装脚本中，配置文件验证使用了 `xray test` 命令，但新版本的 Xray 不支持此命令，导致配置验证失败。错误信息如下：

```
验证配置文件...
配置文件验证失败，请检查: /home/dayao123/xray-freebsd/logs/config_test.log

xray test: unknown command
Run 'xray help' for usage.
```

## 修复方案

1. 修改了配置验证方法，使用 JSON 格式检查工具（如 `python3 -m json.tool` 或 `jq`）来验证配置文件，而不是依赖 Xray 的 `--test` 参数。
2. 创建了新的管理脚本 `fixed_menu.sh`，替换原有的 `menu.sh`。
3. 修改了 `remote_install.sh` 和 `freebsd_xray_installer.sh` 中的 `create_management_script` 函数，使其使用新的管理脚本。

## 使用方法

### 方法一：使用修复后的安装脚本

1. 下载修复后的安装脚本：
   ```sh
   fetch -o remote_install.sh https://your-server/path/to/remote_install.sh
   ```

2. 运行安装脚本：
   ```sh
   sh remote_install.sh
   ```

### 方法二：手动修复现有安装

如果您已经安装了 Xray，可以按照以下步骤手动修复：

1. 下载修复后的管理脚本：
   ```sh
   fetch -o ~/xray-freebsd/menu.sh https://your-server/path/to/fixed_menu.sh
   ```

2. 赋予执行权限：
   ```sh
   chmod +x ~/xray-freebsd/menu.sh
   ```

3. 运行管理脚本：
   ```sh
   sh ~/xray-freebsd/menu.sh
   ```

## 验证修复

修复后，重启 Xray 时不会再出现配置验证失败的错误。您可以通过以下命令验证修复是否成功：

```sh
sh ~/xray-freebsd/menu.sh
```

选择 "3. 重启 Xray" 选项，如果能够正常重启，则表示修复成功。

## 注意事项

1. 确保系统已安装 `python3` 或 `jq` 用于 JSON 格式验证。
2. 如果您使用的是自定义配置文件，请确保其符合 JSON 格式规范。
3. 如果您遇到其他问题，请查看日志文件：`~/xray-freebsd/logs/stdout.log` 和 `~/xray-freebsd/logs/error.log`。
