KDIR ?= /usr/lib/modules/$(shell uname -r)/build
obj-m := psmouse.o
psmouse-objs := psmouse-base.o synaptics.o focaltech.o alps.o byd.o elantech.o \
	logips2pp.o lifebook.o sentelic.o trackpoint.o touchkit_ps2.o \
	cypress_ps2.o vmmouse.o psmouse-smbus.o
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
