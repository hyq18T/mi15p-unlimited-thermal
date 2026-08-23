find_sys_scaling_governor() {
	for SCALING_GOVERNOR in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
		if [ -f "$SCALING_GOVERNOR" ]; then
			echo "$SCALING_GOVERNOR"
			return 0
		fi
	done
	exit 1
}
get_default_scaling_governor() {
	SCALING_GOVERNOR_PATH=$(find_sys_scaling_governor)
	local WAITING_TIMES=60
	while [ "$WAITING_TIMES" -gt 0 ]; do
		if [ "$(cat $SCALING_GOVERNOR_PATH)" == performance ]; then
			sleep 1
			local WAITING_TIMES=$(($WAITING_TIMES-1))
		else
			DEFAULT_CPU_SCALING_GOVERNOR=$(cat $SCALING_GOVERNOR_PATH)
			local WAITING_TIMES=0
		fi
	done
	if [ -z "$DEFAULT_CPU_SCALING_GOVERNOR" ] && [ -f "${SCALING_GOVERNOR_PATH%/*}/scaling_available_governors" ]; then
		SCALING_AVAILABLE_GOVERNORS=$(cat ${SCALING_GOVERNOR_PATH%/*}/scaling_available_governors)
		if [[ "$SCALING_AVAILABLE_GOVERNORS" == *"walt"* ]]; then
			DEFAULT_CPU_SCALING_GOVERNOR=walt
		elif [[ "$SCALING_AVAILABLE_GOVERNORS" == *"schedutil"* ]]; then
			DEFAULT_CPU_SCALING_GOVERNOR=schedutil
		elif [[ "$SCALING_AVAILABLE_GOVERNORS" == *"ondemand"* ]]; then
			DEFAULT_CPU_SCALING_GOVERNOR=ondemand
		elif [[ "$SCALING_AVAILABLE_GOVERNORS" == *"conservative"* ]]; then
			DEFAULT_CPU_SCALING_GOVERNOR=conservative
		elif [[ "$SCALING_AVAILABLE_GOVERNORS" == *"powersave"* ]]; then
			DEFAULT_CPU_SCALING_GOVERNOR=powersave
		else
			exit 1
		fi
	fi
	setprop suto.default_cpu_scaling_governor $DEFAULT_CPU_SCALING_GOVERNOR
}
set_qcom_lpm() {
	if [ "$(cat $1)" != "$2" ]; then
		chmod u+w $1
		echo $2 > $1
		if [ "$3" == N ]; then
			chmod a-w $1
		elif [ "$3" == Y ]; then
			chmod u+w $1
		fi
	fi
}
set_scaling_governor() {
	for SCALING_GOVERNOR in $2; do
		if [[ -f "$SCALING_GOVERNOR" ]] && [[ "$(cat ${SCALING_GOVERNOR%/*}/scaling_available_governors)" == *"$1"* ]]; then
			chmod u+w $SCALING_GOVERNOR
			echo $1 > $SCALING_GOVERNOR
		fi
	done
}
set_freq() {
	for TARGET_PATH in $2; do
		if [[ -d "$TARGET_PATH" ]] && [[ -f "${TARGET_PATH}/$1" && -f "${TARGET_PATH}/$3" ]]; then
			chmod u+w ${TARGET_PATH}/$3
			if [ -n "$4" ]; then
				echo "$(cat ${TARGET_PATH}/$1 | awk -v mult="$4" '{print $1 * mult}')" > ${TARGET_PATH}/$3
			else
				echo "$(cat ${TARGET_PATH}/$1)" > ${TARGET_PATH}/$3
			fi
		fi
	done
}
enable_offline_cpus() {
	for CPU_ONLINE in /sys/devices/system/cpu/cpu*/online; do
		if [ "$(cat $CPU_ONLINE)" == 0 ]; then
			echo 1 > $CPU_ONLINE
		fi
	done
}
set_min_cpus() {
	for MAX_CPUS in /sys/devices/system/cpu/cpu*/core_ctl/max_cpus; do
		if [ -e "$MAX_CPUS" ] && [ "$(cat $MAX_CPUS)" != "$(cat ${MAX_CPUS%/*}/min_cpus)" ]; then
			chmod a+w "${MAX_CPUS%/*}/min_cpus"
			echo "$(cat $MAX_CPUS)" > "${MAX_CPUS%/*}/min_cpus"
			chmod a-w "${MAX_CPUS%/*}/min_cpus"
		fi
	done
}
performance_mode() {
	enable_offline_cpus
	if [ "$(getprop suto.perf_enh_after_power-on)" == normal ] && [ "$(getprop suto.max_perf_release)" != Y ]; then
		set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy*" "scaling_max_freq"
		if [ "$(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq)" -ge '3000000' ]; then
			set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy0" "scaling_min_freq" "0.5"
		else
			set_scaling_governor "performance" "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
			set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy0" "scaling_min_freq"
		fi
		set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy[1-9]*" "scaling_min_freq" "0.5"
	elif [ "$(getprop suto.perf_enh_after_power-on)" == ultra ] || [ "$(getprop suto.max_perf_release)" == Y ]; then
		set_scaling_governor "performance" "/sys/devices/system/cpu/cpufreq/policy*/scaling_governor"
		set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy*" "scaling_max_freq"
		set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy*" "scaling_min_freq"
	fi
	if [ -f /sys/devices/system/cpu/qcom_lpm/parameters/sleep_disabled ]; then
		set_qcom_lpm "/sys/devices/system/cpu/qcom_lpm/parameters/sleep_disabled" "1" "N"
	elif [ -f /sys/module/lpm_levels/parameters/sleep_disabled ]; then
		set_qcom_lpm "/sys/module/lpm_levels/parameters/sleep_disabled" "Y" "N"
	fi
	if [ "$(cat /sys/devices/system/cpu/c1dcvs/enable_c1dcvs 2>/dev/null)" == 1 ]; then
		echo 0 > /sys/devices/system/cpu/c1dcvs/enable_c1dcvs
	fi
	set_freq "hw_max_freq" "/sys/devices/system/cpu/bus_dcvs/*" "boost_freq"
}
balanced_mode() {
	enable_offline_cpus
	set_scaling_governor "$(getprop suto.default_cpu_scaling_governor)" "/sys/devices/system/cpu/cpufreq/policy*/scaling_governor"
	if [ -f /sys/devices/system/cpu/qcom_lpm/parameters/sleep_disabled ]; then
		set_qcom_lpm "/sys/devices/system/cpu/qcom_lpm/parameters/sleep_disabled" "0" "Y"
	elif [ -f /sys/module/lpm_levels/parameters/sleep_disabled ]; then
		set_qcom_lpm "/sys/module/lpm_levels/parameters/sleep_disabled" "N" "Y"
	fi
	if [ "$(cat /sys/devices/system/cpu/c1dcvs/enable_c1dcvs 2>/dev/null)" == 0 ]; then
		echo 1 > /sys/devices/system/cpu/c1dcvs/enable_c1dcvs
	fi
	set_freq "hw_min_freq" "/sys/devices/system/cpu/bus_dcvs/*" "boost_freq"
	if [ "$(getprop suto.min_cpufreq_limit)" == Y ]; then
		set_freq "cpuinfo_min_freq" "/sys/devices/system/cpu/cpufreq/policy0" "scaling_min_freq" "2"
		set_freq "cpuinfo_min_freq" "/sys/devices/system/cpu/cpufreq/policy[1-9]*" "scaling_min_freq" "1.3"
	else
		set_freq "cpuinfo_max_freq" "/sys/devices/system/cpu/cpufreq/policy*" "scaling_max_freq"
		set_freq "cpuinfo_min_freq" "/sys/devices/system/cpu/cpufreq/policy*" "scaling_min_freq"
	fi
	set_min_cpus
}
main() {
	if [ -z "$(getprop suto.default_cpu_scaling_governor)" ]; then
		get_default_scaling_governor
	fi
	if [ "$1" == performance_mode ]; then
		[ "$(getprop suto.perf_enh_after_power-on)" == N ] || performance_mode
		exit 0
	elif [ "$(getprop suto.max_perf_release)" == Y ]; then
		performance_mode
	elif [ "$1" == balanced_mode ]; then
		balanced_mode
		exit 0
	else
		exit 1
	fi
}
main "$@"
