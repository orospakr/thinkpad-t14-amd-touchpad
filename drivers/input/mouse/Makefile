# psmouse only, in the in-tree form so the object list follows the kernel's
# own CONFIG_MOUSE_PS2_* selection.
obj-m := psmouse.o

psmouse-objs := psmouse-base.o synaptics.o focaltech.o

psmouse-$(CONFIG_MOUSE_PS2_ALPS)	+= alps.o
psmouse-$(CONFIG_MOUSE_PS2_BYD)		+= byd.o
psmouse-$(CONFIG_MOUSE_PS2_ELANTECH)	+= elantech.o
psmouse-$(CONFIG_MOUSE_PS2_LOGIPS2PP)	+= logips2pp.o
psmouse-$(CONFIG_MOUSE_PS2_LIFEBOOK)	+= lifebook.o
psmouse-$(CONFIG_MOUSE_PS2_SENTELIC)	+= sentelic.o
psmouse-$(CONFIG_MOUSE_PS2_TRACKPOINT)	+= trackpoint.o
psmouse-$(CONFIG_MOUSE_PS2_TOUCHKIT)	+= touchkit_ps2.o
psmouse-$(CONFIG_MOUSE_PS2_CYPRESS)	+= cypress_ps2.o
psmouse-$(CONFIG_MOUSE_PS2_VMMOUSE)	+= vmmouse.o

psmouse-$(CONFIG_MOUSE_PS2_SMBUS)	+= psmouse-smbus.o
