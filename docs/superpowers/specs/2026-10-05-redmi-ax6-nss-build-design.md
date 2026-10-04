# 红米 AX6 固件自动构建项目 — 设计文档

- 日期：2026-10-05
- 状态：待用户审阅
- 目标仓库：待建（公开仓库，账号 `3R1C168`）
- 本地目录：`D:\Documents\Projects\redmi_ax6_firmware`

---

## 1. 这个项目要干什么

一句话：**每周自动在 GitHub 的云电脑上编译一次红米 AX6 的 ImmortalWrt 固件（带 NSS 硬件加速），编好放到 Release 里让你下载。**

你的电脑全程不用开工，也不用装 Linux。

### 为什么这样做解决了"同步"问题

你最初的表述是"同步 immortalwrt 和 nss 驱动"。这里有个关键事实需要说清楚：

**NSS 不是一个能"添加"的插件，它是长在源码树里的。** 具体表现（已核实）：

- NSS 驱动源码在 `package/qca-nss/` 目录下（一整套：drv、ecm、crypto、clients 等）
- 内核补丁在 `target/linux/qualcommax/patches-6.18/` 下共 111 个，其中 NSS 相关 17 个、ECM 相关 8 个
- 无线 NSS 补丁在 `package/kernel/mac80211/patches/nss/` 下约 85 个
- 目标平台的默认包清单里，一长串 `kmod-qca-nss-*` **已经是默认包含的**

这意味着：**"官方 ImmortalWrt + 外挂 NSS"拼不出能用的固件**，因为补丁必须打进内核。

所以本项目的"同步"实现方式是：

> 每周从 `VIKINGYFY/immortalwrt` 的 `main` 分支拉取最新代码。
> 这个分支本身就是 **ImmortalWrt + NSS 的合体版**。
> 拉它 = 同时拿到 ImmortalWrt 的更新 + NSS 驱动的更新。

---

## 2. 已确认的决策

| 项目 | 决定 | 理由 |
|------|------|------|
| 源码基础 | `VIKINGYFY/immortalwrt` 的 `main` 分支 | 高通专用、带满血 NSS、已支持 AX6 |
| 目标设备 | 只编 `redmi_ax6` | 你刷机用这个；只编一个构建时间减半 |
| 预装插件 | `default-settings-chn` + 防火墙汉化 + Argon 主题全家桶（5 个官方包）| 全部在官方源内，稳定；已确认接受国内镜像源 |
| 代理插件 | **nikki**（mihomo 内核），编进固件 | 见 5.2.1 节——空间账、Go 编译代价均已核实 |
| 首次构建策略 | 一次到位（含全部插件）| 工具链只编一次，之后每周复用 |
| nikki | **不预装** | 第三方源，会引入构建失败风险；以后可在路由器里装 |
| Release 保留 | 最近 5 个 | 仓库不会无限变大 |
| 仓库公开性 | 公开 | Actions 构建时长免费且不限量 |
| 构建方案 | 完整编译 + 缓存 | 第二次起把 3~4 小时压到 1~2 小时 |

---

## 3. 架构设计

### 3.1 核心思路：仓库只放"配方"，不放"原料"

这个项目仓库里**不放 OpenWrt 源码**（那有几百 MB 到几十 GB）。仓库里只放三样东西：

1. **配置**——说明要编哪个设备、装哪些插件
2. **工作流**——告诉 GitHub 每周怎么干活
3. **说明文档**——给你自己看的

源码由 GitHub 的云电脑在构建时**临时下载**，用完即弃。

打个比方：这个仓库就像一张**菜谱**。菜谱很薄，因为你不用把菜市场的菜买回家存着——每次做菜时现去买。

### 3.2 数据流

```
┌─────────────────────────────────────────────────┐
│ GitHub 云电脑（每周四自动，或你手动点一下）        │
└─────────────────────────────────────────────────┘
         │
         │ ① 清理磁盘（腾出空间）
         ▼
   ② 拉取源码：VIKINGYFY/immortalwrt main 分支
         │
         │ ③ 套用配方：config/redmi_ax6.config
         ▼
   ④ 拉取软件包：feeds update + install
         │
         │ ⑤ 下载编译依赖（这一步用缓存加速）
         ▼
   ⑥ 开始编译（约 1~4 小时，用缓存则更快）
         │
         │ ⑦ 从缓存恢复 / 保存到缓存
         ▼
   ⑧ 打包成 Release（含固件 + 校验码）
         │
         │ ⑨ 删掉第 6 个及更早的旧 Release
         ▼
┌─────────────────────────────────────────────────┐
│ 你从 Releases 页面下载固件                        │
└─────────────────────────────────────────────────┘
```

