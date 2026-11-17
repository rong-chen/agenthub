---
name: system_info
description: 获取当前主机系统与环境状态
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - uname
---

# System Info Skill

当用户需要查看本机操作系统、内核架构或硬件环境信息时，可通过本地终端执行 `uname -a` 获取详细信息。
