#!/system/bin/sh

MODDIR=${0%/*}
THERMAL_DIR=/data/vendor/thermal
CONFIG="$THERMAL_DIR/config"
SRC="$MODDIR/haotian/danger"
SET_TRIP_POINT_TEMP_MAX=110000
BACKUP_FILE="$MODDIR/settings_backup"

chmod 0755 "$MODDIR/bin/ultra_performance.sh" 2>/dev/null

wait_sys_boot_completed() {
	local i=20
	until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$i" -le 0 ]; do
		i=$((i-1))
		sleep 9
	done
}

backup_setting() {
	local ns="$1"
	local key="$2"
	[ -n "$ns" ] && [ -n "$key" ] || return 0
	if ! grep -q "^$ns $key=" "$BACKUP_FILE" 2>/dev/null; then
		local val
		val=$(settings get "$ns" "$key" 2>/dev/null)
		[ -n "$val" ] || val="__unset__"
		echo "$ns $key=$val" >> "$BACKUP_FILE"
	fi
}

write_if_exists() {
	[ -w "$1" ] || return 1
	echo "$2" > "$1" 2>/dev/null
}

unlock_thermal_nodes() {
	write_if_exists /sys/devices/platform/soc/soc:mca_business_charger/debug_ctrl "remove_temp_limit 0"
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wired_thermal_remove 1
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_thermal_remove 1
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wired_chg_curr 22000000
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wired_chg_curr2 22000000
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_ctrl_limit 0
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wireless_mag_ctrl_limit 0
	write_if_exists /sys/class/xm_power/charger/charger_thermal/wls_quick_chg_control_limit 0
	write_if_exists /sys/class/xm_power/charger/charger_common/revchg_bcl 0

	for NODE in thermal_max_brightness market_download_limit modem_limit modem_level poor_modem_limit \
		wifi_limit torch_level voice_limit ntn_limit temp_state super_hdr cloud_game dynamic_tj; do
		write_if_exists "/sys/class/thermal/thermal_message/$NODE" 0
	done

	write_if_exists /sys/class/thermal/power_save/power_level 100000000
}

apply_thermal_config() {
	[ -d "$SRC" ] || return 1
	mkdir -p "$CONFIG"
	local i=0
	while [ "$i" -lt 5 ]; do
		chattr -i "$CONFIG" "$CONFIG"/* 2>/dev/null
		rm -rf "$CONFIG"/* 2>/dev/null
		[ "$(ls "$CONFIG" 2>/dev/null | wc -l)" -eq 0 ] && break
		i=$((i+1))
		sleep 1
	done
	cp -f "$SRC"/* "$CONFIG"
	if [ "$(ls "$CONFIG" | wc -l)" -lt 24 ]; then
		cp -f "$SRC"/* "$CONFIG" 2>/dev/null
	fi
	chmod -R 0771 "$THERMAL_DIR"
	chown -R root:system "$CONFIG" 2>/dev/null
	chown root:system "$THERMAL_DIR/decrypt.txt" 2>/dev/null
	chown system:system "$THERMAL_DIR/report.dump" 2>/dev/null
	chown system:system "$THERMAL_DIR/thermal-global-mode" 2>/dev/null
	chown system:system "$THERMAL_DIR/thermal.dump" 2>/dev/null
	restorecon -DFR "$THERMAL_DIR" 2>/dev/null
	chattr +i "$CONFIG"/* 2>/dev/null
}

raise_thermal_wall() {
	for CPU_ONLINE in $(ls /sys/devices/system/cpu/cpu*/online 2>/dev/null); do
		if [ "$(cat "$CPU_ONLINE")" = "0" ]; then
			echo "1" > "$CPU_ONLINE"
		fi
	done

	for CPUFREQ_POLICY_PATH in $(ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null); do
		if [ -f "${CPUFREQ_POLICY_PATH}/cpuinfo_max_freq" ] && [ -f "${CPUFREQ_POLICY_PATH}/scaling_max_freq" ]; then
			echo "$(cat "${CPUFREQ_POLICY_PATH}/cpuinfo_max_freq")" > "${CPUFREQ_POLICY_PATH}/scaling_max_freq"
		fi
	done

	for THERMAL_ZONE in $(ls /sys/class/thermal/thermal_zone*/type); do
		ZONE_TYPE=$(cat "$THERMAL_ZONE" 2>/dev/null)
		case "$ZONE_TYPE" in
			*bcl*|*ibat*|*vbat*|*socd*) continue ;;
		esac
		case "$ZONE_TYPE" in
			*cpu*|*gpu*|*ddr*|*mdmss*|*nsphvx*|*nsphmx*|*xo-therm*)
				for TRIP_POINT_TEMP in $(ls "${THERMAL_ZONE%/*}"/trip_point_*_temp 2>/dev/null); do
					if [ "$(cat "$TRIP_POINT_TEMP")" -lt "$SET_TRIP_POINT_TEMP_MAX" ]; then
						echo "$SET_TRIP_POINT_TEMP_MAX" > "$TRIP_POINT_TEMP"
					fi
				done
				;;
		esac
	done
}

