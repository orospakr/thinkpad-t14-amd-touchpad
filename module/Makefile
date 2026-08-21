KDIR ?= /usr/lib/modules/$(shell uname -r)/build

obj-m := i2c-piix4.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
