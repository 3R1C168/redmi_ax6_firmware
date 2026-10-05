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
| `*-initramfs-factory.ubi` | 刷机中转固件（第一次刷机用）|
| `*-squashfs-sysupgrade.bin` | 最终固件 |
| `SHA256SUMS.txt` | 校验码，可用来确认文件没损坏 |

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
