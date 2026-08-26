// SPDX-License-Identifier: GPL-2.0-or-later
/*
    Copyright (c) 1998 - 2002 Frodo Looijaard <frodol@dds.nl> and
    Philip Edelbrock <phil@netroedge.com>

*/

/*
   Supports:
	Intel PIIX4, 440MX
	Serverworks OSB4, CSB5, CSB6, HT-1000, HT-1100
	ATI IXP200, IXP300, IXP400, SB600, SB700/SP5100, SB800
	AMD Hudson-2, ML, CZ
	Hygon CZ
	SMSC Victory66

   Note: we assume there can only be one device, with one or more
   SMBus interfaces.
   The device can register multiple i2c_adapters (up to PIIX4_MAX_ADAPTERS).
   For devices supporting multiple ports the i2c_adapter should provide
   an i2c_algorithm to access them.
*/

#include <linux/bitops.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/kernel.h>
#include <linux/delay.h>
#include <linux/stddef.h>
#include <linux/ioport.h>
#include <linux/i2c.h>
#include <linux/i2c-smbus.h>
#include <linux/slab.h>
#include <linux/dmi.h>
#include <linux/acpi.h>
#include <linux/io.h>
#include <linux/platform_data/x86/amd-fch.h>

#include "i2c-piix4.h"

/* count for request_region */
#define SMBIOSIZE	9

/* PCI Address Constants */
#define SMBBA		0x090
#define SMBHSTCFG	0x0D2
#define SMBSLVC		0x0D3
#define SMBSHDW1	0x0D4
#define SMBSHDW2	0x0D5
#define SMBREV		0x0D6

/* Other settings */
#define MAX_TIMEOUT	500
#define  ENABLE_INT9	0

/* PIIX4 constants */
#define PIIX4_QUICK		0x00
#define PIIX4_BYTE		0x04
#define PIIX4_BYTE_DATA		0x08
#define PIIX4_WORD_DATA		0x0C

/* Multi-port constants */
#define PIIX4_MAX_ADAPTERS	4
#define HUDSON2_MAIN_PORTS	2 /* HUDSON2, KERNCZ reserves ports 3, 4 */

/* SB800 constants */
#define SB800_PIIX4_SMB_IDX		0xcd6
#define SB800_PIIX4_SMB_MAP_SIZE	2

#define KERNCZ_IMC_IDX			0x3e
#define KERNCZ_IMC_DATA			0x3f

/*
 * SB800 port is selected by bits 2:1 of the smb_en register (0x2c)
 * or the smb_sel register (0x2e), depending on bit 0 of register 0x2f.
 * Hudson-2/Bolton port is always selected by bits 2:1 of register 0x2f.
 */
#define SB800_PIIX4_PORT_IDX		0x2c
#define SB800_PIIX4_PORT_IDX_ALT	0x2e
#define SB800_PIIX4_PORT_IDX_SEL	0x2f
#define SB800_PIIX4_PORT_IDX_MASK	0x06
#define SB800_PIIX4_PORT_IDX_SHIFT	1

/* SmBus0Sel is at bit 20:19 of PMx00 DecodeEn */
#define SB800_PIIX4_PORT_IDX_KERNCZ		(FCH_PM_DECODEEN + 0x02)
#define SB800_PIIX4_PORT_IDX_MASK_KERNCZ	(FCH_PM_DECODEEN_SMBUS0SEL >> 16)
#define SB800_PIIX4_PORT_IDX_SHIFT_KERNCZ	3

#define SB800_PIIX4_FCH_PM_SIZE			8
#define SB800_ASF_ACPI_PATH			"\\_SB.ASFC"

/* insmod parameters */

/* If force is set to anything different from 0, we forcibly enable the
   PIIX4. DANGEROUS! */
static int force;
module_param (force, int, 0);
MODULE_PARM_DESC(force, "Forcibly enable the PIIX4. DANGEROUS!");

/* If force_addr is set to anything different from 0, we forcibly enable
   the PIIX4 at the given address. VERY DANGEROUS! */
static int force_addr;
module_param_hw(force_addr, int, ioport, 0);
MODULE_PARM_DESC(force_addr,
		 "Forcibly enable the PIIX4 at the given address. "
		 "EXTREMELY DANGEROUS!");

static bool asf_host_notify = true;
module_param(asf_host_notify, bool, 0);
MODULE_PARM_DESC(asf_host_notify,
		 "Enable SMBus Host Notify via the ASF controller when the firmware describes one (default 1)");

static int asf_irq = -1;
module_param(asf_irq, int, 0);
MODULE_PARM_DESC(asf_irq, "Override the ASF Host Notify IRQ (-1 = use ACPI)");

/*
 * ASF (Alert Standard Format) SMBus slave / Host Notify support
 *
 * On AMD FCH chipsets the auxiliary SMBus controller is the ASF
 * controller, which can also receive SMBus messages as a slave --
 * including Host Notify, which psmouse-smbus/rmi_smbus require for
 * Synaptics InterTouch touchpads.  Some firmware (e.g. Lenovo ThinkPad
 * T14 Gen 2a AMD) describes this controller as an ACPI device using
 * Microsoft's virtual SMBus HID "SMB0001" carrying the IO range and the
 * IRQ; the Windows Synaptics driver (Smb_driver_AMDASF.sys) binds that
 * device and drives the touchpad this way.
 *
 * Register layout and programming sequences follow i2c-amd-asf-plat.c,
 * which drives the same IP on platforms whose firmware declares an
 * AMDI001A node instead.
 */

/* ASF register bits */
#define ASF_SLV_LISTN	0
#define ASF_SLV_INTR	1
#define ASF_SLV_RST	4
#define ASF_PEC_SP	5
#define ASF_DATA_EN	7
#define ASF_MSTR_EN	16
#define ASF_CLK_EN	17

/* ASF address offsets */
#define ASFINDEX	(0x07 + piix4_smba)
#define ASFLISADDR	(0x09 + piix4_smba)
#define ASFSTA		(0x0A + piix4_smba)
#define ASFSLVSTA	(0x0D + piix4_smba)
#define ASFDATARWPTR	(0x11 + piix4_smba)
#define ASFSETDATARDPTR	(0x12 + piix4_smba)
#define ASFDATABNKSEL	(0x13 + piix4_smba)
#define ASFSLVEN	(0x15 + piix4_smba)

#define ASF_BLOCK_MAX_BYTES	72
#define ASF_ERROR_STATUS	GENMASK(3, 1)
#define ASF_HOST_ADDR		0x08	/* SMBus Host address, Host Notify target */
#define ASF_IOSIZE		0x20	/* IO window declared by SMB0001 _CRS */

static unsigned short piix4_asf_smba;	/* IO base from SMB0001 _CRS, 0 = none */
static unsigned int piix4_asf_iolen;	/* IO window size from SMB0001 _CRS */
static int piix4_asf_irqnum = -1;
static bool piix4_asf_active;
static char piix4_asf_irq_cookie;	/* dev_id for the shared IRQ */
static struct device *piix4_asf_dev;	/* PCI device, for region requests */
static u32 piix4_asf_boot_ctl;		/* boot state of MSTR_EN/CLK_EN */
static atomic_t piix4_asf_pending;	/* notify acked but bank not yet read */
static struct sb800_mmio_cfg piix4_asf_mmio_cfg;
/* Serializes master transfers against slave data-bank processing */
static DEFINE_MUTEX(piix4_asf_mutex);

static void piix4_asf_process_bank(void);

static int srvrworks_csb5_delay;
static struct pci_driver piix4_driver;

static const struct dmi_system_id piix4_dmi_blacklist[] = {
	{
		.ident = "Sapphire AM2RD790",
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "SAPPHIRE Inc."),
			DMI_MATCH(DMI_BOARD_NAME, "PC-AM2RD790"),
		},
	},
	{
		.ident = "DFI Lanparty UT 790FX",
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "DFI Inc."),
			DMI_MATCH(DMI_BOARD_NAME, "LP UT 790FX"),
		},
	},
	{ }
};

/* The IBM entry is in a separate table because we only check it
   on Intel-based systems */
static const struct dmi_system_id piix4_dmi_ibm[] = {
	{
		.ident = "IBM",
		.matches = { DMI_MATCH(DMI_SYS_VENDOR, "IBM"), },
	},
	{ }
};

/*
 * SB800 globals
 */
static u8 piix4_port_sel_sb800;
static u8 piix4_port_mask_sb800;
static u8 piix4_port_shift_sb800;
static const char *piix4_main_port_names_sb800[PIIX4_MAX_ADAPTERS] = {
	" port 0", " port 2", " port 3", " port 4"
};
static const char *piix4_aux_port_name_sb800 = " port 1";

