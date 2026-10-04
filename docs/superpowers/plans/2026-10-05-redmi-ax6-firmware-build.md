# 红米 AX6 固件自动构建 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 GitHub 上建立一个公开仓库，用 GitHub Actions 每周自动编译红米 AX6 的 ImmortalWrt + NSS 固件，并保留最近 5 个 Release 供下载。

**Architecture:** 仓库只存放"配方"（编译配置 + 工作流），不放源码。每次构建时由 GitHub 云电脑临时克隆 `VIKINGYFY/immortalwrt`（该分支本身即 ImmortalWrt + NSS 合体版），套用配置编出固件，发布为 Release。编译产物通过 `dl/`、`.ccache`、`staging_dir` 三层缓存跨次复用。

**Tech Stack:** GitHub Actions、OpenWrt/ImmortalWrt buildroot、shell、YAML。无常规编程语言代码，因此无单元测试；每个任务的"测试"= 语法校验 / 远程可达性校验 / 本地文件校验。

**Spec:** `docs/superpowers/specs/2026-10-05-redmi-ax6-nss-build-design.md`

## Global Constraints

- 源码仓库：`https://github.com/VIKINGYFY/immortalwrt`，分支 **`main`**（高通专用、带 NSS），内核 **6.18**
- 目标：`qualcommax` / 子目标 `ipq807x` / 设备 **`redmi_ax6`**（**不编** `redmi_ax6-stock`）
- 运行环境：`ubuntu-24.04`，**以非 root 用户构建**（GitHub 默认 `runner` 用户）
- 缓存必须包含三层：`dl/`、`.ccache`、`staging_dir/`；GitHub 每仓库缓存上限 **10 GB**
- ccache 生效前提：`CONFIG_DEVEL=y` 与 `CONFIG_CCACHE=y` **必须同时设置**
- Release 标签格式：`YYYYMMDD`；**只保留最近 5 个**
- 预装包（7 个）：`default-settings-chn`、`luci-i18n-firewall-zh-cn`、`luci-theme-argon`、`luci-app-argon-config`、`luci-i18n-argon-config-zh-cn`、`luci-app-nikki`
- nikki 第三方源：`https://github.com/nikkinikki-org/OpenWrt-nikki.git`
- 工作流单次超时上限：**350 分钟**（GitHub 硬上限 360）
- 本地工作目录：`D:\Documents\Projects\redmi_ax6_firmware`
- GitHub 账号：`3R1C168`（`gh` 已登录，含 `workflow` 权限）

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `.config` | 编译配方：设备选择、预装包、ccache 开关 |
| `.github/workflows/build.yml` | 自动化流程：定时/手动触发、克隆、编译、发布 |
| `scripts/diy.sh` | 编译前的自定义钩子（预留给改主机名等，首版为空操作） |
| `feeds.conf` | 额外软件源（nikki） |
| `README.md` | 使用说明：怎么触发、怎么下载、怎么刷、怎么改配置 |
| `红米AX6-ImmortalWrt-操作指南.md` | 已存在，刷机教程 |
| `docs/superpowers/specs/...` | 已存在，设计文档 |

---

## Task 1: 本地仓库初始化与编译配方

**Files:**
- Create: `D:\Documents\Projects\redmi_ax6_firmware\.config`
- Create: `D:\Documents\Projects\redmi_ax6_firmware\feeds.conf`
- Create: `D:\Documents\Projects\redmi_ax6_firmware\.gitignore`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `.config` 内容约定 → Task 2 的工作流从仓库根目录复制此文件；`feeds.conf` → Task 2 追加到源码树

- [ ] **Step 1: 创建 `.config`**

写入以下内容。符号名均取自 ImmortalWrt 官方发布物 `config.buildinfo`，已核实：

```
#
# Target
#
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_MULTI_PROFILE=y
CONFIG_TARGET_DEVICE_qualcommax_ipq807x_DEVICE_redmi_ax6=y
CONFIG_TARGET_DEVICE_PACKAGES_qualcommax_ipq807x_DEVICE_redmi_ax6=""
CONFIG_TARGET_PER_DEVICE_ROOTFS=y

#
# 构建缓存
#
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_CCACHE_DIR="/home/runner/.ccache"

#
# 基础组件
#
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-package-manager=y

#
# 中文与主题
#
CONFIG_PACKAGE_default-settings-chn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn=y

#
# 代理
#
CONFIG_PACKAGE_luci-app-nikki=y
```

- [ ] **Step 2: 创建 `feeds.conf`**

```
src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git
```

- [ ] **Step 3: 创建 `.gitignore`**

```
dl/
bin/
build_dir/
staging_dir/
tmp/
logs/
```