### 3.3 文件结构

```
redmi_ax6_firmware/
├── .github/
│   └── workflows/
│       └── build.yml              # 核心：自动构建工作流
├── config/
│   └── redmi_ax6.config           # 配方：设备 + 插件清单
├── scripts/
│   └── diy.sh                     # 编译前的自定义小调整（预留）
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-10-05-redmi-ax6-nss-build-design.md   # 本文档
├── 红米AX6-ImmortalWrt-操作指南.md  # 已有文档，移入
└── README.md                      # 使用说明
```

**每个文件的职责（一个文件干一件事）：**

| 文件 | 干什么 | 你想改东西时改哪 |
|------|--------|-----------------|
| `build.yml` | 定义"每周几点编、怎么编、编完怎么发" | 改时间、改构建参数 |
| `redmi_ax6.config` | 定义"编哪个设备、装哪些插件" | **加插件、换设备**（最常改这个）|
| `diy.sh` | 编译前跑的小脚本 | 改主机名、改默认设置等 |
| `README.md` | 你自己看的说明书 | — |

---

## 4. 工作流详解

### 4.1 触发方式

| 方式 | 说明 |
|------|------|
| **定时** | 每周四 UTC 20:00（北京时间周五 04:00）自动跑 |
| **手动** | 在仓库 Actions 页面点 "Run workflow" 按钮随时跑 |

> 第一次**必须手动触发**，用来验证整条链路能不能跑通。

### 4.2 运行环境

- 系统：`ubuntu-24.04`
- 配置：GitHub 免费提供的标准云电脑（4 核 CPU、16G 内存）

### 4.3 工作流步骤

1. **检出本仓库**（拿到配方文件）
2. **清理磁盘**——删掉云电脑里预装但用不上的东西（.NET、Android SDK、Java 等），腾出约 30G 空间
3. **拉取源码**——`VIKINGYFY/immortalwrt` 的 `main` 分支，浅克隆（只拉最新一版，不拉全部历史，省时间省空间）
4. **记录源码版本号**——把这次编的是哪个提交记下来，写进 Release 说明，方便你日后追溯
5. **应用配方**——把 `config/redmi_ax6.config` 复制进去，跑 `make defconfig` 展开
6. **执行 diy.sh**——如果你以后想改点什么（比如主机名），在这里改
7. **拉取软件包**——`./scripts/feeds update -a && ./scripts/feeds install -a`
8. **下载依赖**——`make download -j8`（这一步开始用缓存）
9. **编译**——`make -j$(nproc)`，开启 ccache
10. **收集产物**——从 `bin/targets/qualcommax/ipq807x/` 取固件，生成校验码
11. **发布 Release**——标签用日期命名（如 `20261009`）
12. **清理旧 Release**——只保留最近 5 个

### 4.4 缓存策略

#### 先纠正一个常见误解

很多人以为"先编一个不带插件的版本，就能给带插件的版本预热缓存"。**这个想法不成立。**

原因：ccache 是**编译器的结果缓存**——它记的是"这段 C 代码用这些参数编译过，结果是啥"。**没被选中的软件包压根不进编译器**，自然没有任何缓存可存。

| 先编基础版，再编带插件版 | 实际效果 |
|---|---|
| 交叉工具链 | ✅ 第二次复用（**最大头，约 1 小时**）|
| 内核、基础系统包 | ✅ 第二次复用 |
| **新加的 5 个插件** | ❌ **无缓存可复用——它们第一次没编译过，第二次才是首次编译** |

**结论**：分两步走确实会变快，但**不是因为插件被缓存了，而是因为工具链和内核被缓存了**。而这部分缓存，分不分步都会产生。

#### 该缓存什么（三层）

