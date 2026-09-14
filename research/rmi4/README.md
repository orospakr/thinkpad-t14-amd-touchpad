# rmi4 test rig (post-suspend jitter, RESUME-PLAN.md)

`src/` is pristine `drivers/input/rmi4` from v7.1.9. Build trees are not
tracked; regenerate:

    cp -r src patched && cp Makefile patched/ && (cd patched && patch -p1 < ../rmi-experiment.diff && make)
    mkdir smbus && cp src/rmi_smbus.c src/rmi_bus.h src/rmi_driver.h smbus/ && cp Makefile.smbus smbus/Makefile \
      && (cd smbus && patch -p0 < ../rmi_smbus-resume-reactivate.diff && make)

- `rmi-experiment.diff` — rmi_core: `resume_reconfig=` param; sysfs `regdump`,
  `xport_reset`, `reconfig`, `hwreset` on `/sys/bus/i2c/devices/11-002c/rmi4-N/`
  (`rmi-resume-reconfig-regdump.diff` is the earlier subset)
- `rmi_smbus-resume-reactivate.diff` — rmi_smbus: `resume_reactivate=`,
  `resume_reactivate_delay_ms=`

`load-rmi.sh` / `load-smbus.sh` swap the modules in; `probe3..9.sh`, `t3.sh` are
the experiments in RESUME-PLAN.md §Results, with their logs alongside.