- [ ] **Step 4: 校验文件已生成且关键行存在**

Run:
```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
grep -c . .config
grep 'CONFIG_TARGET_DEVICE_qualcommax_ipq807x_DEVICE_redmi_ax6=y' .config
grep 'CONFIG_CCACHE=y' .config
grep 'CONFIG_DEVEL=y' .config
cat feeds.conf
```

Expected: `.config` 有内容；四条 `grep` 均命中（输出对应行）；`feeds.conf` 显示 nikki 源。

- [ ] **Step 5: 提交**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
git init
git add .config feeds.conf .gitignore
git -c user.name="redmi-ax6-builder" -c user.email="builder@local" commit -m "feat: 红米AX6 编译配方与 nikki 源"
```

---

## Task 2: GitHub Actions 工作流

**Files:**
- Create: `D:\Documents\Projects\redmi_ax6_firmware\.github\workflows\build.yml`

**Interfaces:**
- Consumes: Task 1 的 `.config`（复制到源码树）、`feeds.conf`（追加到源码树）
- Produces: Release 标签 `YYYYMMDD`，产物文件在 `bin/targets/qualcommax/ipq807x/`

- [ ] **Step 1: 写工作流**

```yaml
name: Build Redmi AX6 Firmware

on:
  schedule:
    # 每周四 UTC 20:00 = 北京时间周五 04:00
    - cron: '0 20 * * 4'
  workflow_dispatch:

env:
  REPO_URL: https://github.com/VIKINGYFY/immortalwrt
  REPO_BRANCH: main
  TZ: Asia/Shanghai