| 缓存内容 | 是什么 | 作用 | 典型体积 |
|----------|--------|------|---------|
| `dl/` | 下载的源码压缩包 | 省去重复下载 | 约 1~2 GB |
| `.ccache` | C 代码编译结果 | 省去重复编译 | 约 1~3 GB |
| **`staging_dir/`** | **编译好的交叉工具链** | **省去重编工具链（最大头）** | **约 3~6 GB** |

**`staging_dir/` 是最关键的一层。** 交叉工具链的构建约占一次完整编译 1/3 到 1/2 的时间，缓存它收益最大。成熟的工作流（如 `fichenx/Actions-OpenWrt`）正是同时缓存 `.ccache` 和 `staging_dir` 两层。

> 需要 `CONFIG_DEVEL=y` + `CONFIG_CCACHE=y` 才能让 ccache 生效（见 5.3 节）。
> 注：`staging_dir` 缓存对构建路径敏感。GitHub 跑者的路径固定（`/home/runner/work/<仓库>/<仓库>`），因此可行。

#### 10 GB 上限是关键约束

GitHub 每个仓库的缓存总额上限是 **10 GB**（已核实）。上面三层加起来可能逼近甚至超过，超了会淘汰旧缓存。

对策：
- 缓存键（key）随源码版本变化，让失效的旧缓存尽快被淘汰
- 保存缓存时用 `if: always()`——这样即使编译中途失败，已产生的缓存也能保留下来（`fichenx` 的工作流正是这么做的）

#### 缓存失效怎么办

工作流设计成"缓存拿不到就全新编译"，不会因为缓存坏了而失败，只是变慢。

#### 关于"分两步走"

**建议：第一次直接用完整配置跑一次。**

需要区分两类插件：

| 类型 | 包 | 编译代价 | 分两步有用吗 |
|------|-----|---------|------------|
| 脚本/翻译类 | `default-settings-chn`、Argon 主题、各 i18n | 几乎为零（`Build/Compile` 为空，i18n 走 `po2lmo` 转换）| 无意义 |
| **Go 程序** | **nikki / mihomo** | **需要 Go 工具链，首次明显耗时** | **ccache 无效**（Go 不走 ccache）|

**真正的风险（NSS 补丁、内核、工具链）在两种配置里完全一样**，分成两步既躲不掉风险，又要多花一次构建时间。

**唯一值得分两步的情况**：你想先验证"NSS 内核 + 基础系统"这条主干能编通，把 nikki 这个第三方变量排除在外。这属于排错策略，不是提速策略。若采用，做法是第一次构建用不含 nikki 的配置，成功后再加 nikki 编第二次。

> 无论哪种，**每周自动构建在第一次成功后都会变快**（`staging_dir` 缓存跨周复用）。分不分步只影响你的第一次搭建。

---

## 5. 配方内容（`redmi_ax6.config`）

### 5.1 设备选择

```
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_DEVICE_qualcommax_ipq807x_DEVICE_redmi_ax6=y
CONFIG_TARGET_PER_DEVICE_ROOTFS=y
```

> 这三行是压缩包派生的确切符号名。`redmi_ax6-stock` 不启用（只编一个设备）。

### 5.2 预装插件

#### 先看默认带什么（已核实原文）

默认包分三层，跟官方 ImmortalWrt 对比后：

| 层 | 内容 | 与官方差异 |
|----|------|-----------|
| **① 基础层**（`include/target.mk`）| `base-files`、`ca-bundle`、`dropbear`（SSH）、`fstools`、`libc`、`mtd`、`netifd`、`uci`、`urandom-seed`、`urngd`、`procd-ujail`；路由相关加 `dnsmasq-full`、`firewall4`、`nftables`、`kmod-nft-offload`、`odhcp6c`、`odhcpd-ipv6only`、`ppp`、`ppp-mod-pppoe` | **完全相同** |
| **② 网页后台**（`luci` 元包 → `luci-light`）| `luci-app-firewall`、`luci-mod-admin-full`、`luci-proto-ppp`、`luci-theme-bootstrap`，外加 `luci-app-package-manager` | 相同 |
| **③ 目标平台层**（`qualcommax/Makefile`）| `autocore`、`automount`、`cpufreq`、`e2fsprogs`、`f2fs-tools`、`losetup`、`luci`、`uboot-envtools`、`wpad-openssl` + 一批平台驱动 + **NSS 全套 22 个内核模块** | **这里才是差异** |

