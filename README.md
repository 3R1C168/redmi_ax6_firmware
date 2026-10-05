# 红米 AX6 固件自动构建

用 GitHub Actions 云端自动编译红米 AX6 的 ImmortalWrt 固件（带 NSS 硬件加速）。
编译在 GitHub 的服务器上完成，本机无需安装任何环境。

## 怎么触发构建

两种方式：

1. **自动**：每周五凌晨 4 点（北京时间）自动跑一次
2. **手动**：进入本仓库 `Actions` 页面 → 左侧选 `Build Redmi AX6 Firmware` → 右侧 `Run workflow` → 绿色按钮确认

一次构建约需 **90 分钟**（实测值，2026-10-05）。

> 工作流会缓存工具链和编译中间结果，但提速有限（实测 93 分钟 → 90 分钟）。
> 每周自动跑一次完全够用，不必纠结这个数字。

## 怎么下载固件

构建完成后，进入仓库右侧 `Releases` 页面，找到日期标签（形如 `20261010`）的版本，
下载以下文件：

| 文件 | 用途 |
|------|------|
| `*-redmi_ax6-stock-squashfs-factory.ubi` | **刷过 U-Boot 的机器**第一次刷用这个 |
| `*-redmi_ax6-stock-squashfs-sysupgrade.bin` | **刷过 U-Boot 的机器**后续升级用这个 |
| `*-redmi_ax6-initramfs-factory.ubi` | 原厂机器刷机中转固件 |
| `*-redmi_ax6-squashfs-sysupgrade.bin` | 原厂机器的最终固件 |
| `SHA256SUMS.txt` | 校验码，可用来确认文件没损坏 |

**先看上一节「两个变体，选错会刷不进去」确定你该用哪个。**

只保留最近 5 个版本，更旧的会自动删除。

## 怎么改配置

改 `/.config` 文件即可，改完提交，下次构建就生效。

常见改动：

- **加插件**：加一行 `CONFIG_PACKAGE_插件名=y`
  - 例：`CONFIG_PACKAGE_luci-app-openclash=y`
  - 查插件名：在固件后台的"软件包"页面搜索，或到 ImmortalWrt 官方包索引里找
- **改时区/NTP**：由 `default-settings-chn` 包自动处理
- **换代理插件**：把 `CONFIG_PACKAGE_luci-app-nikki=y` 换成别的

## 固件里有什么

- **系统**：ImmortalWrt（VIKINGYFY 分支，内核 6.18），基于快照版
- **NSS 硬件加速**：高通网络加速驱动，已内置于内核（有线转发可用；**无线 offload 建议关闭**）
- **中文**：界面汉化、中国时区、国内 NTP、国内软件源镜像
- **主题**：Argon
- **代理**：nikki（mihomo 内核）

## ⚠️ 两个变体，选错会刷不进去

Release 里同时提供**两个变体**的固件，文件名只差 `-stock`：

| 变体 | 适用于 | 文件名特征 |
|------|--------|-----------|
| `redmi_ax6` | **没刷过**第三方 U-Boot 的机器（原厂分区表）| 含 `redmi_ax6-squashfs-` |
| **`redmi_ax6-stock`** | **刷过**第三方 U-Boot / 做过分区扩容的机器 | 含 `redmi_ax6-stock-squashfs-` |

**判据：你这台机器刷过 U-Boot 或做过分区扩容吗？**
- 刷过 → **用 `-stock` 版**
- 没刷过 → 用普通版

### 为什么会有这个区别

两者的分区表来源完全不同：

- **普通版**：分区表是**写死在固件里的**（固定偏移 `0x2dc0000`）。也就是说，它会**无视**你 U-Boot 里的分区表。
- **`-stock` 版**：从**引导程序里读取**分区表（技术名词 `qcom,smem-part`）。你扩容后的分区信息存在 U-Boot 里，所以它能**自动适配**你的扩容布局。

ImmortalWrt 官方的原话（提交 `753e8267`）：

> "有些设备使用了第三方非原厂 uboot 和 mibib，OpenWrt 的扩展布局在这些分区上**无法刷入、也无法正常启动**。"

而保留 `-stock` 变体的理由（提交 `102fcffa`）：

> "OpenWrt 的布局会**浪费约 30 MiB 空间**，这太多了。"

**选错的后果**：刷了普通版会**引导失败（起不来）或覆盖你的扩容分区**。好消息是——**不会永久变砖**，你的第三方 U-Boot 还在，进 U-Boot 的网页恢复界面重刷 `-stock` 版即可。

### `-stock` 版的刷法（与普通版不同）

`-stock` 版**没有 initramfs 中转固件**，刷法也不一样：

1. 进 **U-Boot 的网页恢复界面**（开机时按住 Reset 约 5 秒；电脑设静态 IP `192.168.1.10`，访问 `192.168.1.1`）
2. 上传 `*-redmi_ax6-stock-squashfs-factory.ubi`
3. 等它写入重启
4. 起来之后，以后升级用 `*-redmi_ax6-stock-squashfs-sysupgrade.bin`

> 普通版走的是"SSH 双分区切换"那套流程，**两者不可混用**。

## 刷机

见仓库内《红米AX6-ImmortalWrt-操作指南.md》。

**刷完机建议做一件事**：关闭无线 offload。编辑 `/etc/modules.d/ath11k`，设 `nss_offload=0`。
原因：NSS 的未修复问题集中在无线 offload 上，有线加速才是稳定可靠的。

## 空间说明

AX6 的 rootfs 分区只有 82 MB。当前固件 **约 37 MB**（实测值），留有充足可写空间。
**不要把 passwall 编进来** —— 它全量依赖 107 MB，装不下。

## 排错

- **构建失败且日志提到 nikki**：nikki 是第三方源，可能与快照版本不兼容。
  临时解决办法：删掉 `.config` 里 `CONFIG_PACKAGE_luci-app-nikki=y` 这一行，重新构建。
- **构建超时**：单次上限 350 分钟，正常 90 分钟就能完成，离上限很远。
  若真的超时，多半是上游源码引入了编译很慢的新内容，可看具体卡在哪一步。
- **磁盘不足**：工作流已包含清理磁盘步骤；若仍不足，需要精简配置。
- **产物没编出来**：工作流有守卫，会直接报错而不是发出空 Release。
  日志里搜「产物校验通过」确认成功。

## 来源与致谢

- 源码：[VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)（ImmortalWrt + NSS）
- NSS 驱动源头：高通 QSDK（经 qosmio、LiBwrt 等社区移植）
- 代理插件：[nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)