jobs:
  build:
    runs-on: ubuntu-24.04
    timeout-minutes: 350

    steps:
      - name: 检出本仓库
        uses: actions/checkout@v4

      - name: 清理磁盘空间
        run: |
          sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc \
                      /opt/hostedtoolcache/CodeQL /usr/local/share/boost \
                      /usr/local/.ghcup /opt/hostedtoolcache/Java_Temurin-Hotspot_jdk
          sudo docker image prune -a -f || true
          df -h /

      - name: 获取源码版本号
        id: src
        run: |
          echo "sha=$(git ls-remote $REPO_URL refs/heads/$REPO_BRANCH | cut -c1-8)" >> $GITHUB_OUTPUT
          echo "date=$(date +%Y%m%d)" >> $GITHUB_OUTPUT
          echo "datefull=$(date +'%Y-%m-%d %H:%M')" >> $GITHUB_OUTPUT

      - name: 克隆源码
        run: |
          git clone --depth=1 --single-branch -b $REPO_BRANCH $REPO_URL openwrt

      - name: 恢复 dl 缓存
        uses: actions/cache@v4
        with:
          path: openwrt/dl
          key: dl-${{ steps.src.outputs.sha }}
          restore-keys: dl-

      - name: 恢复 ccache
        uses: actions/cache@v4
        with:
          path: /home/runner/.ccache
          key: ccache-${{ steps.src.outputs.sha }}
          restore-keys: ccache-

      - name: 恢复工具链暂存区
        uses: actions/cache@v4
        with:
          path: openwrt/staging_dir
          key: staging-${{ steps.src.outputs.sha }}
          restore-keys: staging-

      - name: 安装编译依赖
        run: |
          sudo apt-get update
          sudo apt-get install -y build-essential clang flex bison g++ gawk \
            gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
            python3-setuptools rsync swig unzip zlib1g-dev file wget time \
            python3-pyelftools libelf-dev ccache

      - name: 应用配置
        run: |
          cd openwrt
          cat ../feeds.conf >> feeds.conf.default
          cp ../.config .config
          ./scripts/feeds update -a
          ./scripts/feeds install -a
          make defconfig

      - name: 执行自定义脚本
        run: |
          cd openwrt
          bash ../scripts/diy.sh || true

      - name: 下载软件包源码
        run: |
          cd openwrt
          make download -j8 || make download -j1 V=s

      - name: 编译固件
        run: |
          cd openwrt
          make -j$(nproc) || make -j1 V=s

      - name: 保存 ccache
        if: always()
        uses: actions/cache/save@v4
        with:
          path: /home/runner/.ccache
          key: ccache-${{ steps.src.outputs.sha }}

      - name: 保存工具链暂存区
        if: always()
        uses: actions/cache/save@v4
        with:
          path: openwrt/staging_dir
          key: staging-${{ steps.src.outputs.sha }}

      - name: 整理产物
        run: |
          cd openwrt
          OUT=bin/targets/qualcommax/ipq807x
          ls -lh $OUT/
          mkdir -p ../firmware
          find $OUT -maxdepth 1 -name '*redmi_ax6*' \
            \( -name '*.bin' -o -name '*.ubi' -o -name '*.itb' \) \
            -exec cp {} ../firmware/ \;
          cp $OUT/sha256sums ../firmware/ 2>/dev/null || true
          cd ../firmware
          sha256sum * > SHA256SUMS.txt 2>/dev/null || true
          ls -lh .
          ls > ../filelist.txt

      - name: 生成 Release 说明
        run: |
          cat > release_body.txt << 'EOF'
          ## 红米 AX6 固件（ImmortalWrt + NSS）

          | 项目 | 值 |
          |------|-----|
          | 源码 | VIKINGYFY/immortalwrt @ `${{ env.REPO_BRANCH }}` |
          | 提交 | `${{ steps.src.outputs.sha }}` |
          | 内核 | 6.18 |
          | 构建时间 | ${{ steps.src.outputs.datefull }} |
          | 触发方式 | ${{ github.event_name }} |

          ### 预装内容
          - NSS 硬件加速驱动（kernel 内置）
          - 中文界面 + 中国时区/NTP/国内镜像源（default-settings-chn）
          - Argon 主题
          - nikki（mihomo 内核）透明代理

          ### 文件说明
          - `*-initramfs-factory.ubi` — 刷机中转固件
          - `*-squashfs-sysupgrade.bin` — 最终固件
          - `SHA256SUMS.txt` — 校验码

          ### 刷机
          参见仓库内《红米AX6-ImmortalWrt-操作指南.md》

          ### 注意
          刷好后建议关闭无线 offload（详见指南）。
          EOF
          echo "body written"

      - name: 发布 Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.src.outputs.date }}
          name: "AX6 固件 ${{ steps.src.outputs.date }}"
          body_path: release_body.txt
          files: firmware/*

      - name: 清理旧 Release（只留最近 5 个）
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # 按发布时间倒序列出全部 release，跳过前 5 个，删除其余
          gh release list --limit 100 --json tagName,publishedAt \
            --jq 'sort_by(.publishedAt) | reverse | .[5:] | .[].tagName' \
          | while read -r tag; do
              [ -z "$tag" ] && continue
              echo "删除旧版本: $tag"
              gh release delete "$tag" --yes --cleanup-tag || true
            done
```

- [ ] **Step 2: 校验 YAML 语法**

Run:
```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
python -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/build.yml',encoding='utf-8')); print('YAML OK'); print('jobs:', list(d['jobs'].keys())); print('steps:', len(d['jobs']['build']['steps']))"
```

Expected: 输出 `YAML OK`，`jobs: ['build']`，`steps:` 为 14 左右的数字。若报 YAML 解析错误，说明缩进或引号有误——注意 `run: |` 块内的 heredoc 必须保持缩进一致。

- [ ] **Step 3: 校验关键步骤齐全**

Run:
```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
for k in "schedule" "workflow_dispatch" "staging_dir" "ccache" "make -j" "action-gh-release" "release list --limit 100"; do
  grep -q "$k" .github/workflows/build.yml && echo "  [有] $k" || echo "  [缺] $k"
done
```

Expected: 7 项全部为 `[有]`。

- [ ] **Step 4: 提交**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
git add .github/workflows/build.yml
git -c user.name="redmi-ax6-builder" -c user.email="builder@local" commit -m "feat: 每周自动构建工作流"
```

---

## Task 3: 自定义钩子与 README

**Files:**
- Create: `D:\Documents\Projects\redmi_ax6_firmware\scripts\diy.sh`
- Create: `D:\Documents\Projects\redmi_ax6_firmware\README.md`

**Interfaces:**
- Consumes: 无
- Produces: `scripts/diy.sh` 被 Task 2 工作流以 `bash ../scripts/diy.sh` 调用（工作目录为源码树根）

- [ ] **Step 1: 写 `scripts/diy.sh`**

```bash
#!/bin/bash
# 编译前的自定义钩子。工作目录 = 源码树根目录（openwrt/）。
# 出任何错都不应中断构建，因此整体容错。
set +e

echo "[diy] 当前目录: $(pwd)"

# 示例：改默认主机名（按需取消注释）
# sed -i "s/set system.@system\[0\].hostname='ImmortalWrt'/set system.@system[0].hostname='Redmi-AX6'/" \
#   package/base-files/files/bin/config_generate 2>/dev/null

# 示例：把 LAN 默认网段改成 192.168.2.1
# sed -i "s/192.168.1.1/192.168.2.1/g" package/base-files/files/bin/config_generate 2>/dev/null

echo "[diy] 无自定义改动，跳过"
exit 0
```

- [ ] **Step 2: 写 `README.md`**

内容需包含以下小节（用中文，面向非专业读者）：

```markdown
# 红米 AX6 固件自动构建

用 GitHub Actions 云端自动编译红米 AX6 的 ImmortalWrt 固件（带 NSS 硬件加速）。
编译在 GitHub 的服务器上完成，本机无需安装任何环境。

## 怎么触发构建

两种方式：

1. **自动**：每周五凌晨 4 点（北京时间）自动跑一次
2. **手动**：进入本仓库 `Actions` 页面 → 左侧选 `Build Redmi AX6 Firmware` → 右侧 `Run workflow` → 绿色按钮确认

一次构建约需 1~4 小时（首次最久，之后有缓存会快）。

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

AX6 的 rootfs 分区只有 82 MB。当前配置的固件约 35 MB，留有充足可写空间。
**不要把 passwall 编进来** —— 它全量依赖 107 MB，装不下。

## 排错

- **构建失败且日志提到 nikki**：nikki 是第三方源，可能与快照版本不兼容。
  临时解决办法：删掉 `.config` 里 `CONFIG_PACKAGE_luci-app-nikki=y` 这一行，重新构建。
- **构建超时**：首次编译最慢。若超时，多半是缓存没生效，重跑一次通常会快很多。
- **磁盘不足**：工作流已包含清理磁盘步骤；若仍不足，需要精简配置。

## 来源与致谢

- 源码：[VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)（ImmortalWrt + NSS）
- NSS 驱动源头：高通 QSDK（经 qosmio、LiBwrt 等社区移植）
- 代理插件：[nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)
```

- [ ] **Step 3: 校验文件**

Run:
```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
bash -n scripts/diy.sh && echo "diy.sh 语法 OK"
grep -c . README.md
grep -q 'Release' README.md && echo "README 含下载说明"
```

Expected: 输出 `diy.sh 语法 OK`；README 行数大于 30；输出 `README 含下载说明`。

- [ ] **Step 4: 提交**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
git add scripts/diy.sh README.md
git -c user.name="redmi-ax6-builder" -c user.email="builder@local" commit -m "docs: README 与自定义钩子"
```

---

## Task 4: 创建 GitHub 仓库并推送

**Files:** 无本地文件改动

**Interfaces:**
- Consumes: Task 1-3 产生的全部文件
- Produces: 远程仓库 `<账号>/redmi_ax6_firmware`，供 Task 5 触发构建

- [ ] **Step 1: 确认账号与权限**

Run:
```bash
gh auth status
```

Expected: 显示 `Logged in to github.com account 3R1C168`，权限含 `repo` 与 `workflow`。若缺 `workflow`，先运行 `gh auth refresh -s workflow,repo`。

- [ ] **Step 2: 确认仓库尚不存在**

Run:
```bash
gh repo view 3R1C168/redmi_ax6_firmware 2>&1 | head -3
```

Expected: 报错 `Could not resolve to a Repository` —— 说明可以新建。若已存在，跳到 Step 4 用 `git push` 更新。

- [ ] **Step 3: 创建公开仓库**

Run:
```bash
gh repo create redmi_ax6_firmware --public \
  --description "红米 AX6 ImmortalWrt+NSS 固件自动构建"
```

Expected: 输出类似 `✓ Created repository 3R1C168/redmi_ax6_firmware on GitHub`。

- [ ] **Step 4: 推送全部文件**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/3R1C168/redmi_ax6_firmware.git
git add -A
git -c user.name="redmi-ax6-builder" -c user.email="builder@local" commit -m "chore: 项目文档与设计说明" || echo "无新改动"
git push -u origin main
```

- [ ] **Step 5: 验证推送成功且工作流被识别**

Run:
```bash
gh api repos/3R1C168/redmi_ax6_firmware/contents/.github/workflows --jq '.[].name'
gh workflow list --repo 3R1C168/redmi_ax6_firmware
```

Expected: 第一条输出 `build.yml`；第二条输出工作流名为 `Build Redmi AX6 Firmware` 且状态 `active`。

**这是关键验证点**：若 `.github/workflows` 返回 404 或空，说明 `workflow` 权限不足，文件未被接受——需重新授权后强推。

---

## Task 5: 触发首次构建并验证产出

**Files:** 无本地文件改动

**Interfaces:**
- Consumes: Task 4 建立的远程仓库
- Produces: 一个 Release，含固件文件

- [ ] **Step 1: 手动触发构建**

```bash
gh workflow run "Build Redmi AX6 Firmware" --repo 3R1C168/redmi_ax6_firmware
```

Expected: 命令无报错返回。

- [ ] **Step 2: 确认任务已启动**

```bash
sleep 20
gh run list --repo 3R1C168/redmi_ax6_firmware --limit 3
```

Expected: 出现一条状态为 `in_progress` 或 `queued` 的记录。

- [ ] **Step 3: 观察构建进度（首次约 1~4 小时）**

```bash
gh run watch --repo 3R1C168/redmi_ax6_firmware
```

> 构建期间可中断此命令（Ctrl+C），构建在云端继续，与本机无关。

**中途检查失败原因时用：**
```bash
gh run view --repo 3R1C168/redmi_ax6_firmware --log-failed | tail -60
```

- [ ] **Step 4: 构建成功后验证 Release 与产物**

```bash
gh release list --repo 3R1C168/redmi_ax6_firmware
gh release view --repo 3R1C168/redmi_ax6_firmware --json assets \
  --jq '.assets[] | "\(.name)  \(.size)"'
```

Expected: 出现一个日期标签的 Release；资产列表包含：
- 文件名同时含 `qualcommax-ipq807x` 与 `redmi_ax6` 的 `*-initramfs-factory.ubi`
- 同前缀的 `*-squashfs-sysupgrade.bin`
- `SHA256SUMS.txt`

- [ ] **Step 5: 检查固件体积是否合理**

```bash
gh release view --repo 3R1C168/redmi_ax6_firmware --json assets \
  --jq '.assets[] | select(.name|test("sysupgrade")) | "\(.name): \(.size/1048576|floor) MB"'
```

Expected: 约 **30~40 MB**。判读规则：
- 小于 20 MB → 可能没编进 nikki，检查 `.config` 是否生效
- **大于 50 MB → 危险**，可能超出 82 MB 分区，需检查是否误装了大包
- 约 35 MB → 正常

> GitHub 上报的是压缩后的包体，比解压后小，属正常。

- [ ] **Step 6: 记录本次构建的源码提交号**

```bash
gh release view --repo 3R1C168/redmi_ax6_firmware --json body --jq .body | grep -i '提交\|commit'
```

Expected: 输出中能看到 8 位十六进制提交号。记录下来——出问题时可用它回退到旧版本重新构建。

---

## Task 6: 失败回退（仅当 Task 5 因 nikki 失败时执行）

**Files:**
- Modify: `D:\Documents\Projects\redmi_ax6_firmware\.config`

**Interfaces:**
- Consumes: Task 5 的失败日志
- Produces: 不含 nikki 的可构建配置

- [ ] **Step 1: 确认失败确实与 nikki 相关**

```bash
gh run view --repo 3R1C168/redmi_ax6_firmware --log-failed | grep -iE 'nikki|mihomo|golang' | tail -20
```

Expected: 出现 nikki / mihomo / golang 相关错误。**若错误与这三者无关**（例如内核补丁、显存、磁盘），说明问题不在 nikki，不要执行本任务，而应看日志具体定位。

- [ ] **Step 2: 从配置中移除 nikki**

在 `.config` 里，把这一行：
```
CONFIG_PACKAGE_luci-app-nikki=y
```
改为：
```
# CONFIG_PACKAGE_luci-app-nikki is not set
```

同时在 `feeds.conf` 里把 nikki 源注释掉：
```
#src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git
```

- [ ] **Step 3: 校验改动**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
grep 'nikki' .config feeds.conf
```

Expected: 两处均显示为已注释（行首有 `#`），无未注释的 nikki 启用行。

- [ ] **Step 4: 提交并推送**

```bash
cd "D:/Documents/Projects/redmi_ax6_firmware"
git add .config feeds.conf
git -c user.name="redmi-ax6-builder" -c user.email="builder@local" commit -m "fix: 移除 nikki（第三方源构建失败）"
git push
```

- [ ] **Step 5: 重新触发构建**

```bash
gh workflow run "Build Redmi AX6 Firmware" --repo 3R1C168/redmi_ax6_firmware
sleep 20
gh run list --repo 3R1C168/redmi_ax6_firmware --limit 2
```

Expected: 新任务启动。

> 说明：此时固件不含代理插件。刷机后若要 nikki，可在路由器上运行它官方的 `feed.sh` 脚本安装（需先确认存储空间充足）。

---

## 后续（本次不做）

- 刷机后关闭无线 offload（`/etc/modules.d/ath11k` 设 `nss_offload=0`）
- 若想要 passwall 的某些功能，考虑加装 USB 存储后装到外置盘
- 若 VIKINGYFY 上游停更，切换到官方 `immortalwrt/immortalwrt` 或 `qosmio/openwrt-ipq`