#### 那"非 ImmortalWrt 自带"的到底是什么？

**只有 NSS 那一套**（外加几个平台专用驱动）。具体：

- 源码树里多出一个 `package/qca-nss/` 目录，含 10 个子包：`nss-firmware`、`qca-nss-drv`、`qca-nss-ecm`、`qca-nss-dp`、`qca-nss-crypto`、`qca-nss-clients`、`qca-nss-phy`、`qca-mcs`、`qca-ssdk`、`nss-eip-firmware`
- 目标平台默认含 22 个 `kmod-qca-nss-*` 内核模块
- 另加平台驱动：`kmod-ath11k-pci`、`kmod-dsa`、`kmod-dsa-qca8k`、`kmod-phy-aquantia`、`kmod-phy-qca83xx`、`kmod-fs-ext4`、`kmod-fs-f2fs`、`kmod-leds-pwm`、`kmod-usb-serial-qualcomm`

**但严格说，NSS 也不算"作者的第三方代码"** —— 驱动源码来自高通官方，作者做的是放进源码树 + 写内核补丁（详见第 1 节）。

**作者自己的第三方插件不在此列。** 作者另有一个 `VIKINGYFY/packages` 仓库，含 `axonhub`、`gecoosac`、`luci-app-wolultra` 等自研插件，但**默认构建完全不引用它**（`feeds.conf.default` 只指向官方源，全树无引用）。要装得手动加源。

> **关键结论：默认构建里，用户可见的 LuCI 插件只有"防火墙"和"软件包管理"两个。默认主题是 bootstrap（不是 Argon）。中文翻译文件一个都没装。**

#### 本项目要额外加的包（均已核实存在于 luci 源）

**最终清单（已由用户确认）：**

| 包名 | 是什么 |
|------|--------|
| `default-settings-chn` | 面向中国用户的默认设置（自动带中文基础包，见下）|
| `luci-i18n-firewall-zh-cn` | 防火墙界面汉化 |
| `luci-theme-argon` | Argon 主题本体 |
| `luci-app-argon-config` | Argon 主题设置面板 |
| `luci-i18n-argon-config-zh-cn` | 主题设置面板汉化 |

> 不需要单独写 `luci-i18n-base-zh-cn`——`default-settings-chn` 的依赖里已经包含它，编译时会自动装上。

**重点说明 `default-settings-chn`** —— 这个包性价比很高，它**自动依赖** `luci-i18n-base-zh-cn`（中文基础界面包），装它一个等于装两个，并额外做三件事：

1. 时区设为 `Asia/Shanghai`
2. NTP 服务器换成 `ntp.tencent.com`、`ntp.aliyun.com`、`ntp.ntsc.ac.cn`、`cn.ntp.org.cn`
3. 软件源替换为国内镜像 `https://mirrors.vsean.net/openwrt`

> **用户已确认接受第 3 条**：软件源会从官方改为第三方镜像 `mirrors.vsean.net`，换取国内下载速度。这是知情决策，不是疏漏。

> 注：`default-settings-chn` 顶部有 `system.@imm_init[0].system_chn` 判断，只在其未设置时生效，不会反复覆盖你后来的改动。

### 5.2.1 代理插件：为什么选 nikki 而不是 passwall

#### 空间账（已核实，这是决定性因素）

AX6 的 rootfs 分区只有 **82.1 MB**（设备树原文 `reg = <0x2dc0000 0x5220000>`）。

| 方案 | 解压后体积 | 装得下吗 |
|------|-----------|---------|
| **passwall 全量** | **107.0 MB** | ❌ **超出分区总容量** |
| passwall 精简（只留 xray 一个核心）| 38.8 MB | ✅ 勉强 |
| openclash | 21.6 MB | ✅ |
| **nikki（只需 mihomo 一个核心）** | 约 40 MB | ✅ |

passwall 之所以臃肿，是因为它默认同时拉进**三个代理核心**：

```
sing-box      40.1 MB
xray-core     26.4 MB
v2ray-plugin  14.4 MB
ss-rust ×2    13.6 MB
```

而实际使用时你只会选其中一个。这就是不选它的原因。

#### 一个反直觉但重要的发现：烧进固件比事后装更省空间