struct i2c_piix4_adapdata {
	unsigned short smba;

	/* SB800 */
	bool sb800_main;
	bool notify_imc;
	u8 port;		/* Port number, shifted */
	struct sb800_mmio_cfg mmio_cfg;
};

int piix4_sb800_region_request(struct device *dev, struct sb800_mmio_cfg *mmio_cfg)
{
	if (mmio_cfg->use_mmio) {
		void __iomem *addr;

		if (!request_mem_region_muxed(FCH_PM_BASE,
					      SB800_PIIX4_FCH_PM_SIZE,
					      "sb800_piix4_smb")) {
			dev_err(dev,
				"SMBus base address memory region 0x%x already in use.\n",
				FCH_PM_BASE);
			return -EBUSY;
		}

		addr = ioremap(FCH_PM_BASE,
			       SB800_PIIX4_FCH_PM_SIZE);
		if (!addr) {
			release_mem_region(FCH_PM_BASE,
					   SB800_PIIX4_FCH_PM_SIZE);
			dev_err(dev, "SMBus base address mapping failed.\n");
			return -ENOMEM;
		}

		mmio_cfg->addr = addr;

		return 0;
	}

	if (!request_muxed_region(SB800_PIIX4_SMB_IDX, SB800_PIIX4_SMB_MAP_SIZE,
				  "sb800_piix4_smb")) {
		dev_err(dev,
			"SMBus base address index region 0x%x already in use.\n",
			SB800_PIIX4_SMB_IDX);
		return -EBUSY;
	}

	return 0;
}
EXPORT_SYMBOL_NS_GPL(piix4_sb800_region_request, "PIIX4_SMBUS");

void piix4_sb800_region_release(struct device *dev, struct sb800_mmio_cfg *mmio_cfg)
{
	if (mmio_cfg->use_mmio) {
		iounmap(mmio_cfg->addr);
		release_mem_region(FCH_PM_BASE,
				   SB800_PIIX4_FCH_PM_SIZE);
		return;
	}

	release_region(SB800_PIIX4_SMB_IDX, SB800_PIIX4_SMB_MAP_SIZE);
}
EXPORT_SYMBOL_NS_GPL(piix4_sb800_region_release, "PIIX4_SMBUS");

static bool piix4_sb800_use_mmio(struct pci_dev *PIIX4_dev)
{
	/*
	 * cd6h/cd7h port I/O accesses can be disabled on AMD processors
	 * w/ SMBus PCI revision ID 0x51 or greater. MMIO is supported on
	 * the same processors and is the recommended access method.
	 */
	return (PIIX4_dev->vendor == PCI_VENDOR_ID_AMD &&
		PIIX4_dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS &&
		PIIX4_dev->revision >= 0x51);
}

static int piix4_setup(struct pci_dev *PIIX4_dev,
		       const struct pci_device_id *id)
{
	unsigned char temp;
	unsigned short piix4_smba;

	if ((PIIX4_dev->vendor == PCI_VENDOR_ID_SERVERWORKS) &&
	    (PIIX4_dev->device == PCI_DEVICE_ID_SERVERWORKS_CSB5))
		srvrworks_csb5_delay = 1;

	/* On some motherboards, it was reported that accessing the SMBus
	   caused severe hardware problems */
	if (dmi_check_system(piix4_dmi_blacklist)) {
		dev_err(&PIIX4_dev->dev,
			"Accessing the SMBus on this system is unsafe!\n");
		return -EPERM;
	}

	/* Don't access SMBus on IBM systems which get corrupted eeproms */
	if (dmi_check_system(piix4_dmi_ibm) &&
			PIIX4_dev->vendor == PCI_VENDOR_ID_INTEL) {
		dev_err(&PIIX4_dev->dev, "IBM system detected; this module "
			"may corrupt your serial eeprom! Refusing to load "
			"module!\n");
		return -EPERM;
	}

	/* Determine the address of the SMBus areas */
	if (force_addr) {
		piix4_smba = force_addr & 0xfff0;
		force = 0;
	} else {
		pci_read_config_word(PIIX4_dev, SMBBA, &piix4_smba);
		piix4_smba &= 0xfff0;
		if(piix4_smba == 0) {
			dev_err(&PIIX4_dev->dev, "SMBus base address "
				"uninitialized - upgrade BIOS or use "
				"force_addr=0xaddr\n");
			return -ENODEV;
		}
	}

	if (acpi_check_region(piix4_smba, SMBIOSIZE, piix4_driver.name))
		return -ENODEV;

	if (!request_region(piix4_smba, SMBIOSIZE, piix4_driver.name)) {
		dev_err(&PIIX4_dev->dev, "SMBus region 0x%x already in use!\n",
			piix4_smba);
		return -EBUSY;
	}

	pci_read_config_byte(PIIX4_dev, SMBHSTCFG, &temp);

	/* If force_addr is set, we program the new address here. Just to make
	   sure, we disable the PIIX4 first. */
	if (force_addr) {
		pci_write_config_byte(PIIX4_dev, SMBHSTCFG, temp & 0xfe);
		pci_write_config_word(PIIX4_dev, SMBBA, piix4_smba);
		pci_write_config_byte(PIIX4_dev, SMBHSTCFG, temp | 0x01);
		dev_info(&PIIX4_dev->dev, "WARNING: SMBus interface set to "
			"new address %04x!\n", piix4_smba);
	} else if ((temp & 1) == 0) {
		if (force) {
			/* This should never need to be done, but has been
			 * noted that many Dell machines have the SMBus
			 * interface on the PIIX4 disabled!? NOTE: This assumes
			 * I/O space and other allocations WERE done by the
			 * Bios!  Don't complain if your hardware does weird
			 * things after enabling this. :') Check for Bios
			 * updates before resorting to this.
			 */
			pci_write_config_byte(PIIX4_dev, SMBHSTCFG,
					      temp | 1);
			dev_notice(&PIIX4_dev->dev,
				   "WARNING: SMBus interface has been FORCEFULLY ENABLED!\n");
		} else {
			dev_err(&PIIX4_dev->dev,
				"SMBus Host Controller not enabled!\n");
			release_region(piix4_smba, SMBIOSIZE);
			return -ENODEV;
		}
	}

	if (((temp & 0x0E) == 8) || ((temp & 0x0E) == 2))
		dev_dbg(&PIIX4_dev->dev, "Using IRQ for SMBus\n");
	else if ((temp & 0x0E) == 0)
		dev_dbg(&PIIX4_dev->dev, "Using SMI# for SMBus\n");
	else
		dev_err(&PIIX4_dev->dev, "Illegal Interrupt configuration "
			"(or code out of date)!\n");

	pci_read_config_byte(PIIX4_dev, SMBREV, &temp);
	dev_info(&PIIX4_dev->dev,
		 "SMBus Host Controller at 0x%x, revision %d\n",
		 piix4_smba, temp);

	return piix4_smba;
}

static int piix4_setup_sb800_smba(struct pci_dev *PIIX4_dev,
				  u8 smb_en,
				  u8 aux,
				  u8 *smb_en_status,
				  unsigned short *piix4_smba)
{
	struct sb800_mmio_cfg mmio_cfg;
	u8 smba_en_lo;
	u8 smba_en_hi;
	int retval;

	mmio_cfg.use_mmio = piix4_sb800_use_mmio(PIIX4_dev);
	retval = piix4_sb800_region_request(&PIIX4_dev->dev, &mmio_cfg);
	if (retval)
		return retval;

	if (mmio_cfg.use_mmio) {
		smba_en_lo = ioread8(mmio_cfg.addr);
		smba_en_hi = ioread8(mmio_cfg.addr + 1);
	} else {
		outb_p(smb_en, SB800_PIIX4_SMB_IDX);
		smba_en_lo = inb_p(SB800_PIIX4_SMB_IDX + 1);
		outb_p(smb_en + 1, SB800_PIIX4_SMB_IDX);
		smba_en_hi = inb_p(SB800_PIIX4_SMB_IDX + 1);
	}

	piix4_sb800_region_release(&PIIX4_dev->dev, &mmio_cfg);

	if (!smb_en) {
		*smb_en_status = smba_en_lo & 0x10;
		*piix4_smba = smba_en_hi << 8;
		if (aux)
			*piix4_smba |= 0x20;
	} else {
		*smb_en_status = smba_en_lo & 0x01;
		*piix4_smba = ((smba_en_hi << 8) | smba_en_lo) & 0xffe0;
	}

	if (!*smb_en_status) {
		dev_err(&PIIX4_dev->dev,
			"SMBus Host Controller not enabled!\n");
		return -ENODEV;
	}

	return 0;
}

