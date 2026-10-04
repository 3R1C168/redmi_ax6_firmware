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
