#!/system/bin/sh
# Magisk Module Installer Script

# 设置权限
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755

ui_print "- Installing Magisk Pre-SU Authorization Module"
ui_print "- Auto-grant su permission for:"
ui_print "  • adb shell (UID 2000)"
ui_print "  • com.test.test package (when installed)"
ui_print "- Module will monitor and auto-grant permissions"
ui_print "- Check logs at: /data/local/tmp/magisk_presu.log"
