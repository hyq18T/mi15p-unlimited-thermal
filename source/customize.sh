#!/system/bin/sh

MODPATH=${MODPATH:-${0%/*}}
THERMAL_DIR=/data/vendor/thermal
CONFIG="$THERMAL_DIR/config"
FACTORY_DIR=/data/adb/unlimited_thermal_factory

DEVICE=$(getprop ro.product.device)
MODEL=$(getprop ro.product.model)

if [ "$DEVICE" != "haotian" ]; then
    ui_print "!! 机型不匹配：本模块仅适配小米 15 Pro (haotian / 2410DPN6CC)"
    ui_print "!! 当前 device=$DEVICE model=$MODEL"
    abort "安装中止：机型不匹配，避免刷入后出现温控异常。"
fi

LEFTOVER=0
if pgrep -f "ultra_performance" >/dev/null 2>&1; then
    pkill -f "ultra_performance" 2>/dev/null
    LEFTOVER=1
fi
for MP in \
    /vendor/etc/perf/perfboostsconfig.xml \
    /vendor/etc/perf/perfboostselection.xml \
    /vendor/etc/perf/perfconfigstore.xml \
    /vendor/etc/perf/thermalbreakboostconfig.xml \
    /vendor/etc/thermal-engine.conf; do
    if grep -q " $MP " /proc/mounts 2>/dev/null; then
        umount "$MP" 2>/dev/null
        umount -l "$MP" 2>/dev/null
        LEFTOVER=1
    fi
done
if [ "$LEFTOVER" -eq 1 ]; then
    ui_print "[清理] 已清理旧版 ultra_performance 残留进程/挂载"
fi

ui_print "[备份] 备份当前温控配置到 /data/adb/unlimited_thermal_factory"
if [ ! -d "$FACTORY_DIR/config" ]; then
    mkdir -p "$FACTORY_DIR/config"
    chattr -i "$CONFIG" "$CONFIG"/* 2>/dev/null
    if [ -d "$CONFIG" ]; then
        cp -f "$CONFIG"/files.ini "$FACTORY_DIR/files.ini" 2>/dev/null
        cp -f "$CONFIG"/*.conf "$FACTORY_DIR/config/" 2>/dev/null
    fi
    if [ ! -s "$FACTORY_DIR/files.ini" ]; then
        echo "normal" > "$FACTORY_DIR/files.ini"
    fi
    chmod -R 0771 "$FACTORY_DIR"
fi

TMP_ZIP_FOUND=0
for ZIP in /data/local/tmp/mi15p_unlimited_thermal_*.zip \
    /data/local/tmp/combined-thermal-unlimit*.zip; do
    [ -e "$ZIP" ] || continue
    [ -n "$ZIPFILE" ] && [ "$ZIP" = "$ZIPFILE" ] && continue
    rm -f "$ZIP" 2>/dev/null
    TMP_ZIP_FOUND=1
done
if [ "$TMP_ZIP_FOUND" -eq 1 ]; then
    ui_print "[清理] 删除本机临时目录中的旧版安装包"
fi

ui_print "安装完成，请重启一次让模块生效。"
