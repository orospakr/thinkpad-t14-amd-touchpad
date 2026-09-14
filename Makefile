# Out-of-tree build of the three patched modules. With DKMS this file is
# invoked as `make -C <kernel headers> M=<this dir> modules`; standalone,
# `make` does the same against the running kernel.
ifneq ($(KERNELRELEASE),)
obj-m += drivers/i2c/busses/
obj-m += drivers/input/rmi4/
obj-m += drivers/input/mouse/
else
KDIR ?= /usr/lib/modules/$(shell uname -r)/build
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
endif
