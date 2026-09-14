# psmouse test rig (post-suspend jitter, RESUME-PLAN.md)

`src/` is pristine `drivers/input/mouse` from v7.1.9. The build trees are not
tracked; regenerate one with

    cp -r src X && cp Makefile X/ && (cd X && patch -p1 < ../PATCH.diff && make)

- `stock/`    — no patch (baseline)
- `patched/`  — `psmouse-cleanup-smbus.diff` (psmouse_cleanup skips F6/F4 for SMBus companions)
- `delay/`    — `psmouse-reset-delay-param.diff` (`synaptics_smbus_reset_delay=` ms param)

Loaders `load*.sh` re-attach the pad (out-of-tree psmouse, rmi_smbus); `motw*.sh`
are touch-triggered SYN_REPORT interval captures; `cycle.sh` drives suspend A/B
runs; `ps2cmd.py` pokes the i8042 aux port via /dev/port; logs in `ab/`.