static int piix4_setup_sb800(struct pci_dev *PIIX4_dev,
			     const struct pci_device_id *id, u8 aux)
{
	unsigned short piix4_smba;
	u8 smb_en, smb_en_status, port_sel;
	u8 i2ccfg, i2ccfg_offset = 0x10;
	struct sb800_mmio_cfg mmio_cfg;
	int retval;

	/* SB800 and later SMBus does not support forcing address */
	if (force || force_addr) {
		dev_err(&PIIX4_dev->dev, "SMBus does not support "
			"forcing address!\n");
		return -EINVAL;
	}

	/* Determine the address of the SMBus areas */
	if ((PIIX4_dev->vendor == PCI_VENDOR_ID_AMD &&
	     PIIX4_dev->device == PCI_DEVICE_ID_AMD_HUDSON2_SMBUS &&
	     PIIX4_dev->revision >= 0x41) ||
	    (PIIX4_dev->vendor == PCI_VENDOR_ID_AMD &&
	     PIIX4_dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS &&
	     PIIX4_dev->revision >= 0x49) ||
	    (PIIX4_dev->vendor == PCI_VENDOR_ID_HYGON &&
	     PIIX4_dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS))
		smb_en = 0x00;
	else
		smb_en = (aux) ? 0x28 : 0x2c;

	retval = piix4_setup_sb800_smba(PIIX4_dev, smb_en, aux, &smb_en_status,
					&piix4_smba);

	if (retval)
		return retval;

	if (acpi_check_region(piix4_smba, SMBIOSIZE, piix4_driver.name))
		return -ENODEV;

	if (!request_region(piix4_smba, SMBIOSIZE, piix4_driver.name)) {
		dev_err(&PIIX4_dev->dev, "SMBus region 0x%x already in use!\n",
			piix4_smba);
		return -EBUSY;
	}

	/* Aux SMBus does not support IRQ information */
	if (aux) {
		dev_info(&PIIX4_dev->dev,
			 "Auxiliary SMBus Host Controller at 0x%x\n",
			 piix4_smba);
		return piix4_smba;
	}

	/* Request the SMBus I2C bus config region */
	if (!request_region(piix4_smba + i2ccfg_offset, 1, "i2ccfg")) {
		dev_err(&PIIX4_dev->dev, "SMBus I2C bus config region "
			"0x%x already in use!\n", piix4_smba + i2ccfg_offset);
		release_region(piix4_smba, SMBIOSIZE);
		return -EBUSY;
	}
	i2ccfg = inb_p(piix4_smba + i2ccfg_offset);
	release_region(piix4_smba + i2ccfg_offset, 1);

	if (i2ccfg & 1)
		dev_dbg(&PIIX4_dev->dev, "Using IRQ for SMBus\n");
	else
		dev_dbg(&PIIX4_dev->dev, "Using SMI# for SMBus\n");

	dev_info(&PIIX4_dev->dev,
		 "SMBus Host Controller at 0x%x, revision %d\n",
		 piix4_smba, i2ccfg >> 4);

	/* Find which register is used for port selection */
	if (PIIX4_dev->vendor == PCI_VENDOR_ID_AMD ||
	    PIIX4_dev->vendor == PCI_VENDOR_ID_HYGON) {
		if (PIIX4_dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS ||
		    (PIIX4_dev->device == PCI_DEVICE_ID_AMD_HUDSON2_SMBUS &&
		     PIIX4_dev->revision >= 0x1F)) {
			piix4_port_sel_sb800 = SB800_PIIX4_PORT_IDX_KERNCZ;
			piix4_port_mask_sb800 = SB800_PIIX4_PORT_IDX_MASK_KERNCZ;
			piix4_port_shift_sb800 = SB800_PIIX4_PORT_IDX_SHIFT_KERNCZ;
		} else {
			piix4_port_sel_sb800 = SB800_PIIX4_PORT_IDX_ALT;
			piix4_port_mask_sb800 = SB800_PIIX4_PORT_IDX_MASK;
			piix4_port_shift_sb800 = SB800_PIIX4_PORT_IDX_SHIFT;
		}
	} else {
		mmio_cfg.use_mmio = piix4_sb800_use_mmio(PIIX4_dev);
		retval = piix4_sb800_region_request(&PIIX4_dev->dev, &mmio_cfg);
		if (retval) {
			release_region(piix4_smba, SMBIOSIZE);
			return retval;
		}

		outb_p(SB800_PIIX4_PORT_IDX_SEL, SB800_PIIX4_SMB_IDX);
		port_sel = inb_p(SB800_PIIX4_SMB_IDX + 1);
		piix4_port_sel_sb800 = (port_sel & 0x01) ?
				       SB800_PIIX4_PORT_IDX_ALT :
				       SB800_PIIX4_PORT_IDX;
		piix4_port_mask_sb800 = SB800_PIIX4_PORT_IDX_MASK;
		piix4_port_shift_sb800 = SB800_PIIX4_PORT_IDX_SHIFT;
		piix4_sb800_region_release(&PIIX4_dev->dev, &mmio_cfg);
	}

	dev_info(&PIIX4_dev->dev,
		 "Using register 0x%02x for SMBus port selection\n",
		 (unsigned int)piix4_port_sel_sb800);

	return piix4_smba;
}

static int piix4_setup_aux(struct pci_dev *PIIX4_dev,
			   const struct pci_device_id *id,
			   unsigned short base_reg_addr)
{
	/* Set up auxiliary SMBus controllers found on some
	 * AMD chipsets e.g. SP5100 (SB700 derivative) */

	unsigned short piix4_smba;

	/* Read address of auxiliary SMBus controller */
	pci_read_config_word(PIIX4_dev, base_reg_addr, &piix4_smba);
	if ((piix4_smba & 1) == 0) {
		dev_dbg(&PIIX4_dev->dev,
			"Auxiliary SMBus controller not enabled\n");
		return -ENODEV;
	}

	piix4_smba &= 0xfff0;
	if (piix4_smba == 0) {
		dev_dbg(&PIIX4_dev->dev,
			"Auxiliary SMBus base address uninitialized\n");
		return -ENODEV;
	}

	if (acpi_check_region(piix4_smba, SMBIOSIZE, piix4_driver.name))
		return -ENODEV;

	if (!request_region(piix4_smba, SMBIOSIZE, piix4_driver.name)) {
		dev_err(&PIIX4_dev->dev, "Auxiliary SMBus region 0x%x "
			"already in use!\n", piix4_smba);
		return -EBUSY;
	}

	dev_info(&PIIX4_dev->dev,
		 "Auxiliary SMBus Host Controller at 0x%x\n",
		 piix4_smba);

	return piix4_smba;
}

int piix4_transaction(struct i2c_adapter *piix4_adapter, unsigned short piix4_smba)
{
	int temp;
	int result = 0;
	int timeout = 0;

	dev_dbg(&piix4_adapter->dev, "Transaction (pre): CNT=%02x, CMD=%02x, "
		"ADD=%02x, DAT0=%02x, DAT1=%02x\n", inb_p(SMBHSTCNT),
		inb_p(SMBHSTCMD), inb_p(SMBHSTADD), inb_p(SMBHSTDAT0),
		inb_p(SMBHSTDAT1));

	/* Make sure the SMBus host is ready to start transmitting */
	if ((temp = inb_p(SMBHSTSTS)) != 0x00) {
		dev_dbg(&piix4_adapter->dev, "SMBus busy (%02x). "
			"Resetting...\n", temp);
		outb_p(temp, SMBHSTSTS);
		if ((temp = inb_p(SMBHSTSTS)) != 0x00) {
			dev_err(&piix4_adapter->dev, "Failed! (%02x)\n", temp);
			return -EBUSY;
		} else {
			dev_dbg(&piix4_adapter->dev, "Successful!\n");
		}
	}

	/* start the transaction by setting bit 6 */
	outb_p(inb(SMBHSTCNT) | 0x040, SMBHSTCNT);

	/* We will always wait for a fraction of a second! (See PIIX4 docs errata) */
	if (srvrworks_csb5_delay) /* Extra delay for SERVERWORKS_CSB5 */
		usleep_range(2000, 2100);
	else
		usleep_range(250, 500);

	while ((++timeout < MAX_TIMEOUT) &&
	       ((temp = inb_p(SMBHSTSTS)) & 0x01))
		usleep_range(250, 500);

	/* If the SMBus is still busy, we give up */
	if (timeout == MAX_TIMEOUT) {
		dev_err(&piix4_adapter->dev, "SMBus Timeout!\n");
		result = -ETIMEDOUT;
	}

	if (temp & 0x10) {
		result = -EIO;
		dev_err(&piix4_adapter->dev, "Error: Failed bus transaction\n");
	}

	if (temp & 0x08) {
		result = -EIO;
		dev_dbg(&piix4_adapter->dev, "Bus collision! SMBus may be "
			"locked until next hard reset. (sorry!)\n");
		/* Clock stops and target is stuck in mid-transmission */
	}

	if (temp & 0x04) {
		result = -ENXIO;
		dev_dbg(&piix4_adapter->dev, "Error: no response!\n");
	}

	if (inb_p(SMBHSTSTS) != 0x00)
		outb_p(inb(SMBHSTSTS), SMBHSTSTS);

	if ((temp = inb_p(SMBHSTSTS)) != 0x00) {
		dev_err(&piix4_adapter->dev, "Failed reset at end of "
			"transaction (%02x)\n", temp);
	}
	dev_dbg(&piix4_adapter->dev, "Transaction (post): CNT=%02x, CMD=%02x, "
		"ADD=%02x, DAT0=%02x, DAT1=%02x\n", inb_p(SMBHSTCNT),
		inb_p(SMBHSTCMD), inb_p(SMBHSTADD), inb_p(SMBHSTDAT0),
		inb_p(SMBHSTDAT1));
	return result;
}
EXPORT_SYMBOL_NS_GPL(piix4_transaction, "PIIX4_SMBUS");

