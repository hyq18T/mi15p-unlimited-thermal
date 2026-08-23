# 小米 15 Pro 无限制去温控模块

适配小米 15 Pro（`haotian` / `2410DPN6CC`）的 Magisk / KernelSU 去温控模块，v3.2.2。

## 功能

- 解除充电相关温控：有线/无线充电热保护关闭、充电电流上限放开、无线磁吸与快充控制限制清除、反向充电限制关闭。
- 关闭系统热消息限制：屏幕最高亮度、下载限速、Modem/WiFi 限流、闪光灯、语音、NTN、云游戏、Super HDR、动态温控等节点统一放行。
- 替换温控配置文件：写入 `/data/vendor/thermal/config`，覆盖充电、游戏、视频、相机、导航、AR/VR 等场景配置，全部改为无限制策略。
- 提高温控墙：CPU、GPU、DDR、Modem、CDSP、XO 等热区的 trip point 低于 `110000` 的档位抬到 `110000`；BCL / 电池电流 / 电池电压 / SOC 类节点保持不变。
- 关闭显示降级：关闭热降亮度、热降刷新率、SystemUI 温控阶梯和厂商提频温控阶梯。
- 默认均衡调度：无论充电与否统一使用 `balanced_mode`，执行一次后退出，不保留后台进程。
- 极致性能属性默认全部关闭，不会额外锁频或强制最高性能释放。

## 版本 v3.2.2 修复内容

旧版本开机写入 `remove_temp_limit 1`，会触发小米充电驱动把 `fake_soc=55`、`fake_temp=500` 持久化到独立 `charger` 分区，导致重启后卡 55% 电量 / 50°C，且卸载、恢复出厂、降级都无法清除。

v3.2.2 改为写入 `remove_temp_limit 0`，保留其它去温控功能，不再写坏电量与温度节点。详细说明见 [docs/卡55电量50度修复说明.md](docs/卡55电量50度修复说明.md)。

## 安装

1. 下载 [release/mi15p_unlimited_thermal_v3.2.2.zip](release/mi15p_unlimited_thermal_v3.2.2.zip)。
2. 在 Magisk 或 KernelSU 中刷入，安装完成后重启。
3. 卸载时直接移除模块并重启，卸载脚本会还原温控配置、系统设置和关键 sysfs 开关。

安装脚本带机型校验，仅允许 `haotian`（小米 15 Pro）刷入。

## 校验

安装包 SHA256：

```text
07AC9C4D569705541FE2458B849D6264A79717648F55B9928CE4FE25BF8064EA  mi15p_unlimited_thermal_v3.2.2.zip
```

## 风险

- 去除温控和大幅提高温控墙会让设备在重负载或充电场景下温度明显升高，可能导致降频失效、电池损耗加快、硬件过热，请自行评估风险。
- 仅适配小米 15 Pro，其它机型请勿刷入。
- 请勿再执行 `remove_temp_limit 1` 写入，否则可能再次触发卡 55% 电量 / 50°C。

## 目录

```text
source/
  module.prop
  service.sh
  customize.sh
  uninstall.sh
  system.prop
  bin/
    ultra_performance.sh
    ultra_performance
  haotian/danger/*.conf
release/
  mi15p_unlimited_thermal_v3.2.2.zip
  SHA256SUMS.txt
docs/
  卡55电量50度修复说明.md
```

模块仅供学习交流，请勿用于商业用途。