| 方式 | 原理 | mihomo 占用 | 剩余可写空间 |
|------|------|------------|-------------|
| **烧进固件** | 包在 squashfs 里，**是压缩的** | **19.5 MB** | **46.9 MB** ✅ |
| 事后安装 | 包在 overlay 里，**不压缩** | 40 MB | 26.5 MB ⚠️ |

**结论：把 nikki 编进固件，反而比刷完机再装省一半空间。** 固件体积从 15.6 MB 增到约 35.2 MB，仍在 82 MB 分区内，且可写空间宽裕。

#### 编译代价：需要编 Go 程序（必须知情）

nikki 的代理内核 `mihomo` 是 **Go 语言程序**，编译配方明确要求 Go 工具链（`PKG_BUILD_DEPENDS:=golang/host`）。影响：

1. **首次构建需要先构建 Go 工具链**，时间明显增加
2. **ccache 对 Go 无效**——ccache 只缓存 C/C++ 结果，Go 用自己的编译器。所以"先编基础版给插件预热缓存"对本项目**没有意义**
3. Go 工具链一旦构建好，会存在 `staging_dir` 里被缓存，**后续每周构建直接复用**

> 这也是 4.4 节强调 `staging_dir` 缓存比 ccache 更重要的原因。

#### 集成方式

在构建时把 nikki 的源码仓库作为额外软件源加入：

```
src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git
```

然后配置 `CONFIG_PACKAGE_luci-app-nikki=y`（会自动带上 `nikki` 和 `mihomo`）。

要装的包：`luci-app-nikki`、`nikki`、`mihomo-meta`（`VARIANT:=meta`，是默认变体）。

#### 需要你刷机后手动做的一步

nikki **不在官方源**，它是第三方项目。装好后需要你在路由器上配置订阅、节点等——这些无法预置。

另外 nikki 的 `feed.sh` 是**给路由器用的**（往路由器加预编译包源），不是给编译用的，别混淆。

### 5.2.2 为什么 open-box 也不能编进固件

用户曾问：基于 sing-box 的 Open-Box 能不能预装？核实后结论是**不能**，原因有三，任一都足以否决。

#### 原因一：体积是硬伤（决定性）

Open-Box 是个"全家桶"，一个包同时塞进三样东西（已核实，来源：其 release 的 `components.json`）：

| 组件 | 是什么 | 压缩体积 |
|------|--------|---------|
| `app` | Open-Box 面板本体 | 11.2 MB |
| **`runtime`** | **Node.js 运行环境**（`node/bin/node` + libstdc++）| **37.0 MB** |
| `kernel` | sing-box 内核 | 14.0 MB |
| **合计** | | **62.2 MB**（整个 bundle 71.7 MB）|

**关键点：它自带一个 Node.js 运行时。** 这是它体积巨大的根本原因——它的管理面板是个网页服务，靠 Node.js 跑。

而该包的安装逻辑是**把整个 `_core/` 目录完整铺到 `/opt/open-box/`**（Makefile 原文：`$(CP) $(PKG_BUILD_DIR)/_core/* $(1)/opt/open-box/`）。这些内容是**解压后**放进固件的，不是压缩存放。

对照 AX6 的账：

```
rootfs 分区总量            82.1 MB
系统本体（压缩 squashfs）   15.6 MB
------------------------------------
可容纳的插件               约 66 MB
Open-Box 解压后            远超此数（仅 Node.js 一项解压后就很大）
```

**结论：装不下。** 连压缩包本身（71.7 MB）就已经逼近分区上限。

#### 原因二：它的包装包 Makefile 是坏的

存在一个正规的 LuCI 包 `kiddin9/luci-app-open-box`（有 `Makefile`、`po/zh_Hans` 中文翻译、`root/` 配置），架构映射 `aarch64 → arm64` 也对得上 AX6。

**但它写死的版本号指向一个已不存在的 release：**

```
Makefile: PKG_VERSION:=0.1.263
          PKG_SOURCE_URL:=.../releases/download/v$(PKG_VERSION)/

实际情况: 该仓库仅有 10 个 release，最新 v0.1.282
          v0.1.263 查询返回 404 Not Found
```

原因推测：Open-Box 作者会清理旧 release，而这个包装包写死了版本号，版本一被清理就失效。**构建时会直接下载失败。**