/* Return negative errno on error. */
static s32 piix4_access(struct i2c_adapter * adap, u16 addr,
		 unsigned short flags, char read_write,
		 u8 command, int size, union i2c_smbus_data * data)
{
	struct i2c_piix4_adapdata *adapdata = i2c_get_adapdata(adap);
	unsigned short piix4_smba = adapdata->smba;
	int i, len;
	int status;

	switch (size) {
	case I2C_SMBUS_QUICK:
		outb_p((addr << 1) | read_write,
		       SMBHSTADD);
		size = PIIX4_QUICK;
		break;
	case I2C_SMBUS_BYTE:
		outb_p((addr << 1) | read_write,
		       SMBHSTADD);
		if (read_write == I2C_SMBUS_WRITE)
			outb_p(command, SMBHSTCMD);
		size = PIIX4_BYTE;
		break;
	case I2C_SMBUS_BYTE_DATA:
		outb_p((addr << 1) | read_write,
		       SMBHSTADD);
		outb_p(command, SMBHSTCMD);
		if (read_write == I2C_SMBUS_WRITE)
			outb_p(data->byte, SMBHSTDAT0);
		size = PIIX4_BYTE_DATA;
		break;
	case I2C_SMBUS_WORD_DATA:
		outb_p((addr << 1) | read_write,
		       SMBHSTADD);
		outb_p(command, SMBHSTCMD);
		if (read_write == I2C_SMBUS_WRITE) {
			outb_p(data->word & 0xff, SMBHSTDAT0);
			outb_p((data->word & 0xff00) >> 8, SMBHSTDAT1);
		}
		size = PIIX4_WORD_DATA;
		break;
	case I2C_SMBUS_BLOCK_DATA:
		outb_p((addr << 1) | read_write,
		       SMBHSTADD);
		outb_p(command, SMBHSTCMD);
		if (read_write == I2C_SMBUS_WRITE) {
			len = data->block[0];
			if (len == 0 || len > I2C_SMBUS_BLOCK_MAX)
				return -EINVAL;
			outb_p(len, SMBHSTDAT0);
			inb_p(SMBHSTCNT);	/* Reset SMBBLKDAT */
			for (i = 1; i <= len; i++)
				outb_p(data->block[i], SMBBLKDAT);
		}
		size = PIIX4_BLOCK_DATA;
		break;
	default:
		dev_warn(&adap->dev, "Unsupported transaction %d\n", size);
		return -EOPNOTSUPP;
	}

	outb_p((size & 0x1C) + (ENABLE_INT9 & 1), SMBHSTCNT);

	status = piix4_transaction(adap, piix4_smba);
	if (status)
		return status;

	if ((read_write == I2C_SMBUS_WRITE) || (size == PIIX4_QUICK))
		return 0;


	switch (size) {
	case PIIX4_BYTE:
	case PIIX4_BYTE_DATA:
		data->byte = inb_p(SMBHSTDAT0);
		break;
	case PIIX4_WORD_DATA:
		data->word = inb_p(SMBHSTDAT0) + (inb_p(SMBHSTDAT1) << 8);
		break;
	case PIIX4_BLOCK_DATA:
		data->block[0] = inb_p(SMBHSTDAT0);
		if (data->block[0] == 0 || data->block[0] > I2C_SMBUS_BLOCK_MAX)
			return -EPROTO;
		inb_p(SMBHSTCNT);	/* Reset SMBBLKDAT */
		for (i = 1; i <= data->block[0]; i++)
			data->block[i] = inb_p(SMBBLKDAT);
		dev_dbg(&adap->dev, "Block read cmd %#04x len %d: %*ph\n",
			command, data->block[0], data->block[0],
			&data->block[1]);
		break;
	}
	return 0;
}

static uint8_t piix4_imc_read(uint8_t idx)
{
	outb_p(idx, KERNCZ_IMC_IDX);
	return inb_p(KERNCZ_IMC_DATA);
}

static void piix4_imc_write(uint8_t idx, uint8_t value)
{
	outb_p(idx, KERNCZ_IMC_IDX);
	outb_p(value, KERNCZ_IMC_DATA);
}

static int piix4_imc_sleep(void)
{
	int timeout = MAX_TIMEOUT;

	if (!request_muxed_region(KERNCZ_IMC_IDX, 2, "smbus_kerncz_imc"))
		return -EBUSY;

	/* clear response register */
	piix4_imc_write(0x82, 0x00);
	/* request ownership flag */
	piix4_imc_write(0x83, 0xB4);
	/* kick off IMC Mailbox command 96 */
	piix4_imc_write(0x80, 0x96);

	while (timeout--) {
		if (piix4_imc_read(0x82) == 0xfa) {
			release_region(KERNCZ_IMC_IDX, 2);
			return 0;
		}
		usleep_range(1000, 2000);
	}

	release_region(KERNCZ_IMC_IDX, 2);
	return -ETIMEDOUT;
}

static void piix4_imc_wakeup(void)
{
	int timeout = MAX_TIMEOUT;

	if (!request_muxed_region(KERNCZ_IMC_IDX, 2, "smbus_kerncz_imc"))
		return;

	/* clear response register */
	piix4_imc_write(0x82, 0x00);
	/* release ownership flag */
	piix4_imc_write(0x83, 0xB5);
	/* kick off IMC Mailbox command 96 */
	piix4_imc_write(0x80, 0x96);

	while (timeout--) {
		if (piix4_imc_read(0x82) == 0xfa)
			break;
		usleep_range(1000, 2000);
	}

	release_region(KERNCZ_IMC_IDX, 2);
}

int piix4_sb800_port_sel(u8 port, struct sb800_mmio_cfg *mmio_cfg)
{
	u8 smba_en_lo, val;

	if (mmio_cfg->use_mmio) {
		smba_en_lo = ioread8(mmio_cfg->addr + piix4_port_sel_sb800);
		val = (smba_en_lo & ~piix4_port_mask_sb800) | port;
		if (smba_en_lo != val)
			iowrite8(val, mmio_cfg->addr + piix4_port_sel_sb800);

		return (smba_en_lo & piix4_port_mask_sb800);
	}

	outb_p(piix4_port_sel_sb800, SB800_PIIX4_SMB_IDX);
	smba_en_lo = inb_p(SB800_PIIX4_SMB_IDX + 1);

	val = (smba_en_lo & ~piix4_port_mask_sb800) | port;
	if (smba_en_lo != val)
		outb_p(val, SB800_PIIX4_SMB_IDX + 1);

	return (smba_en_lo & piix4_port_mask_sb800);
}
EXPORT_SYMBOL_NS_GPL(piix4_sb800_port_sel, "PIIX4_SMBUS");

/*
 * Handles access to multiple SMBus ports on the SB800.
 * The port is selected by bits 2:1 of the smb_en register (0x2c).
 * Returns negative errno on error.
 *
 * Note: The selected port must be returned to the initial selection to avoid
 * problems on certain systems.
 */
