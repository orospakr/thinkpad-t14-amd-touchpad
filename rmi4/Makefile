KDIR ?= /usr/lib/modules/$(shell uname -r)/build
obj-m := rmi_core.o
rmi_core-objs := rmi_bus.o rmi_driver.o rmi_f01.o rmi_2d_sensor.o rmi_f03.o rmi_f11.o rmi_f12.o \
	rmi_f1a.o rmi_f21.o rmi_f30.o rmi_f34.o rmi_f34v7.o rmi_f3a.o rmi_f55.o
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
