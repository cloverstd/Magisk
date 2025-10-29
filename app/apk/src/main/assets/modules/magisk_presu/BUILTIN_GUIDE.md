# 将模块内置到 Magisk 安装指南

本文档说明如何将 `magisk-presu` 模块内置到 Magisk 中，使得在安装 Magisk 时自动安装该模块。

## 目录

- [方法一：修改 Magisk APK（推荐）](#方法一修改-magisk-apk推荐)
- [方法二：通过 Boot 脚本自动安装](#方法二通过-boot-脚本自动安装)
- [方法三：集成到自定义 ROM](#方法三集成到自定义-rom)

---

## 方法一：修改 Magisk APK（推荐）

这种方法适合给其他用户分发已经预装模块的 Magisk 安装包。

### 前置要求

- Linux/macOS 环境（或 WSL）
- 安装必要工具：
  ```bash
  # Ubuntu/Debian
  sudo apt install -y android-sdk apktool zipalign openjdk-11-jdk

  # macOS
  brew install apktool android-platform-tools openjdk@11
  ```

### 步骤 1: 准备模块文件

首先打包你的模块：

```bash
cd /path/to/magisk-presu
zip -r magisk-presu.zip module.prop service.sh customize.sh -x "*.git*" "*.DS_Store" "*.md"
```

### 步骤 2: 下载并解包 Magisk APK

```bash
# 创建工作目录
mkdir -p ~/magisk-build && cd ~/magisk-build

# 下载 Magisk APK（以 v29.0 为例）
wget https://github.com/topjohnwu/Magisk/releases/download/v29.0/Magisk-v29.0.apk

# 解包 APK
apktool d Magisk-v29.0.apk -o magisk-unpacked
```

### 步骤 3: 添加预装模块

将模块添加到 APK 的 assets 目录：

```bash
cd magisk-unpacked

# 创建预装模块目录
mkdir -p assets/modules

# 复制模块 zip 到 assets
cp /path/to/magisk-presu.zip assets/modules/

# 或者直接创建模块文件夹（推荐）
mkdir -p assets/modules/magisk_presu
cp /path/to/magisk-presu/module.prop assets/modules/magisk_presu/
cp /path/to/magisk-presu/service.sh assets/modules/magisk_presu/
cp /path/to/magisk-presu/customize.sh assets/modules/magisk_presu/
chmod 644 assets/modules/magisk_presu/*
```

### 步骤 4: 修改安装脚本

编辑 `assets/util_functions.sh`，在安装过程中自动安装预置模块：

```bash
# 找到 install_module 函数或者 recovery_actions 函数
# 添加以下代码（在文件末尾或合适位置）
```

在 `assets/util_functions.sh` 中添加：

```bash
# 在文件末尾添加
install_prebuilt_modules() {
  ui_print "- Installing prebuilt modules..."

  if [ -d "$MAGISKBIN/../modules" ]; then
    for module in "$MAGISKBIN/../modules/"*; do
      if [ -f "$module/module.prop" ]; then
        module_id=$(grep "^id=" "$module/module.prop" | cut -d= -f2)
        ui_print "  • Installing: $module_id"

        # 复制到 Magisk 模块目录
        cp -rf "$module" /data/adb/modules/

        # 设置权限
        chmod -R 755 /data/adb/modules/"$module_id"
        chmod 644 /data/adb/modules/"$module_id"/module.prop

        # 如果有 customize.sh，执行它
        if [ -f /data/adb/modules/"$module_id"/customize.sh ]; then
          chmod 755 /data/adb/modules/"$module_id"/customize.sh
          sh /data/adb/modules/"$module_id"/customize.sh
        fi
      fi
    done
  fi
}
```

然后在安装主流程中调用（找到 `install_magisk` 函数，在末尾添加）：

```bash
install_magisk() {
  # ... 原有代码 ...

  # 在函数末尾添加
  install_prebuilt_modules
}
```

### 步骤 5: 重新打包 APK

```bash
cd ~/magisk-build

# 重新打包
apktool b magisk-unpacked -o Magisk-v29.0-modded.apk
```

### 步骤 6: 签名 APK

使用 APK 签名工具签名（必须步骤）：

```bash
# 方法 1: 使用 apksigner（推荐）
# 生成密钥（首次）
keytool -genkey -v -keystore my-release-key.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias my-key-alias

# 签名 APK
apksigner sign --ks my-release-key.jks \
  --out Magisk-v29.0-modded-signed.apk \
  Magisk-v29.0-modded.apk

# 方法 2: 使用 jarsigner（备用）
jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 \
  -keystore my-release-key.jks \
  Magisk-v29.0-modded.apk my-key-alias

# Zipalign 优化
zipalign -v 4 Magisk-v29.0-modded.apk Magisk-v29.0-modded-signed.apk
```

### 步骤 7: 验证和分发

```bash
# 验证签名
apksigner verify Magisk-v29.0-modded-signed.apk

# 重命名
mv Magisk-v29.0-modded-signed.apk Magisk-v29.0-with-presu.apk
```

现在可以将 `Magisk-v29.0-with-presu.apk` 分发给用户了！

---

## 方法二：通过 Boot 脚本自动安装

这种方法更简单，但需要在首次安装 Magisk 后手动执行一次。

### 步骤 1: 创建自动安装脚本

```bash
# 创建脚本目录
mkdir -p ~/magisk-auto-install
cd ~/magisk-auto-install
```

创建 `install-presu.sh`：

```bash
#!/system/bin/sh

MODPATH="/data/adb/modules/magisk_presu"
ZIPFILE="/sdcard/magisk-presu.zip"

# 等待 Magisk 完全启动
while [ ! -d "/data/adb/modules" ]; do
  sleep 2
done

# 检查模块是否已安装
if [ -d "$MODPATH" ]; then
  echo "Module already installed"
  exit 0
fi

# 如果 zip 文件存在，安装它
if [ -f "$ZIPFILE" ]; then
  echo "Installing module from $ZIPFILE"

  # 解压到临时目录
  TMPDIR="/data/local/tmp/magisk_presu_install"
  mkdir -p "$TMPDIR"
  unzip -o "$ZIPFILE" -d "$TMPDIR"

  # 复制到模块目录
  mkdir -p "$MODPATH"
  cp -rf "$TMPDIR"/* "$MODPATH"/

  # 设置权限
  chmod -R 755 "$MODPATH"
  chmod 644 "$MODPATH"/module.prop
  chmod 755 "$MODPATH"/service.sh

  # 清理
  rm -rf "$TMPDIR"

  echo "Module installed successfully"
  exit 0
fi

echo "Module zip file not found"
exit 1
```

### 步骤 2: 集成到 Magisk 安装流程

将脚本和模块 zip 打包到一起：

```bash
# 创建安装包
mkdir -p package/sdcard
cp magisk-presu.zip package/sdcard/
cp install-presu.sh package/

# 创建 README
cat > package/README.txt << 'EOF'
安装说明：

1. 安装 Magisk v29.0
2. 重启设备
3. 通过 adb 推送文件：
   adb push magisk-presu.zip /sdcard/
   adb push install-presu.sh /data/local/tmp/
   adb shell "su -c 'sh /data/local/tmp/install-presu.sh'"
4. 再次重启设备

模块将自动安装并生效。
EOF

# 打包
zip -r magisk-presu-installer.zip package/
```

---

## 方法三：集成到自定义 ROM

如果你在构建自定义 ROM，可以直接将模块集成到系统中。

### 在 ROM 源码中添加模块

编辑 ROM 构建脚本（通常是 `device.mk` 或 `BoardConfig.mk`）：

```makefile
# device.mk

# Magisk 预装模块
PRODUCT_COPY_FILES += \
    vendor/custom/magisk-modules/magisk_presu/module.prop:system/addon.d/magisk_presu/module.prop \
    vendor/custom/magisk-modules/magisk_presu/service.sh:system/addon.d/magisk_presu/service.sh \
    vendor/custom/magisk-modules/magisk_presu/customize.sh:system/addon.d/magisk_presu/customize.sh
```

### 创建安装后脚本

在 ROM 中创建 `system/addon.d/99-magisk-modules.sh`：

```bash
#!/sbin/sh
#
# ADDOND_VERSION=2
#

. /tmp/backuptool.functions

case "$1" in
  backup)
    # 备份操作（可选）
    ;;
  restore)
    # 恢复操作（可选）
    ;;
  pre-backup)
    # 备份前操作
    ;;
  post-backup)
    # 备份后操作
    ;;
  pre-restore)
    # 恢复前操作
    ;;
  post-restore)
    # 恢复后操作
    # 安装 Magisk 模块
    if [ -d /data/adb/modules ]; then
      cp -rf /system/addon.d/magisk_presu /data/adb/modules/
      chmod -R 755 /data/adb/modules/magisk_presu
      chmod 644 /data/adb/modules/magisk_presu/module.prop
    fi
    ;;
esac
```

---

## 验证安装

安装完成后，通过以下方式验证：

```bash
# 连接设备
adb shell

# 切换到 root
su

# 检查模块是否安装
ls -la /data/adb/modules/magisk_presu/

# 查看模块信息
cat /data/adb/modules/magisk_presu/module.prop

# 检查 Magisk 是否识别模块
magisk --list

# 查看日志
cat /data/local/tmp/magisk_presu.log
```

---

## 注意事项

1. **签名问题**：修改后的 APK 必须重新签名，否则无法安装
2. **兼容性**：确保模块与目标 Magisk 版本兼容
3. **测试**：在分发前务必在测试设备上完整测试
4. **法律合规**：分发修改版 Magisk 需要遵守 GPL-3.0 许可证
5. **更新维护**：Magisk 更新时需要重新打包
6. **用户知情**：告知用户你修改了原版 Magisk

---

## 故障排除

### 问题：APK 安装失败

**解决方案**：
```bash
# 卸载旧版本
adb uninstall com.topjohnwu.magisk

# 重新安装
adb install Magisk-v29.0-with-presu.apk
```

### 问题：模块未自动安装

**检查步骤**：
1. 确认模块文件在 APK 的 `assets/modules/` 目录中
2. 检查 `util_functions.sh` 修改是否正确
3. 查看 Magisk 安装日志：`adb logcat | grep Magisk`

### 问题：权限错误

**解决方案**：
```bash
# 手动修复权限
adb shell su -c "chmod -R 755 /data/adb/modules/magisk_presu"
adb shell su -c "chmod 644 /data/adb/modules/magisk_presu/module.prop"
adb shell su -c "chmod 755 /data/adb/modules/magisk_presu/service.sh"
```

---

## 高级技巧

### 1. 添加多个预装模块

只需在 `assets/modules/` 目录下添加更多模块：

```bash
assets/modules/
├── magisk_presu/
│   ├── module.prop
│   ├── service.sh
│   └── customize.sh
├── another_module/
│   ├── module.prop
│   └── ...
```

### 2. 条件安装

在 `util_functions.sh` 中添加条件判断：

```bash
install_prebuilt_modules() {
  # 检查设备型号
  DEVICE=$(getprop ro.product.device)

  if [ "$DEVICE" = "your_device" ]; then
    # 只在特定设备上安装
    ui_print "- Installing modules for $DEVICE"
    # ... 安装逻辑
  fi
}
```

### 3. 自动更新检查

在 `service.sh` 中添加版本检查：

```bash
# 检查模块版本并自动更新
MODULE_VERSION=$(grep "^version=" /data/adb/modules/magisk_presu/module.prop | cut -d= -f2)
LATEST_VERSION="v1.1"

if [ "$MODULE_VERSION" != "$LATEST_VERSION" ]; then
  # 执行更新逻辑
  echo "Updating module from $MODULE_VERSION to $LATEST_VERSION"
fi
```

---

## 相关资源

- [Magisk 官方文档](https://topjohnwu.github.io/Magisk/)
- [Magisk 模块开发指南](https://topjohnwu.github.io/Magisk/guides.html)
- [APK 签名工具文档](https://developer.android.com/studio/command-line/apksigner)
- [Apktool 使用说明](https://ibotpeaches.github.io/Apktool/)

---

## 许可证

本文档基于 MIT License 发布。修改 Magisk 时请遵守其 GPL-3.0 许可证。

## 作者

cloverstd

---

**完成！** 现在你已经知道如何将模块内置到 Magisk 中了。选择最适合你需求的方法开始吧！