static s32 piix4_access_sb800(struct i2c_adapter *adap, u16 addr,
		 unsigned short flags, char read_write,
		 u8 command, int size, union i2c_smbus_data *data)
{
	struct i2c_piix4_adapdata *adapdata = i2c_get_adapdata(adap);
	unsigned short piix4_smba = adapdata->smba;
	int retries = MAX_TIMEOUT;
	int smbslvcnt;
	u8 prev_port;
	int retval;

	retval = piix4_sb800_region_request(&adap->dev, &adapdata->mmio_cfg);
	if (retval)
		return retval;

	/* Request the SMBUS semaphore, avoid conflicts with the IMC */
	smbslvcnt  = inb_p(SMBSLVCNT);
	do {
		outb_p(smbslvcnt | 0x10, SMBSLVCNT);

		/* Check the semaphore status */
		smbslvcnt  = inb_p(SMBSLVCNT);
		if (smbslvcnt & 0x10)
			break;

		usleep_range(1000, 2000);
	} while (--retries);
	/* SMBus is still owned by the IMC, we give up */
	if (!retries) {
		retval = -EBUSY;
		goto release;
	}

	/*
	 * Notify the IMC (Integrated Micro Controller) if required.
	 * Among other responsibilities, the IMC is in charge of monitoring
	 * the System fans and temperature sensors, and act accordingly.
	 * All this is done through SMBus and can/will collide
	 * with our transactions if they are long (BLOCK_DATA).
	 * Therefore we need to request the ownership flag during those
	 * transactions.
	 */
	if ((size == I2C_SMBUS_BLOCK_DATA) && adapdata->notify_imc) {
		int ret;

		ret = piix4_imc_sleep();
		switch (ret) {
		case -EBUSY:
			dev_warn(&adap->dev,
				 "IMC base address index region 0x%x already in use.\n",
				 KERNCZ_IMC_IDX);
			break;
		case -ETIMEDOUT:
			dev_warn(&adap->dev,
				 "Failed to communicate with the IMC.\n");
			break;
		default:
			break;
		}

		/* If IMC communication fails do not retry */
		if (ret) {
			dev_warn(&adap->dev,
				 "Continuing without IMC notification.\n");
			adapdata->notify_imc = false;
		}
	}

	prev_port = piix4_sb800_port_sel(adapdata->port, &adapdata->mmio_cfg);

	retval = piix4_access(adap, addr, flags, read_write,
			      command, size, data);

	piix4_sb800_port_sel(prev_port, &adapdata->mmio_cfg);

	/* Release the semaphore */
	outb_p(smbslvcnt | 0x20, SMBSLVCNT);

	if ((size == I2C_SMBUS_BLOCK_DATA) && adapdata->notify_imc)
		piix4_imc_wakeup();

release:
	piix4_sb800_region_release(&adap->dev, &adapdata->mmio_cfg);
	return retval;
}

static u32 piix4_func(struct i2c_adapter *adapter)
{
	return I2C_FUNC_SMBUS_QUICK | I2C_FUNC_SMBUS_BYTE |
	    I2C_FUNC_SMBUS_BYTE_DATA | I2C_FUNC_SMBUS_WORD_DATA |
	    I2C_FUNC_SMBUS_BLOCK_DATA;
}

static const struct i2c_algorithm smbus_algorithm = {
	.smbus_xfer	= piix4_access,
	.functionality	= piix4_func,
};

static const struct i2c_algorithm piix4_smbus_algorithm_sb800 = {
	.smbus_xfer	= piix4_access_sb800,
	.functionality	= piix4_func,
};

static const struct pci_device_id piix4_ids[] = {
	{ PCI_DEVICE(PCI_VENDOR_ID_INTEL, PCI_DEVICE_ID_INTEL_82371AB_3) },
	{ PCI_DEVICE(PCI_VENDOR_ID_INTEL, PCI_DEVICE_ID_INTEL_82443MX_3) },
	{ PCI_DEVICE(PCI_VENDOR_ID_EFAR, PCI_DEVICE_ID_EFAR_SLC90E66_3) },
	{ PCI_DEVICE(PCI_VENDOR_ID_ATI, PCI_DEVICE_ID_ATI_IXP200_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_ATI, PCI_DEVICE_ID_ATI_IXP300_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_ATI, PCI_DEVICE_ID_ATI_IXP400_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_ATI, PCI_DEVICE_ID_ATI_SBX00_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_AMD, PCI_DEVICE_ID_AMD_HUDSON2_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_AMD, PCI_DEVICE_ID_AMD_KERNCZ_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_HYGON, PCI_DEVICE_ID_AMD_KERNCZ_SMBUS) },
	{ PCI_DEVICE(PCI_VENDOR_ID_SERVERWORKS,
		     PCI_DEVICE_ID_SERVERWORKS_OSB4) },
	{ PCI_DEVICE(PCI_VENDOR_ID_SERVERWORKS,
		     PCI_DEVICE_ID_SERVERWORKS_CSB5) },
	{ PCI_DEVICE(PCI_VENDOR_ID_SERVERWORKS,
		     PCI_DEVICE_ID_SERVERWORKS_CSB6) },
	{ PCI_DEVICE(PCI_VENDOR_ID_SERVERWORKS,
		     PCI_DEVICE_ID_SERVERWORKS_HT1000SB) },
	{ PCI_DEVICE(PCI_VENDOR_ID_SERVERWORKS,
		     PCI_DEVICE_ID_SERVERWORKS_HT1100LD) },
	{ 0, }
};

MODULE_DEVICE_TABLE (pci, piix4_ids);

static struct i2c_adapter *piix4_main_adapters[PIIX4_MAX_ADAPTERS];
static struct i2c_adapter *piix4_aux_adapter;
static int piix4_adapter_count;

struct piix4_asf_crs {
	u32 gsi;
	u8 triggering;
	u8 polarity;
	bool has_irq;
};

/*
 * Intercept the IRQ descriptor during the _CRS walk.  The default
 * conversion (acpi_dev_get_irqresource()) replaces the descriptor's
 * trigger/polarity with the ISA edge/high default ("ACPI: IRQ 7
 * override to edge, high" at boot).  On AMD Zen FCHs the ASF block
 * asserts this line level/active-low as _CRS declares, so under the
 * edge/high programming the slave interrupt never fires (mainline
 * acknowledges the same problem for IRQs 1/12 in
 * acpi_dev_irq_override()).  Keep the raw descriptor and register the
 * GSI ourselves.
 */
static int piix4_asf_crs_preproc(struct acpi_resource *ares, void *data)
{
	struct piix4_asf_crs *crs = data;

	if (ares->type == ACPI_RESOURCE_TYPE_IRQ) {
		struct acpi_resource_irq *irq = &ares->data.irq;

		if (irq->interrupt_count >= 1 && !crs->has_irq) {
			crs->gsi = irq->interrupts[0];
			crs->triggering = irq->triggering;
			crs->polarity = irq->polarity;
			crs->has_irq = true;
		}
		return 1;
	}
	if (ares->type == ACPI_RESOURCE_TYPE_EXTENDED_IRQ) {
		struct acpi_resource_extended_irq *irq = &ares->data.extended_irq;

		if (irq->interrupt_count >= 1 && !crs->has_irq) {
			crs->gsi = irq->interrupts[0];
			crs->triggering = irq->triggering;
			crs->polarity = irq->polarity;
			crs->has_irq = true;
		}
		return 1;
	}

	return 0;
}

static void piix4_asf_detect(struct pci_dev *dev)
{
	struct piix4_asf_crs crs = {};
	struct resource_entry *rentry;
	struct acpi_device *adev;
	LIST_HEAD(res_list);
	int ret;

	if (!asf_host_notify)
		return;

	adev = acpi_dev_get_first_match_dev(ACPI_SMBUS_MS_HID, NULL, -1);
	if (!adev)
		return;

	ret = acpi_dev_get_resources(adev, &res_list, piix4_asf_crs_preproc,
				     &crs);
	if (ret >= 0) {
		list_for_each_entry(rentry, &res_list, node) {
			struct resource *res = rentry->res;

			if (resource_type(res) == IORESOURCE_IO &&
			    !piix4_asf_smba) {
				piix4_asf_smba = res->start;
				piix4_asf_iolen = resource_size(res);
			}
		}
		acpi_dev_free_resource_list(&res_list);
	}
	acpi_dev_put(adev);

	if (crs.has_irq && piix4_asf_irqnum < 0) {
		u8 triggering = crs.triggering;
		u8 polarity = crs.polarity;

		/*
		 * Register the GSI with the attributes from _CRS (level/low on
		 * every known platform) instead of the ISA edge/high default
		 * that acpi_dev_get_irqresource() would impose. The ASF block
		 * asserts a level-low line, so the default silently loses
		 * every Host Notify. This only takes effect if we are the
		 * first user of the pin (see mp_check_pin_attr()).
		 */
		ret = acpi_register_gsi(&dev->dev, crs.gsi, triggering,
					polarity);
		if (ret < 0)
			dev_warn(&dev->dev,
				 "ASF: cannot program GSI %u as %s/%s (%d); the pin was already registered with different attributes, reboot to apply\n",
				 crs.gsi,
				 triggering == ACPI_EDGE_SENSITIVE ?
					"edge" : "level",
				 polarity == ACPI_ACTIVE_LOW ?
					"low" : "high",
				 ret);
		else
			piix4_asf_irqnum = ret;
	}

	if (asf_irq >= 0)
		piix4_asf_irqnum = asf_irq;

	if (piix4_asf_smba)
		dev_info(&dev->dev,
			 "ASF SMBus slave (SMB0001) at 0x%04x, IRQ %d\n",
			 piix4_asf_smba, piix4_asf_irqnum);
}