set_min_uclamp() {
	local uclamp_file="/dev/cpuctl/$2/cpu.uclamp.min"
	if [ -f "$uclamp_file" ]; then
		chmod a+w "$uclamp_file"
		echo "$1" > "$uclamp_file"
		chmod a-w "$uclamp_file"
	fi
}

ensure_settings() {
	[ -n "$(getprop ro.miui.ui.version.code)" ] || return 0
	[ "$(settings get system POWER_SAVE_PRE_HIDE_MODE 2>/dev/null)" = "performance" ] || \
		settings put system POWER_SAVE_PRE_HIDE_MODE performance 2>/dev/null
	[ "$(settings get secure speed_mode_enable 2>/dev/null)" = "1" ] || \
		settings put secure speed_mode_enable 1 2>/dev/null
	[ "$(settings get system speed_mode 2>/dev/null)" = "1" ] || \
		settings put system speed_mode 1 2>/dev/null
}

wait_sys_boot_completed
pkill -f "ultra_performance" 2>/dev/null
sleep 1
unlock_thermal_nodes
apply_thermal_config
raise_thermal_wall

# 极致性能三个属性默认全部关闭：不锁频、不提最低频、不启用最大性能释放
setprop suto.perf_enh_after_power-on N
setprop suto.min_cpufreq_limit N
setprop suto.max_perf_release N

# 无论充电与否统一走 balanced_mode，执行完即退出，不保留后台进程
"$MODDIR/bin/ultra_performance.sh" balanced_mode >/dev/null 2>&1

if [ -n "$(getprop ro.miui.ui.version.code)" ]; then
	backup_setting system POWER_SAVE_PRE_HIDE_MODE
	backup_setting secure speed_mode_enable
	backup_setting system speed_mode
	backup_setting secure miui_refresh_rate
	backup_setting secure user_refresh_rate
	ensure_settings
fi

if [ -e /proc/game_opt/disable_cpufreq_limit ] && [ "$(cat /proc/game_opt/disable_cpufreq_limit)" = "0" ]; then
	echo "1" > /proc/game_opt/disable_cpufreq_limit
fi

if [ -e /sys/devices/system/cpu/cpufreq/boost ] && [ "$(cat /sys/devices/system/cpu/cpufreq/boost)" = "0" ]; then
	echo "1" > /sys/devices/system/cpu/cpufreq/boost
fi

if [ "$(settings get system peak_refresh_rate 2>/dev/null)" -ge 90 ] 2>/dev/null; then
	PEAK=$(settings get system peak_refresh_rate)
	[ "$PEAK" -ge "$(settings get secure miui_refresh_rate 2>/dev/null)" ] && {
		settings put secure miui_refresh_rate "$PEAK"
	}
	[ "$PEAK" -ge "$(settings get secure user_refresh_rate 2>/dev/null)" ] && {
		settings put secure user_refresh_rate "$PEAK"
	}
fi

set_min_uclamp 80 top-app
set_min_uclamp 15 foreground
