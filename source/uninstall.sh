#!/system/bin/sh

MODDIR=${0%/*}
THERMAL_DIR=/data/vendor/thermal
CONFIG="$THERMAL_DIR/config"
FACTORY_DIR=/data/adb/unlimited_thermal_factory

write_if_exists() {
	[ -w "$1" ] || return 1
	echo "$2" > "$1" 2>/dev/null
}

echo "[卸载] 停止 ultra_performance 残留进程"
pkill -f "ultra_performance" 2>/dev/null
sleep 1

echo "[卸载] 卸载旧版残留的 bind mount"
for MP in \
    /vendor/etc/perf/perfboostsconfig.xml \
    /vendor/etc/perf/perfboostselection.xml \
    /vendor/etc/perf/perfconfigstore.xml \
    /vendor/etc/perf/thermalbreakboostconfig.xml \
    /vendor/etc/thermal-engine.conf; do
    umount "$MP" 2>/dev/null
    umount -l "$MP" 2>/dev/null
done

echo "[卸载] 删除模块写入的系统属性"
PROPS="$(awk '/^(persist\.|suto\.)/ {sub(/=.*/, ""); print}' "$MODDIR/system.prop")"
for prop in $PROPS; do
	case "$prop" in
		persist.*) resetprop -p --delete "$prop" 2>/dev/null ;;
		*) resetprop --delete "$prop" 2>/dev/null ;;
	esac
done

echo "[卸载] 还原模块修改过的系统设置"
restore_settings() {
	[ -f "$MODDIR/settings_backup" ] || return 0
	while IFS=' ' read -r ns keyval; do
		[ -n "$ns" ] && [ -n "$keyval" ] || continue
		key=${keyval%%=*}
		val=${keyval#*=}
		if [ "$val" = "__unset__" ]; then
			settings delete "$ns" "$key" 2>/dev/null
		else
			settings put "$ns" "$key" "$val" 2>/dev/null
		fi
	done < "$MODDIR/settings_backup"
}
restore_settings

echo "[卸载] 还原原厂温控配置"
mkdir -p "$CONFIG"
i=0
while [ "$i" -lt 5 ]; do
	chattr -i "$CONFIG" "$CONFIG"/* 2>/dev/null
	rm -rf "$CONFIG"/* 2>/dev/null
	[ "$(ls "$CONFIG" 2>/dev/null | wc -l)" -eq 0 ] && break
	i=$((i+1))
	sleep 1
done

if ls /odm/etc/thermal-*.conf >/dev/null 2>&1; then
	cp -f /odm/etc/thermal-*.conf "$CONFIG"/
	echo "normal" > "$CONFIG/files.ini"
elif [ -d "$FACTORY_DIR/config" ] && ls "$FACTORY_DIR/config"/*.conf >/dev/null 2>&1; then
	cp -f "$FACTORY_DIR/config"/*.conf "$CONFIG"/
	[ -f "$FACTORY_DIR/files.ini" ] && cp -f "$FACTORY_DIR/files.ini" "$CONFIG/files.ini"
else
	echo "normal" > "$CONFIG/files.ini"
fi
chmod -R 0771 "$THERMAL_DIR"
chown -R root:system "$CONFIG" 2>/dev/null
restorecon -DFR "$THERMAL_DIR" 2>/dev/null
rm -rf "$FACTORY_DIR" 2>/dev/null

echo "[卸载] 还原关键 sysfs 开关"
write_if_exists /sys/devices/platform/soc/soc:mca_business_charger/debug_ctrl "remove_temp_limit 0"
write_if_exists /sys/class/xm_power/charger/charger_thermal/wired_thermal_remove 0
write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_thermal_remove 0
write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_ctrl_limit 1
write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_mag_ctrl_limit 1
write_if_exists /sys/class/xm_power/charger/charger_thermal/wls_quick_chg_control_limit 1
write_if_exists /sys/class/xm_power/charger/charger_common/revchg_bcl 1
for NODE in thermal_max_brightness market_download_limit modem_limit modem_level poor_modem_limit \
	wifi_limit torch_level voice_limit ntn_limit temp_state super_hdr cloud_game dynamic_tj; do
	write_if_exists "/sys/class/thermal/thermal_message/$NODE" 1
done
write_if_exists /sys/class/thermal/power_save/power_level 0

echo "[卸载] 重启 mi_thermald 加载原厂温控配置"
if [ "$(getprop init.svc.mi_thermald)" = "running" ]; then
	stop mi_thermald 2>/dev/null
	sleep 1
	start mi_thermald 2>/dev/null
fi

echo "[卸载] 完成。温度/性能相关内核状态会在重启后完全复位，请重启一次手机。"