static void piix4_asf_update_ioport(u8 bit, unsigned long offset, bool set)
{
	unsigned long reg;

	reg = inb_p(offset);
	__assign_bit(bit, &reg, set);
	outb_p(reg, offset);
}

/* Caller must hold the FCH PM region (piix4_sb800_region_request) */
static void piix4_asf_update_mmio(u8 bit, bool set)
{
	unsigned long reg;

	reg = ioread32(piix4_asf_mmio_cfg.addr);
	__assign_bit(bit, &reg, set);
	iowrite32(reg, piix4_asf_mmio_cfg.addr);
}

/*
 * Restore MSTR_EN/CLK_EN to their boot state, so the controller keeps
 * doing master transfers under the stock driver after we let go.
 * Caller must hold the FCH PM region.
 */
static void piix4_asf_restore_ctl(void)
{
	u32 reg;

	reg = ioread32(piix4_asf_mmio_cfg.addr);
	reg &= ~(BIT(ASF_MSTR_EN) | BIT(ASF_CLK_EN));
	reg |= piix4_asf_boot_ctl;
	iowrite32(reg, piix4_asf_mmio_cfg.addr);
}

/*
 * Put the controller in slave/listen mode so it can receive Host Notify.
 * Caller must hold piix4_asf_mutex and the FCH PM region.
 * Sequence from amd_asf_setup_target().
 */
static void piix4_asf_slave_arm(unsigned short piix4_smba)
{
	/* Reset both host and slave status */
	outb_p(0, SMBHSTSTS);
	outb_p(0, ASFSLVSTA);
	outb_p(0, ASFSTA);

	/* Enable listening on the programmed address */
	piix4_asf_update_ioport(ASF_SLV_LISTN, ASFLISADDR, true);
	/* Slave mode: master enable off, clock on */
	piix4_asf_update_mmio(ASF_MSTR_EN, false);
	piix4_asf_update_mmio(ASF_CLK_EN, true);
	/* Enable the slave interrupt and take the slave out of reset */
	piix4_asf_update_ioport(ASF_SLV_INTR, ASFSLVEN, true);
	piix4_asf_update_ioport(ASF_SLV_RST, ASFSLVEN, false);
	/*
	 * Enable PEC handling and PEC append, as amd_asf_setup_target()
	 * does.  Note piix4_access() rewrites SMBHSTCNT on every master
	 * transaction, so these bits only affect slave reception.
	 */
	piix4_asf_update_ioport(ASF_DATA_EN, SMBHSTCNT, true);
	piix4_asf_update_ioport(ASF_PEC_SP, SMBHSTCNT, true);
	/* Route the 0x07 data window back to the ASF banks while listening */
	piix4_asf_update_ioport(ASF_DATA_EN, ASFDATABNKSEL, false);
}

/* Return negative errno on error. */
static s32 piix4_access_asf(struct i2c_adapter *adap, u16 addr,
			    unsigned short flags, char read_write,
			    u8 command, int size, union i2c_smbus_data *data)
{
	struct i2c_piix4_adapdata *adapdata = i2c_get_adapdata(adap);
	unsigned short piix4_smba = adapdata->smba;
	s32 result;
	int retval;
	u8 sta;

	mutex_lock(&piix4_asf_mutex);

	/* Checked under the mutex so teardown can quiesce us */
	if (!piix4_asf_active) {
		mutex_unlock(&piix4_asf_mutex);
		return piix4_access(adap, addr, flags, read_write, command,
				    size, data);
	}

	retval = piix4_sb800_region_request(&adap->dev, &piix4_asf_mmio_cfg);
	if (retval) {
		mutex_unlock(&piix4_asf_mutex);
		return retval;
	}

	/*
	 * The slave reset below discards any received-but-unread Host
	 * Notify.  Stop listening so nothing new is accepted, quiesce the
	 * interrupt source (synchronize_hardirq(), not synchronize_irq():
	 * the IRQ thread blocks on piix4_asf_mutex, which we hold), then
	 * drain both a notify the hard handler already acked (pending
	 * flag) and one it never got to see (status bit).
	 */
	piix4_asf_update_ioport(ASF_SLV_LISTN, ASFLISADDR, false);
	piix4_asf_update_ioport(ASF_SLV_INTR, ASFSLVEN, false);
	synchronize_hardirq(piix4_asf_irqnum);
	if (atomic_xchg(&piix4_asf_pending, 0))
		piix4_asf_process_bank();
	sta = inb_p(ASFSTA);
	if (sta & BIT(6)) {
		outb_p(sta | BIT(6), ASFSTA);
		piix4_asf_process_bank();
	}

	/*
	 * Take the slave offline while the controller acts as a master,
	 * per amd_asf_xfer().
	 */
	piix4_asf_update_ioport(ASF_SLV_RST, ASFSLVEN, true);
	outb_p(0, ASFSLVSTA);
	piix4_asf_update_mmio(ASF_MSTR_EN, true);

	/*
	 * ASFINDEX shares port 0x07 with SMBBLKDAT; route the data window
	 * to the host FIFO while mastering, otherwise block reads return
	 * the ASF bank contents instead of the slave's data.
	 */
	piix4_asf_update_ioport(ASF_DATA_EN, ASFDATABNKSEL, true);

	result = piix4_access(adap, addr, flags, read_write, command, size,
			      data);

	/* Back to listen mode so Host Notify keeps working */
	piix4_asf_slave_arm(piix4_smba);

	piix4_sb800_region_release(&adap->dev, &piix4_asf_mmio_cfg);
	mutex_unlock(&piix4_asf_mutex);

	return result;
}

static u32 piix4_func_asf(struct i2c_adapter *adapter)
{
	return piix4_func(adapter) | I2C_FUNC_SMBUS_HOST_NOTIFY;
}

static const struct i2c_algorithm piix4_smbus_algorithm_asf = {
	.smbus_xfer	= piix4_access_asf,
	.functionality	= piix4_func_asf,
};

static irqreturn_t piix4_asf_irq_handler(int irq, void *dev_id)
{
	unsigned short piix4_smba = piix4_asf_smba;
	u8 sta = inb_p(ASFSTA);

	/* Bit 6: slave interrupt.  The line is shared, only claim our own. */
	if (!(sta & BIT(6)))
		return IRQ_NONE;

	/* Ack so the level-triggered line deasserts */
	outb_p(sta | BIT(6), ASFSTA);

	atomic_set(&piix4_asf_pending, 1);
	return IRQ_WAKE_THREAD;
}

/*
 * Read the received message out of the ASF data bank and, if it is a
 * Host Notify, forward it to the i2c core.  Data-bank sequence from
 * amd_asf_process_target().  Caller must hold piix4_asf_mutex.
 */
