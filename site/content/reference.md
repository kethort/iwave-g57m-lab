+++
title = "Reference"
description = "Fast checks and conventions used throughout the lab."
+++

## Container paths

| Container path | Purpose |
| --- | --- |
| `/work` | User-supplied artifacts and configurations |
| `/work/output` | Generated BIF, PDI, scripts, and FIT files |
| `/srv/tftp` | Host TFTP root |
| `/opt/qt-boot-gui/configs` | Read-only bundled configuration templates |

## JTAG checks

```bash
./diagnose-jtag.sh
ss -ltnp 'sport = :3121'
tail -f ~/.qt-boot-gui-container/hw_server.log
```

## Publication hygiene

Remove serial numbers, device DNA, credentials, private repository URLs, licensed vendor source, and proprietary hardware deliverables before publishing logs or artifacts.