#### 原因三：包装包本身很脆弱

`kiddin9/luci-app-open-box`：**0 星、0 fork**，仓库创建于 2026-09-28，仅三次提交（其中两次是"上传文件"）。属新建立、无社区验证的仓库。

#### 那 Open-Box 到底适合什么设备

其官方文档的目标是**有存储空间的 x86_64 / aarch64 盒子或主机**：文档里提到 ESXi 虚拟化、手机 App 与路由器共用内核、`/opt` 目录等。它明确不是为 128 MB NAND 路由器设计的。

#### 如果仍想用 Open-Box

**唯一可行路径是刷机后装到外置存储上。** AX6 自带 USB 3.0 口（默认包里有 `kmod-usb3`、`kmod-usb-dwc3-qcom`），可以插 U 盘/固态，把 `/opt` 挂到外置盘，再跑它的 `install.sh`。

这属于刷机后的手动操作，**不在本项目范围内**，但在技术上可行，记录下来备查。

#### 三个方案对照（AX6 视角）

| 方案 | 压缩后占用 | 能编进固件吗 | 说明 |
|------|-----------|-------------|------|
| **nikki（mihomo）** | **19.5 MB** | ✅ **可以** | 单内核，空间宽裕，本项目采用 |
| open-box | 71.7 MB | ❌ 不行 | 自带 Node.js 运行时，体积过大 |
| passwall 全量 | 107.0 MB（解压） | ❌ 不行 | 同时带三个代理核心 |

**nikki 是三者中唯一装得下的。**

#### 关于包管理器（会影响你日后装插件的方式）

该树基于 ImmortalWrt **snapshot/master**（`VERSION_NUMBER` 默认 `SNAPSHOT`），master 已迁移到 **APK** 包管理器。树里 `package/system/apk` 和 `package/system/opkg` 都存在，**默认很可能用 `apk`**。

**影响**：日后在路由器上装插件，命令可能是 `apk add 包名` 而不是 `opkg install 包名`。刷机后跑 `apk --version` 就能确认。这一点会写进 README。

> 由于是 snapshot 而非稳定版，这也意味着：**没有固定的版本号**，Release 标签用构建日期命名更清晰。

### 5.3 NSS 相关

**无需手动添加。** 目标平台 `DEFAULT_PACKAGES` 已默认包含完整 NSS 驱动（`kmod-qca-nss-drv`、`kmod-qca-nss-ecm`、`kmod-qca-nss-dp`、`kmod-qca-ssdk`、`kmod-qca-nss-crypto` 等）。

编译选项：
```
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_CCACHE_DIR="/home/runner/.ccache"
```

> **注意**：`CONFIG_CCACHE` 在源码树里被定义为"仅当 `DEVEL` 开启时可见"（`config/Config-devel.in` 中 `bool "Use ccache" if DEVEL`）。因此**必须同时开启 `CONFIG_DEVEL=y`**，否则 ccache 选项不会生效，缓存也就无从谈起。这是已核实的技术细节。

### 5.4 编译后需要你手动做的一步

**无线 NSS offload 默认可能是开的，建议你在路由器里关掉。** 原因：前面调研发现，NSS 的**未修复 bug 全部集中在无线 offload 这条路径上**（苹果设备掉线、部分机型无线崩溃等），而有线加速是稳定可靠的。

配置方式：在路由器上编辑 `/etc/modules.d/ath11k`，设置 `nss_offload=0`。

> 这一条会写进 README 提醒你。

---

## 6. 风险与对策

诚实列出已知风险，不粉饰。