static void piix4_asf_process_bank(void)
{
	unsigned short piix4_smba = piix4_asf_smba;
	u8 data[ASF_BLOCK_MAX_BYTES];
	u8 bank, reg, cmd = 1;
	u8 len = 0, idx;

	reg = inb_p(ASFSLVSTA);
	if (reg & ASF_ERROR_STATUS) {
		/* Reception error: mark both banks consumed */
		reg |= GENMASK(3, 2);
		outb_p(reg, ASFDATABNKSEL);
	} else {
		reg = inb_p(ASFDATABNKSEL);
		bank = (reg & BIT(3)) ? 1 : 0;
		if (bank) {
			reg |= BIT(4);
			reg &= ~BIT(3);
		} else {
			reg &= ~BIT(4);
			reg &= ~BIT(2);
		}
		outb_p(reg, ASFDATABNKSEL);

		cmd = inb_p(ASFINDEX);
		len = inb_p(ASFDATARWPTR);
		if (len > ASF_BLOCK_MAX_BYTES)
			len = ASF_BLOCK_MAX_BYTES;
		for (idx = 0; idx < len; idx++)
			data[idx] = inb_p(ASFINDEX);

		/* Mark the bank consumed */
		if (bank)
			reg |= BIT(3);
		else
			reg |= BIT(2);
		outb_p(reg, ASFDATABNKSEL);
	}
	outb_p(0, ASFSETDATARDPTR);

	/*
	 * Observed bank layout on this hardware: the first byte read via
	 * ASFINDEX is the message's target address byte, the payload
	 * follows.  For a Host Notify the target is the SMBus Host (0x08,
	 * Wr) and the payload is the notifying device's own address byte
	 * plus two status bytes.
	 * i2c_handle_smbus_host_notify() only wakes the client's IRQ
	 * thread, so calling it with the mutex held cannot deadlock.
	 */
	if (cmd != (ASF_HOST_ADDR << 1) || len < 1)
		return;

	if (piix4_aux_adapter) {
		dev_dbg(&piix4_aux_adapter->dev,
			"ASF Host Notify from 0x%02x, %d byte(s): %*ph\n",
			data[0] >> 1, len, (int)len, data);
		i2c_handle_smbus_host_notify(piix4_aux_adapter, data[0] >> 1);
	}
}

static irqreturn_t piix4_asf_irq_thread(int irq, void *dev_id)
{
	unsigned short piix4_smba = piix4_asf_smba;
	int i;

	mutex_lock(&piix4_asf_mutex);

	if (!piix4_asf_active) {
		mutex_unlock(&piix4_asf_mutex);
		return IRQ_HANDLED;
	}

	/* A master transfer may have drained the bank ahead of us */
	if (atomic_xchg(&piix4_asf_pending, 0))
		piix4_asf_process_bank();

	/*
	 * The IRQ is edge-triggered on this platform (ACPI override), so
	 * messages whose edges coalesced generate no further interrupts:
	 * drain until the status stays clear.
	 */
	for (i = 0; i < 4; i++) {
		u8 sta = inb_p(ASFSTA);

		if (!(sta & BIT(6)))
			break;
		outb_p(sta | BIT(6), ASFSTA);
		piix4_asf_process_bank();
	}

	/*
	 * Reset and re-arm the slave.  The bank-consumed writes in
	 * piix4_asf_process_bank() do not reliably free the receive
	 * banks on this hardware; once both banks fill, the slave NAKs
	 * everything and, with an edge IRQ, reception dies permanently.
	 * The reset (same cycle the master-transfer path runs) frees
	 * them for certain.
	 */
	if (!piix4_sb800_region_request(piix4_asf_dev, &piix4_asf_mmio_cfg)) {
		piix4_asf_update_ioport(ASF_SLV_RST, ASFSLVEN, true);
		outb_p(0, ASFSLVSTA);
		piix4_asf_slave_arm(piix4_smba);
		piix4_sb800_region_release(piix4_asf_dev, &piix4_asf_mmio_cfg);
	}

	mutex_unlock(&piix4_asf_mutex);

	return IRQ_HANDLED;
}

static void piix4_asf_enable(struct pci_dev *dev, unsigned short piix4_smba)
{
	int retval;

	if (!piix4_asf_smba || piix4_asf_smba != piix4_smba ||
	    piix4_asf_irqnum < 0)
		return;

	/* All ASF registers must lie inside the firmware-described window */
	if (piix4_asf_iolen < ASF_IOSIZE) {
		dev_warn(&dev->dev,
			 "SMB0001 IO window too small (%#x < %#x), not enabling Host Notify\n",
			 piix4_asf_iolen, ASF_IOSIZE);
		return;
	}

	piix4_asf_mmio_cfg.use_mmio = piix4_sb800_use_mmio(dev);
	if (!piix4_asf_mmio_cfg.use_mmio) {
		dev_warn(&dev->dev,
			 "ASF slave setup needs FCH PM MMIO, not enabling Host Notify\n");
		return;
	}

	/*
	 * The ASF registers extend past the SMBIOSIZE window already
	 * requested for the adapter; claim the rest of the _CRS range.
	 */
	if (acpi_check_region(piix4_smba + SMBIOSIZE, ASF_IOSIZE - SMBIOSIZE,
			      piix4_driver.name))
		return;

	if (!request_region(piix4_smba + SMBIOSIZE, ASF_IOSIZE - SMBIOSIZE,
			    "piix4-asf")) {
		dev_warn(&dev->dev,
			 "ASF register region 0x%x already in use, not enabling Host Notify\n",
			 piix4_smba + SMBIOSIZE);
		return;
	}

	/*
	 * Install the IRQ handler before arming the slave: once the slave
	 * interrupt is enabled, an incoming Host Notify asserts the
	 * level-triggered line and only our handler can ack it.
	 *
	 * The trigger/polarity were programmed at acpi_register_gsi()
	 * time in piix4_asf_detect() (level/low per the _CRS descriptor;
	 * IRQF_TRIGGER_* flags cannot reprogram an IOAPIC pin).
	 */
	retval = request_threaded_irq(piix4_asf_irqnum, piix4_asf_irq_handler,
				      piix4_asf_irq_thread, IRQF_SHARED,
				      "piix4-asf", &piix4_asf_irq_cookie);
	if (retval) {
		dev_warn(&dev->dev, "ASF: failed to request IRQ %d: %d\n",
			 piix4_asf_irqnum, retval);
		goto release_ioregion;
	}

	retval = piix4_sb800_region_request(&dev->dev, &piix4_asf_mmio_cfg);
	if (retval) {
		free_irq(piix4_asf_irqnum, &piix4_asf_irq_cookie);
		goto release_ioregion;
	}

	piix4_asf_dev = &dev->dev;

	mutex_lock(&piix4_asf_mutex);
	/* Remember the boot state of MSTR_EN/CLK_EN for teardown */
	piix4_asf_boot_ctl = ioread32(piix4_asf_mmio_cfg.addr) &
			     (BIT(ASF_MSTR_EN) | BIT(ASF_CLK_EN));
	/* Listen for messages addressed to the SMBus Host (Host Notify) */
	outb_p((ASF_HOST_ADDR << 1) | BIT(ASF_SLV_LISTN), ASFLISADDR);
	piix4_asf_slave_arm(piix4_smba);
	mutex_unlock(&piix4_asf_mutex);

	piix4_sb800_region_release(&dev->dev, &piix4_asf_mmio_cfg);

	piix4_asf_active = true;
	dev_info(&dev->dev, "SMBus Host Notify enabled via ASF (IRQ %d)\n",
		 piix4_asf_irqnum);
	return;

release_ioregion:
	release_region(piix4_smba + SMBIOSIZE, ASF_IOSIZE - SMBIOSIZE);
}

static void piix4_asf_disable(struct device *dev)
{
	unsigned short piix4_smba = piix4_asf_smba;

	if (!piix4_asf_active)
		return;

	/*
	 * Quiesce under the mutex: any transfer already inside the ASF
	 * dance completes (and re-arms the slave) before we disarm here.
	 * MSTR_EN/CLK_EN are restored to their boot state in the same
	 * critical section, so a transfer racing with removal either runs
	 * the full ASF dance or a plain piix4_access() on a controller
	 * already back in its firmware state.  free_irq() must stay
	 * outside the mutex because the IRQ thread takes it.
	 */
	mutex_lock(&piix4_asf_mutex);
	piix4_asf_active = false;
	/* Sequence from amd_asf_unreg_target() */
	piix4_asf_update_ioport(ASF_SLV_INTR, ASFSLVEN, false);
	piix4_asf_update_ioport(ASF_SLV_RST, ASFSLVEN, true);
	if (!piix4_sb800_region_request(dev, &piix4_asf_mmio_cfg)) {
		piix4_asf_restore_ctl();
		piix4_sb800_region_release(dev, &piix4_asf_mmio_cfg);
	}
	mutex_unlock(&piix4_asf_mutex);

	free_irq(piix4_asf_irqnum, &piix4_asf_irq_cookie);
	release_region(piix4_smba + SMBIOSIZE, ASF_IOSIZE - SMBIOSIZE);
}

static int piix4_add_adapter(struct pci_dev *dev, unsigned short smba,
			     bool sb800_main, u8 port, bool notify_imc,
			     u8 hw_port_nr, const char *name,
			     struct i2c_adapter **padap)
{
	struct i2c_adapter *adap;
	struct i2c_piix4_adapdata *adapdata;
	int retval;

