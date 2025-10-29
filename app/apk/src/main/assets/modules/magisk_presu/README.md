# Magisk Pre-SU Authorization Module

## 功能说明

这个 Magisk 模块可以自动为指定的应用包和 adb shell 预授权 root 权限，无需手动操作。

## 特性

- ✅ **自动授权 adb shell su**（UID 2000，立即生效）
- ✅ 为 `com.test.test` 包预授权 su 权限
- ✅ 自动监控应用安装状态
- ✅ 应用安装后自动授权（无需手动操作）
- ✅ 持久化授权（永久有效）
- ✅ 完整的日志记录

## 工作原理

1. 模块在系统启动后运行 `service.sh` 脚本
2. **立即授权 shell 用户（UID 2000），使 `adb shell su` 无需手动确认**
3. 检查目标应用 `com.test.test` 是否已安装
4. 如果已安装，立即写入 Magisk 数据库授权
5. 如果未安装，脚本会持续监控（24小时），一旦检测到安装即自动授权
6. 授权信息写入 `/data/adb/magisk.db` 数据库

## 安装方法

1. 将模块打包成 zip 文件：
   ```bash
   zip -r magisk-presu.zip . -x "*.git*" "*.DS_Store" "README.md"
   ```

2. 在 Magisk Manager 中安装模块：
   - 打开 Magisk Manager
   - 点击"模块"
   - 点击"从本地安装"
   - 选择 `magisk-presu.zip`
   - 重启设备

3. 安装完成后，模块会自动开始工作

## 自定义配置

如果你想为其他应用预授权，可以修改 `service.sh` 中的 `PACKAGE_NAME` 变量：

```bash
PACKAGE_NAME="com.your.package"
```

然后重新打包安装即可。

### 关于 adb shell su 自动授权

模块会在启动时**自动授权 shell 用户（UID 2000）**，这意味着：

- ✅ 执行 `adb shell su` 无需手动确认
- ✅ 授权立即生效，无需等待
- ✅ 永久授权，重启后依然有效
- ✅ 适合调试和自动化脚本使用

**测试方法**：

```bash
# 重启设备后，直接执行
adb shell su -c "id"
# 应该立即显示 uid=0(root) gid=0(root)，无需手动确认
```

如果不需要 adb shell 自动授权，可以在 `service.sh` 中注释掉以下行：

```bash
# grant_shell_su  # 注释此行以禁用 adb shell su 自动授权
```

## 日志查看

模块运行日志保存在：`/data/local/tmp/magisk_presu.log`

通过 adb 查看日志：
```bash
adb shell cat /data/local/tmp/magisk_presu.log
```

或在设备上通过终端查看：
```bash
su
cat /data/local/tmp/magisk_presu.log
```

## 日志示例

```
[2025-10-29 10:30:00] === Magisk Pre-SU Service Started ===
[2025-10-29 10:30:30] Magisk database found
[2025-10-29 10:30:30] Granting su permission to shell user (UID: 2000) for adb shell su
[2025-10-29 10:30:30] Successfully granted su permission to shell user (UID: 2000)
[2025-10-29 10:30:30] Verification: 2000|2
[2025-10-29 10:30:30] Package not installed yet, starting monitoring...
[2025-10-29 11:15:45] Package com.test.test found with UID: 10234
[2025-10-29 11:15:45] Granting su permission to UID: 10234 (com.test.test)
[2025-10-29 11:15:45] Successfully granted su permission to UID: 10234 (com.test.test)
[2025-10-29 11:15:45] Verification: 10234|2
[2025-10-29 11:15:45] Package installed and authorized, stopping monitor
[2025-10-29 11:15:45] === Magisk Pre-SU Service Finished ===
```

## 注意事项

1. **需要 Magisk v29.0 或更高版本**（专门适配 v29.0 的 policies 表结构）
2. 模块会在后台监控 24 小时，超时后自动停止
3. 如果需要重新监控，可以重启设备
4. 授权为永久性，卸载应用后需要手动清理数据库记录
5. 建议仅用于可信任的应用
6. Magisk v29.0 的 policies 表只使用 `uid` 作为主键，不再使用 `package_name`

## 手动清理授权

如果需要手动撤销授权，首先获取应用的 UID：

```bash
su
# 获取应用的 UID
grep "^com.test.test " /data/system/packages.list | awk '{print $2}'
```

然后使用 UID 删除授权记录：

```bash
su
# 假设 UID 是 10234
sqlite3 /data/adb/magisk.db "DELETE FROM policies WHERE uid=10234;"
```

或者查看所有授权记录：

```bash
su
sqlite3 /data/adb/magisk.db "SELECT * FROM policies;"
```

## 故障排除

### 问题：adb shell su 仍然需要手动确认

**检查步骤**：
1. 确认模块已正确安装：`ls -la /data/adb/modules/magisk_presu/`
2. 检查日志确认 shell 用户已授权：
   ```bash
   adb shell cat /data/local/tmp/magisk_presu.log | grep "shell user"
   ```
3. 验证数据库中是否有 UID 2000 的记录：
   ```bash
   adb shell su -c "sqlite3 /data/adb/magisk.db 'SELECT * FROM policies WHERE uid=2000;'"
   ```
4. 如果没有记录，手动执行模块脚本：
   ```bash
   adb shell su -c "sh /data/adb/modules/magisk_presu/service.sh"
   ```

### 问题：应用安装后没有自动授权

1. 检查日志文件确认模块是否正常运行
2. 确认 Magisk 版本是否支持
3. 尝试手动运行脚本测试：
   ```bash
   su
   sh /data/adb/modules/magisk_presu/service.sh
   ```

### 问题：授权后应用仍然提示没有权限

1. 确认应用请求的是 root 权限
2. 检查 Magisk Manager 中的授权列表
3. 尝试清除应用数据后重新打开

## 许可证

MIT License

## 作者

cloverstd

## 版本历史

- v1.2 (2025-10-29)
  - **新增 adb shell su 自动授权功能**
  - 自动授权 shell 用户（UID 2000），使 `adb shell su` 无需手动确认
  - 授权立即生效，永久有效
  - 更新安装脚本提示信息
  - 优化日志输出

- v1.1 (2025-10-29)
  - **适配 Magisk v29.0 数据库结构**
  - 修改 policies 表操作，仅使用 `uid` 字段
  - 移除对不存在的 `package_name` 字段的引用
  - 优化 UID 获取方式（优先使用 packages.list）
  - 添加授权验证日志

- v1.0 (2025-10-29)
  - 初始版本
  - 支持预授权功能
  - 支持自动监控安装