| 风险 | 严重度 | 对策 |
|------|--------|------|
| **磁盘空间不足**——内核 6.18 + NSS 体积大，云电脑默认空闲空间不够 | 高 | 工作流第 2 步专门清理磁盘，可腾出约 30G；若仍不够，追加清理 `/usr/local/lib/android`、`/opt/ghc`、`/usr/local/.ghcup` 等目录 |
| **首次编译可能超时**——GitHub 单次任务上限 6 小时，无缓存时可能接近上限 | 中 | 只编一个设备；后续靠缓存降到 1~2 小时 |
| **超时导致缓存没保存**——任务被强杀时，缓存保存步骤可能不执行 | 中 | 在编译中途也主动保存一次缓存；详见实施计划 |
| **上游源码变动导致编译失败**——VIKINGYFY 推送了有问题的提交 | 中 | Release 说明里记录提交号，出问题可回退到上一个能用的版本 |
| **upstream 代理插件源变动**——nikki 是第三方项目，其源码可能不兼容我们的快照版本 | 中 | 构建失败时先单独用基础配置验证；Release 记录提交号；必要时临时移除 nikki |
| **上游项目停更**——VIKINGYFY 及 nikki 均为个人维护 | 低 | 属外部风险，无法技术解决；文档中说明如何切换到官方 ImmortalWrt 或 qosmio 源码 |
| **构建产物超出闪存**——AX6 只有 128M NAND | 低 | 只装必要插件；编译时会自动报错，不会产生刷不进去的固件 |

> **关于免费额度**：公开仓库使用标准云电脑，Actions 构建时长免费且不限量。GitHub 不为免费账号提供更大的机器，所以"磁盘不够就换大机器"这条路不存在——只能靠清理磁盘和精简编译内容解决。

---

## 7. 怎么验证成功了

构建完成后，检查这几项（实施时逐条验证）：

1. Actions 页面显示绿色对勾（不是红色叉）
2. Release 里出现固件文件，文件名特征是同时包含 `qualcommax-ipq807x` 和 `redmi_ax6`，典型形如：
   - `<前缀>-qualcommax-ipq807x-redmi_ax6-initramfs-factory.ubi`
   - `<前缀>-qualcommax-ipq807x-redmi_ax6-squashfs-sysupgrade.bin`
   - 以及 `sha256sums` 校验文件
   > 前缀取决于源码的版本号配置（该树基于 snapshot，前缀可能是 `immortalwrt` 或含日期），**以实际产出为准**，不以本文字面为准。
3. Release 说明里记录了源码提交号
4. 固件体积合理（sysupgrade 预期约 30~40 MB，含 mihomo 压缩后约 19.5 MB；超过 50 MB 要警惕）

**无法自动验证的**：固件实际刷机后能否正常工作。这个只能你收到后自己刷机验证。

---

## 8. 本项目不做什么（YAGNI）

明确划出边界，避免范围膨胀：

- ❌ **不做 passwall**——全量依赖 107 MB，超出 AX6 的 82 MB 分区，装不下
- ❌ **不做 openclash**——用户已选择 nikki；openclash 作为备选记录在案
- ❌ **不做 open-box**——虽有正规 LuCI 包装包，但体积远超 AX6 分区，且该包 Makefile 指向已删除的版本，构建必然失败。详见 5.2.2 节
- ❌ **不编 `redmi_ax6-stock`**——你用不到
- ❌ **不自己移植 NSS 到官方 ImmortalWrt**——那需要维护 140+ 个内核补丁的持续适配，个人几乎无法长期维持
- ❌ **不做多设备支持**——你只有一台
- ❌ **不做镜像加速站**——Release 够用
- ❌ **不把 passwall 精简版作为默认**——nikki 更省空间且只有一个内核，passwall 精简版作为退路

---

## 9. 与已有文档的关系

`红米AX6-ImmortalWrt-操作指南.md`（已移入本项目目录）讲的是**怎么刷机**，本项目解决的是**怎么拿到固件**。两者互补：

- 本项目 → 产出固件文件
- 操作指南 → 教你把这个文件刷进路由器

README 中会与操作指南互相引用。

---

## 10. 前置条件（实施前必须满足）

| 条件 | 当前状态 |
|------|---------|
| GitHub 账号 | ✅ 已登录（`3R1C168`）|
| `repo` 权限 | ✅ 已有 |
| **`workflow` 权限** | ✅ **已授权**（2026-10-05 确认：`gist, read:org, repo, workflow`）|
| 仓库是否已存在 | ❌ 需新建（公开）|

**全部前置条件已满足，可以开工。**

---

## 11. 下一步

1. 你审阅本文档，确认无误
2. 转入实施计划（writing-plans），把上述设计拆成可逐条执行的步骤
3. 按计划实施：建仓库 → 写文件 → 推送 → 手动触发首次构建验证

> 前置条件（含 `workflow` 权限）已全部满足。