	adap = kzalloc_obj(*adap);
	if (adap == NULL) {
		release_region(smba, SMBIOSIZE);
		return -ENOMEM;
	}

	adap->owner = THIS_MODULE;
	adap->class = I2C_CLASS_HWMON;
	/*
	 * Host Notify support must be decided here: i2c_add_adapter() only
	 * creates the host-notify IRQ domain when the adapter already
	 * advertises I2C_FUNC_SMBUS_HOST_NOTIFY.
	 */
	if (sb800_main)
		adap->algo = &piix4_smbus_algorithm_sb800;
	else if (piix4_asf_active && smba == piix4_asf_smba)
		adap->algo = &piix4_smbus_algorithm_asf;
	else
		adap->algo = &smbus_algorithm;

	adapdata = kzalloc_obj(*adapdata);
	if (adapdata == NULL) {
		kfree(adap);
		release_region(smba, SMBIOSIZE);
		return -ENOMEM;
	}

	adapdata->mmio_cfg.use_mmio = piix4_sb800_use_mmio(dev);
	adapdata->smba = smba;
	adapdata->sb800_main = sb800_main;
	adapdata->port = port << piix4_port_shift_sb800;
	adapdata->notify_imc = notify_imc;

	/* set up the sysfs linkage to our parent device */
	adap->dev.parent = &dev->dev;

	if (has_acpi_companion(&dev->dev)) {
		acpi_preset_companion(&adap->dev,
				      ACPI_COMPANION(&dev->dev),
				      hw_port_nr);
	}

	snprintf(adap->name, sizeof(adap->name),
		"SMBus PIIX4 adapter%s at %04x", name, smba);

	i2c_set_adapdata(adap, adapdata);

	retval = i2c_add_adapter(adap);
	if (retval) {
		kfree(adapdata);
		kfree(adap);
		release_region(smba, SMBIOSIZE);
		return retval;
	}

	/*
	 * The AUX bus can not be probed as on some platforms it reports all
	 * devices present and all reads return "0".
	 * This would allow the ee1004 to be probed incorrectly.
	 */
	if (port == 0)
		i2c_register_spd_write_enable(adap);

	*padap = adap;
	return 0;
}

static int piix4_add_adapters_sb800(struct pci_dev *dev, unsigned short smba,
				    bool notify_imc)
{
	struct i2c_piix4_adapdata *adapdata;
	int port;
	int retval;

	if (dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS ||
	    (dev->device == PCI_DEVICE_ID_AMD_HUDSON2_SMBUS &&
	     dev->revision >= 0x1F)) {
		piix4_adapter_count = HUDSON2_MAIN_PORTS;
	} else {
		piix4_adapter_count = PIIX4_MAX_ADAPTERS;
	}

	for (port = 0; port < piix4_adapter_count; port++) {
		u8 hw_port_nr = port == 0 ? 0 : port + 1;

		retval = piix4_add_adapter(dev, smba, true, port, notify_imc,
					   hw_port_nr,
					   piix4_main_port_names_sb800[port],
					   &piix4_main_adapters[port]);
		if (retval < 0)
			goto error;
	}

	return retval;

error:
	dev_err(&dev->dev,
		"Error setting up SB800 adapters. Unregistering!\n");
	while (--port >= 0) {
		adapdata = i2c_get_adapdata(piix4_main_adapters[port]);
		if (adapdata->smba) {
			i2c_del_adapter(piix4_main_adapters[port]);
			kfree(adapdata);
			kfree(piix4_main_adapters[port]);
			piix4_main_adapters[port] = NULL;
		}
	}

	return retval;
}

static int piix4_probe(struct pci_dev *dev, const struct pci_device_id *id)
{
	int retval;
	bool is_sb800 = false;
	bool is_asf = false;
	acpi_status status;
	acpi_handle handle;

	if ((dev->vendor == PCI_VENDOR_ID_ATI &&
	     dev->device == PCI_DEVICE_ID_ATI_SBX00_SMBUS &&
	     dev->revision >= 0x40) ||
	    dev->vendor == PCI_VENDOR_ID_AMD ||
	    dev->vendor == PCI_VENDOR_ID_HYGON) {
		bool notify_imc = false;
		is_sb800 = true;

		if ((dev->vendor == PCI_VENDOR_ID_AMD ||
		     dev->vendor == PCI_VENDOR_ID_HYGON) &&
		    dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS) {
			u8 imc;

			/*
			 * Detect if IMC is active or not, this method is
			 * described on coreboot's AMD IMC notes
			 */
			pci_bus_read_config_byte(dev->bus, PCI_DEVFN(0x14, 3),
						 0x40, &imc);
			if (imc & 0x80)
				notify_imc = true;
		}

		/* base address location etc changed in SB800 */
		retval = piix4_setup_sb800(dev, id, 0);
		if (retval < 0)
			return retval;

		/*
		 * Try to register multiplexed main SMBus adapter,
		 * give up if we can't
		 */
		retval = piix4_add_adapters_sb800(dev, retval, notify_imc);
		if (retval < 0)
			return retval;
	} else {
		retval = piix4_setup(dev, id);
		if (retval < 0)
			return retval;

		/* Try to register main SMBus adapter, give up if we can't */
		retval = piix4_add_adapter(dev, retval, false, 0, false, 0,
					   "", &piix4_main_adapters[0]);
		if (retval < 0)
			return retval;
		piix4_adapter_count = 1;
	}

	/* Check for auxiliary SMBus on some AMD chipsets */
	retval = -ENODEV;

	if (dev->vendor == PCI_VENDOR_ID_ATI &&
	    dev->device == PCI_DEVICE_ID_ATI_SBX00_SMBUS) {
		if (dev->revision < 0x40) {
			retval = piix4_setup_aux(dev, id, 0x58);
		} else {
			/* SB800 added aux bus too */
			retval = piix4_setup_sb800(dev, id, 1);
		}
	}

	status = acpi_get_handle(NULL, (acpi_string)SB800_ASF_ACPI_PATH, &handle);
	if (ACPI_SUCCESS(status))
		is_asf = true;

	if (dev->vendor == PCI_VENDOR_ID_AMD &&
	    (dev->device == PCI_DEVICE_ID_AMD_HUDSON2_SMBUS ||
	     dev->device == PCI_DEVICE_ID_AMD_KERNCZ_SMBUS)) {
		/* Do not setup AUX port if ASF is enabled */
		if (!is_asf)
			retval = piix4_setup_sb800(dev, id, 1);
	}

	if (retval > 0) {
		/*
		 * If the firmware describes the aux controller's ASF slave
		 * function (SMB0001), enable Host Notify reception before
		 * registering the adapter.
		 */
		piix4_asf_detect(dev);
		piix4_asf_enable(dev, retval);

		/* Try to add the aux adapter if it exists,
		 * piix4_add_adapter will clean up if this fails */
		piix4_add_adapter(dev, retval, false, 0, false, 1,
				  is_sb800 ? piix4_aux_port_name_sb800 : "",
				  &piix4_aux_adapter);
		if (!piix4_aux_adapter)
			piix4_asf_disable(&dev->dev);
	}

	return 0;
}

static void piix4_adap_remove(struct i2c_adapter *adap)
{
	struct i2c_piix4_adapdata *adapdata = i2c_get_adapdata(adap);

	if (adapdata->smba) {
		i2c_del_adapter(adap);
		if (adapdata->port == (0 << piix4_port_shift_sb800))
			release_region(adapdata->smba, SMBIOSIZE);
		kfree(adapdata);
		kfree(adap);
	}
}

static void piix4_remove(struct pci_dev *dev)
{
	int port = piix4_adapter_count;

	while (--port >= 0) {
		if (piix4_main_adapters[port]) {
			piix4_adap_remove(piix4_main_adapters[port]);
			piix4_main_adapters[port] = NULL;
		}
	}

	if (piix4_aux_adapter) {
		piix4_asf_disable(&dev->dev);
		piix4_adap_remove(piix4_aux_adapter);
		piix4_aux_adapter = NULL;
	}
}

static struct pci_driver piix4_driver = {
	.name		= "piix4_smbus",
	.id_table	= piix4_ids,
	.probe		= piix4_probe,
	.remove		= piix4_remove,
};

module_pci_driver(piix4_driver);

MODULE_AUTHOR("Frodo Looijaard <frodol@dds.nl>");
MODULE_AUTHOR("Philip Edelbrock <phil@netroedge.com>");
MODULE_DESCRIPTION("PIIX4 SMBus driver");
MODULE_LICENSE("GPL");
