# Upstreaming notes

Research date: 2026-09-13/14. Reference tree: `/home/andrew/Developer/others/linux`
at `7f063b2f17eaba2a35e251aa53627f2a70d536e2` (post-7.2-rc merge window, 2026-08-20).

**Caveat on method.** The reference checkout is a `--depth 1` shallow clone, so no
`git log`/`git blame` was available locally. All commit history below was read from
`git.kernel.org` cgit (`/log/<path>` and `/patch/?id=<sha>`), which is authoritative.
`lore.kernel.org` and `patchwork.kernel.org` are behind an Anubis proof-of-work
challenge and cannot be fetched with plain `curl`. Mailing-list research was
therefore done three ways, and each section says which:

- **linux-i2c (§3.2, §4.1)** — the complete public-inbox archive was cloned
  (`git clone https://lore.kernel.org/linux-i2c/0`, 87,345 messages, 2008 →
  2026-09) and quotes were read from the message bodies. This is the strongest
  sourcing in the document; the `https://lore.kernel.org/linux-i2c/<msgid>/`
  URLs are the canonical form of Message-IDs read out of that archive.
- **linux-input (§3.1)** — read from the **marc.info** mirror
  (`https://marc.info/?l=linux-input&m=<id>&w=4`), which prints the real
  `Message-ID:` header; the `lore.kernel.org` URLs given are reconstructed from
  those Message-IDs and were not re-fetched. **Check each before quoting it in
  a public posting.**
- **patchwork.ozlabs.org** (linux-i2c patch states) is reachable with `curl` and
  was used to cross-check what is in flight.

Commit messages quoted anywhere in this document were fetched directly from
git.kernel.org cgit and are exact. Where a claim could not be verified it says
so explicitly.

The four patches:

| # | Change | File(s) | State today |
|---|---|---|---|
| 1 | ASF SMBus Host Notify on SMB0001 AMD FCH platforms | `drivers/i2c/busses/i2c-piix4.c` | not yet a patch file; `diff -u ref/i2c-piix4.c module/i2c-piix4.c`, 1013 added / 5 removed lines |
| 2 | 300 ms settle before the resume config pass | `drivers/input/rmi4/rmi_smbus.c` | `upstream/0001-...settle...patch` |
| 3 | RMI4 doze interval 6 on the Lenovo pad list | `drivers/input/mouse/synaptics.c` | `upstream/0002-...doze-interval...patch` |
| 4 | `LEN2073` in `smbus_pnp_ids[]` | `drivers/input/mouse/synaptics.c` | not written yet |

---

## 1. Maintainer map

`scripts/get_maintainer.pl` was run in the reference tree. Running it on the two
existing `.patch` files is unreliable: they are hand-written diffs without
`index` lines, so the git fallback produces `Bad divisor in main::vcs_assign: 0`
and adds nothing. Run it on **file paths** (`-f`) instead — the results below are
identical with and without `--no-git-fallback`.

### Patch 2 and 3 and 4 — input side

```
$ scripts/get_maintainer.pl --no-git-fallback -f drivers/input/rmi4/rmi_smbus.c
$ scripts/get_maintainer.pl --no-git-fallback -f drivers/input/mouse/synaptics.c
Dmitry Torokhov <dmitry.torokhov@gmail.com> (maintainer:INPUT (KEYBOARD, MOUSE, JOYSTICK, TOUCHSCREEN)...)
linux-input@vger.kernel.org (open list:INPUT (KEYBOARD, MOUSE, JOYSTICK, TOUCHSCREEN)...)
linux-kernel@vger.kernel.org (open list)
```

Same output for `drivers/input/mouse/psmouse-smbus.c` and
`drivers/input/rmi4/rmi_driver.c`. There is **no separate RMI4 or Synaptics
MAINTAINERS entry** — `grep -i 'rmi4\|synaptics' MAINTAINERS` finds only
unrelated ARM SoC / DRM panel entries. Everything under `drivers/input/` is one
entry:

```
INPUT (KEYBOARD, MOUSE, JOYSTICK, TOUCHSCREEN) DRIVERS
M:  Dmitry Torokhov <dmitry.torokhov@gmail.com>
L:  linux-input@vger.kernel.org
S:  Maintained
Q:  http://patchwork.kernel.org/project/linux-input/list/
T:  git git://git.kernel.org/pub/scm/linux/kernel/git/dtor/input.git
F:  drivers/input/
```

So: **one maintainer, one list, one tree** (`dtor/input.git`, branches `next`
and `for-linus`). Dmitry applies patches himself; there are no designated
reviewers to Cc. Benjamin Tissoires wrote the original RMI4-over-SMBus and
psmouse-SMBus-companion code (82264d0cf7ae, 8eb92e5c9133, bf232e460a35) and is
the obvious optional Cc for patch 2, but `get_maintainer` does not produce him
and MAINTAINERS does not list him for these files.

### Patch 1 — i2c side

```
$ scripts/get_maintainer.pl --no-git-fallback -f drivers/i2c/busses/i2c-piix4.c
Jean Delvare <jdelvare@suse.com> (maintainer:I2C/SMBUS CONTROLLER DRIVERS FOR PC)
Andi Shyti <andi.shyti@kernel.org> (maintainer:I2C SUBSYSTEM HOST DRIVERS)
linux-i2c@vger.kernel.org (open list:I2C/SMBUS CONTROLLER DRIVERS FOR PC)
linux-kernel@vger.kernel.org (open list)
```

Note the address is `jdelvare@suse.com`, not `@suse.de` (the `@suse.de` form
appears in his older commits, e.g. 0183eb8bb59d from 2019).

Related files, if you need to Cc their owners:

```
$ scripts/get_maintainer.pl --no-git-fallback -f drivers/i2c/busses/i2c-amd-asf-plat.c
Shyam Sundar S K <shyam-sundar.s-k@amd.com> (maintainer:AMD ASF I2C DRIVER)
Andi Shyti <andi.shyti@kernel.org> (maintainer:I2C SUBSYSTEM HOST DRIVERS)
linux-i2c@vger.kernel.org (open list:AMD ASF I2C DRIVER)
linux-kernel@vger.kernel.org (open list)

$ scripts/get_maintainer.pl --no-git-fallback -f drivers/i2c/i2c-core-smbus.c
Andi Shyti <andi.shyti@kernel.org> (maintainer:I2C SUBSYSTEM)
linux-i2c@vger.kernel.org (open list:I2C SUBSYSTEM)
linux-kernel@vger.kernel.org (open list)

$ scripts/get_maintainer.pl --no-git-fallback -f drivers/i2c/busses/i2c-i801.c
Jean Delvare <jdelvare@suse.com> (maintainer:I2C/SMBUS CONTROLLER DRIVERS FOR PC)
Andi Shyti <andi.shyti@kernel.org> (maintainer:I2C SUBSYSTEM HOST DRIVERS)
```

### Trees, and the Wolfram Sang question

**Wolfram Sang is no longer the I2C maintainer in this tree.** In
`MAINTAINERS` at 7f063b2f he holds only `GENERIC GPIO I2C DRIVER`,
`GENERIC PINCTRL I2C DEMULTIPLEXER DRIVER`, `GPIO SLOPPY LOGIC ANALYZER`,
`I3C DRIVER FOR RENESAS`, `RENESAS EMEV2 I2C DRIVER`, `RENESAS R-CAR I2C
DRIVERS` and `TMIO/SDHI MMC DRIVER` — all as `wsa+renesas@sang-engineering.com`.
Both `I2C SUBSYSTEM` and `I2C SUBSYSTEM HOST DRIVERS` name **Andi Shyti** with
the same tree:

```
T:  git git://git.kernel.org/pub/scm/linux/kernel/git/andi.shyti/linux.git
Q:  https://patchwork.ozlabs.org/project/linux-i2c/list/
```

Corroboration that this is live: `i2c-amd-asf-plat.c` history shows
`Merge tag 'i2c-7.3-part1' of .../git/an...` (2026-08-19) — pull requests come
from Andi's tree. Shyam's 2024 ASF series carries
`Signed-off-by: Andi Shyti <andi.shyti@kernel.org>` as the applying maintainer
(05d980046f5a, 650e2c396a98, c509ebdb95ee). Do **not** address Wolfram as the
i2c maintainer. He is still worth an optional Cc on Host Notify specifically —
he wrote `i2c: rcar: add HostNotify support`, `i2c: add debug message for
detected HostNotify alerts` and `i2c: mark HostNotify target address as used`
(patchwork.ozlabs.org/project/linux-i2c/patch/20200910091118.13434-1-wsa+renesas@sang-engineering.com/,
.../20240704032940.4268-2-wsa+renesas@sang-engineering.com/,
.../20240710085506.31267-2-wsa+renesas@sang-engineering.com/) — but that is a
courtesy Cc, not a required one.

### Summary table

| Patch | Files | To: | Cc: | List | Tree |
|---|---|---|---|---|---|
| 1 ASF Host Notify | `drivers/i2c/busses/i2c-piix4.c` (+`i2c-piix4.h` if split) | Jean Delvare `<jdelvare@suse.com>`, Andi Shyti `<andi.shyti@kernel.org>` | Shyam Sundar S K `<shyam-sundar.s-k@amd.com>` (owns `i2c-amd-asf-plat.c`, which shares the register block and the exported `piix4_transaction()`); Mario Limonciello `<superm1@kernel.org>` (recent AMD FCH work on this file); optionally Andy Shevchenko `<andriy.shevchenko@linux.intel.com>` (reviewed the ASF series and wrote the SMB0001 ACPI-platform rule), Wolfram Sang (HostNotify) | `linux-i2c@vger.kernel.org`, `linux-kernel@vger.kernel.org` | `andi.shyti/linux.git` (`i2c/i2c-host`) |
| 2 rmi4 resume settle | `drivers/input/rmi4/rmi_smbus.c` | Dmitry Torokhov `<dmitry.torokhov@gmail.com>` | optionally Benjamin Tissoires `<bentiss@kernel.org>` | `linux-input@vger.kernel.org`, `linux-kernel@vger.kernel.org` | `dtor/input.git` |
| 3 doze interval | `drivers/input/mouse/synaptics.c` | Dmitry Torokhov | — | same | `dtor/input.git` |
| 4 LEN2073 | `drivers/input/mouse/synaptics.c` | Dmitry Torokhov | — | same | `dtor/input.git` |

**Two trees, therefore two separate series.** Patch 1 goes to linux-i2c and
Andi Shyti's tree; patches 2–4 go to linux-input and Dmitry's tree. They cannot
be one series and must not be sent with a shared cover letter implying an
ordering dependency that one maintainer can satisfy. In practice patches 3 and
4 are *useless* without patch 1 on this hardware (see §4), which is a real
sequencing problem to state explicitly in each cover letter with a `Link:` to
the other series on lore.

---

## 2. Precedents

All hashes verified against `git.kernel.org` cgit; commit messages quoted from
`https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/patch/?id=<sha>`.

### 2.1 For patch 2 (resume settle delay) — the decisive history

This exact problem has been through upstream twice already, and the outcome
constrains how patch 2 must be argued.

**`92e24e0e57f7` — "Input: psmouse - add delay when deactivating for SMBus mode"**
(Jeffery Miller, Google, 2023-07-26). Added `msleep(30)` in
`psmouse-smbus.c` after `psmouse_deactivate()`. Its commit message is the
template for a delay patch that got accepted:

- names the machine (Lenovo T440p) and the reproduction rate ("1 in 10 boots");
- pastes the actual failure dmesg (`i801_smbus ... No response`,
  `rmi4_smbus 0-002c: failed to get SMBus version number!`);
- gives the *measured* window: "Experimentation on the Lenovo T440p showed that
  a delay of 7-12ms on resume allowed the companion to respond";
- and then justifies the constant it actually used by citing someone else:
  "The 30ms delay in this patch was chosen based on the linux-input message:
  Link: https://lore.kernel.org/all/BYAPR03MB47572F2C65E52ED673238D41B2439@BYAPR03MB4757.namprd03.prod.outlook.com/"
  (a `namprd03.prod.outlook.com` address, i.e. a Synaptics vendor statement).

**`b35726396390` — Revert "Input: psmouse - add delay when deactivating for
SMBus mode"** (Dmitry Torokhov, 2023-10-12). Read this one in full before
writing patch 2's commit message. Dmitry's own words:

> "While the patch itself is correct, it uncovered an issue with fallback to
> PS/2 mode ... While discussing various approaches to fix the issue it was
> noted that this patch ass undesired delay in the "fast" resume path of PS/2
> device, and it would be better to actually use "reset_delay" option defined
> in struct rmi_device_platform_data and have RMI code handle it for SMBus
> transport as well."

With `Reported-by: Thorsten Leemhuis <linux@leemhuis.info>` and a `Closes:` link.

**`5030b2fe6aab` — "Input: synaptics-rmi4 - handle reset delay when using SMBus
trsnsport"** (Dmitry Torokhov, 2023-10-13; note the typo in the upstream
subject). This is the replacement, and it is the code your patch sits next to:

> "Note that originally the delay was added to psmouse driver in 92e24e0e57f7
> ... but that resulted in an unwanted delay in "fast" reconnect handler for
> the serio port, so it was decided to revert the patch and have the delay
> being handled in the RMI4 driver, similar to the other transports."

with `Tested-by: Jeffery Miller <jefferymiller@google.com>` and
`Link: https://lore.kernel.org/r/ZR1yUFJ8a9Zt606N@penguin`.

**`e2cb5cc822b6` — "Input: psmouse - fix fast_reconnect function for PS/2
mode"** (Jeffery Miller, 2023-10-13) — the crash the revert was about. Carries
`Fixes:`, `Reported-by:` + `Tested-by:` from Thorsten Leemhuis, and a `Link:`.

**What is in the tree today, verified:** `psmouse-smbus.c` contains **no**
`msleep` (`grep -n msleep drivers/input/mouse/psmouse-smbus.c` → nothing). The
only delay on this path is `rmi_smbus.c:240`

```c
	/*
	 * psmouse driver resets the controller, we only need to wait
	 * to give the firmware chance to fully reinitialize.
	 */
	if (rmi_smb->xport.pdata.reset_delay_ms)
		msleep(rmi_smb->xport.pdata.reset_delay_ms);
```

inside `rmi_smb_enable_smbus_mode()`, reached from `rmi_smb_reset()`, with
`reset_delay_ms = 30` set by `synaptics_create_intertouch()`
(`synaptics.c:1793`). Plus `rmi_driver.c:866`
`mdelay(pdata->reset_delay_ms ?: DEFAULT_RESET_DELAY_MS)` on the RMI initial
reset path.

**Consequence for patch 2.** The "0 ms" row of the delay table is not really
0 ms: it is already 30 ms (`reset_delay_ms`) plus the SMBus version query.
Say that in the commit message, or the table looks like it contradicts itself.
And the first question will be "why not raise `reset_delay_ms` instead" — see
§4.2, which has both the prepared answer and an unresolved contradiction in our
own data that has to be settled first.

### 2.2 For patch 3 (doze interval) — no direct precedent exists

There is no prior commit that sets `power_management.doze_interval` from an x86
PnP-ID table. Verified plumbing (`drivers/input/rmi4/rmi_f01.c`):

- `rmi_f01.c:110` — "`@doze_interval`: controls the interval between checks for
  finger presence when the touch sensor is in doze mode, **in units of 10ms**"
  → our value 6 means **60 ms**; the commit message must say so.
- the only existing route in is device tree: `rmi_f01.c:367`
  `"syna,doze-interval-ms"` → `pdata->power_management.doze_interval = val / 10`.
  There is **no sysfs knob and no ACPI/DT node** for a PS/2-discovered SMBus
  companion, so a kernel-side table is the only mechanism. State this
  explicitly; it is the answer to "why not do this in userspace".
- gated by `f01->properties.has_adjustable_doze` (`rmi_f01.c:473`); written at
  probe (`:480`) and re-applied on every configuration pass (`:598`), which
  matches the claim in the patch.

The closest structural precedent is the original RMI4 platform-data plumbing by
Andrew Duggan / Benjamin Tissoires (2016), and Loic Poulain's unit fix.

**The Windows-INF evidence checks out exactly.** Verified in
`artifacts/windows-driver/extracted/code$GetExtractPath$/SynPD.inf`:

```
[AdjustFWDozeInterval_AddReg]
HKR,System\CurrentControlSet\Services\SynTP\Parameters,RMIDozeInterval,0x00010001,0x00000006
```

referenced from exactly eight InterTouch install sections
(`LENOVO_UWP_GROUP{13,14,15,16,17,18,25,29}_InterTouch_Inst`), which between
them are bound to exactly twelve `ACPI\LEN....` hardware IDs:

| section | hardware IDs |
|---|---|
| GROUP16 | `LEN040D` |
| GROUP15 | `LEN040E` |
| GROUP13 | `LEN040F` |
| GROUP17 | `LEN0410` |
| GROUP14 | `LEN0411` |
| GROUP25 | `LEN0417`, `LEN0418`, `LEN2064`, **`LEN2073`** |
| GROUP18 | `LEN2149` |
| GROUP29 | `LEN2161`, `LEN2162` |

That is precisely the list in patch `0002`, so the "twelve pad IDs, LEN2073
among them" claim is accurate and reproducible.

### 2.3 For patch 4 (`smbus_pnp_ids`) — plenty of precedent, one trap

Most recent additions, newest first:

| Commit | Subject | Author | Evidence in the message | Trailers |
|---|---|---|---|---|
| `7890fd28fd12` | Input: synaptics - enable InterTouch on Dell Inspiron 3521 | Shashwat Agrawal, 2026-06-26 | "Hardware: Dell Inc. Inspiron 3521 (board 06RYX8, BIOS A07), Synaptics fw 8.1 / board id 2382, firmware_id \"PNP: DLL0597 PNP0f13\"." | `Link: https://patch.msgid.link/...`; **no** Tested-by, **no** Cc: stable |
| `16ca52bc209f` | Input: synaptics - add LEN2058 to SMBus passlist for ThinkPad E490 | Nicolás Bazaes, 2026-05-13 | PNP ID, "Synaptics TM3471-020", explains what the absence causes, "Tested on ThinkPad E490 with kernel 7.0.5-zen1 and Arch Linux. RMI4 over SMBus is confirmed working without any kernel parameters." | `Assisted-by: Claude:claude-sonnet-4-6`, `Link: https://patch.msgid.link/...`, **`Cc: stable@vger.kernel.org`** |
| `a609cb4cc07a` | Input: synaptics - enable InterTouch on Dell Precision M3800 | Aditya Garg, 2025-05-07 | one sentence | `Reported-by:`, `Link:`, `Cc: stable` |
| `f04f03d3e99b` | Input: synaptics - enable SMBus for HP Elitebook 850 G1 | Dmitry Torokhov, 2025-05-07 | "The kernel reports that the touchpad for this device can support SMBus mode." | `Reported-by:`, `Link:`, `Cc: stable` |
| `496b7d2e5b93` | Input: synaptics - hide unused smbus_pnp_ids[] array | Arnd Bergmann, 2025-02-25 | W=1 warning | `Fixes: e839ffab0289` |

Note `Cc: stable@vger.kernel.org` on most of them — Dmitry adds it himself;
you may add it, it will not be held against you.

**The trap: this hardware family was on the list and was taken off.**

- `e4ce4d3a939d` "Input: synaptics - enable InterTouch on ThinkPad T14/P14s Gen
  1 AMD" (Matthew Haughton, 2022-03-20) added `LEN2064`.
- `2fd003ee8ade` "Input: synaptics - disable Intertouch for Lenovo T14 and P14s
  AMD G1" (**Mark Pearson, markpearson@lenovo.com**, 2022-09-24) removed it:

  > "Since intertouch was enabled for the T14 and P14s AMD G1 laptops there
  > have been a number of reports of touchpads not working well.
  > **Debugging this with Synaptics they noted that intertouch should not be
  > enabled as SMBUS host notify is not available on these laptops.**
  > ... Note - we are working with Synaptics to see if there is a better
  > solution, but nothing is confirmed as yet."

  Verified: neither `LEN2064` nor `LEN2073` is anywhere in the tree today
  (`grep -rn "LEN2073\|LEN2064" --include=*.c --include=*.h .` → no hits), and
  `smbus_pnp_ids[]` has `LEN2068 /* T14 Gen 1 */` (Intel) but nothing for the
  AMD variants.

  **This is the best thing that has happened to this series.** A Lenovo
  engineer, on the record, says the reason InterTouch was disabled on AMD
  ThinkPads is that SMBus Host Notify is not available — which is exactly what
  patch 1 provides. Cite `2fd003ee8ade` in the cover letter of *both* series and
  in patch 4's commit message. It converts "random quirk from a hobbyist" into
  "closing a four-year-old known gap".

- Also worth knowing as a caution: `3c44e2b6cde6` Revert "Input: synaptics -
  switch touchpad on HP Laptop 15-da3001TU to RMI mode" (Dmitry, 2022-12-16,
  `Cc: stable`, SUSE bugzilla link) — "because it causes loss of keyboard on HP
  15-da1xxx". PnP-ID additions do get reverted when they break siblings.

### 2.4 For patch 1 (i2c-piix4 ASF)

- **`0183eb8bb59d` "i2c: piix4: Add ACPI support"** (Jean Delvare, 2019-08-29;
  `Signed-off-by: Wolfram Sang <wsa@the-dreams.de>` — the era before Andi).
  Style notes: cites the AMD BKDG by document number ("52740 BIOS and Kernel
  Developer's Guide (BKDG) for AMD Family 16h Models 30h-3Fh Processors"),
  explains the adapter-ordering mismatch between Linux and the BKDG, credits
  prior work ("Based on earlier work by Andrew Cooks"), `Reported-by:`.
  **Delvare documents hardware claims against a named vendor document.** Do the
  same for the ASF register block.
- **Shyam Sundar S K's 2024 series** that carved the ASF driver out of piix4 —
  four commits, applied by Andi Shyti, all with
  `Reviewed-by: Andy Shevchenko <andriy.shevchenko@linux.intel.com>` and
  `Co-developed-by: Sanket Goswami`:
  - `9d9929e9929f` i2c: piix4: Change the parameter list of piix4_transaction function
  - `650e2c396a98` i2c: piix4: Move i2c_piix4 macros and structures to common header
  - `05d980046f5a` i2c: piix4: Export i2c_piix4 driver functions as library
  - `c509ebdb95ee` i2c: amd-asf: Add ACPI support for AMD ASF Controller

  This is the *shape* linux-i2c expects for a change of this size: **one logical
  step per patch, refactors first, new behaviour last**, and it reached v7 on
  the list (patchwork shows `[v7,1/8]` … `[v7,8/8]`,
  http://patchwork.ozlabs.org/project/linux-i2c/patch/20240923080401.2167310-7-Shyam-sundar.S-k@amd.com/).
  A 1000-line single patch will not be reviewed.

  `c509ebdb95ee` is also the commit that taught piix4 to stand aside for ASF:

  > "Currently, the piix4 driver assumes that a specific port address is
  > designated for AUX operations. However, with the introduction of ASF, the
  > same port address may also be used by the ASF controller. Therefore, a check
  > needs to be added to ensure that if ASF is advertised and enabled in ACPI,
  > the AUX port should not be configured."

  In the tree that is `SB800_ASF_ACPI_PATH "\\_SB.ASFC"` (`i2c-piix4.c:90`) and
  the `if (!is_asf)` guard at `i2c-piix4.c:1101`. On gondolin `\_SB.ASFC` does
  **not** exist — `dmesg.out` shows "Auxiliary SMBus Host Controller at 0xb20",
  so piix4 does create the aux adapter here. Patch 1 has to say how it interacts
  with that guard.

- **Host Notify precedent in a bus driver**: `7b0ed334b846` "i2c: i801: add
  support of Host Notify" (Benjamin Tissoires) — i801 calls
  `i2c_handle_smbus_host_notify()` from its interrupt handler, which is what
  patch 1 does. Later `f0c8f0ee0787` "i2c: i801: make FEATURE_HOST_NOTIFY
  dependent on FEATURE_IRQ" and `03a976c9afb5` "i2c: i801: Fix interrupt storm
  from SMB_ALERT signal" are the kind of follow-up such code attracts.
  The generic core function came from Alain Volmat, 2020:
  `i2c: smbus: add core function handling SMBus host-notify` +
  `i2c: stm32f7: Add SMBus Host-Notify protocol support`
  (http://patchwork.ozlabs.org/project/linux-i2c/patch/1596431876-24115-2-git-send-email-alain.volmat@st.com/,
  .../1596431876-24115-3-...), and Wolfram added
  `i2c: rcar: add HostNotify support`
  (http://patchwork.ozlabs.org/project/linux-i2c/patch/20200910091118.13434-1-wsa+renesas@sang-engineering.com/).

---

## 3. Reviewer profiles

**Sourcing caveat, please read.** `lore.kernel.org` and `patchwork.kernel.org`
are behind an Anubis proof-of-work gate and could not be fetched (neither by
shell nor by the fetch tool; the gate was *not* circumvented). The linux-input
quotations below were fetched from the **marc.info** linux-input archive
(`https://marc.info/?l=linux-input&m=<id>&w=4`), which prints the real
`Message-ID:` header; the `https://lore.kernel.org/linux-input/<msgid>/` URLs
are **reconstructed from those Message-IDs**. They are correct by construction
but were not re-fetched to confirm. Verify each link before quoting it in a
public posting. Commit-message quotations elsewhere in this document *were*
fetched directly from git.kernel.org and are exact.

### 3.1 Dmitry Torokhov — patches 2, 3, 4

Sole maintainer of `drivers/input/`, applies to `dtor/input.git`. He reviews
personally, replies tersely, and often just rewrites the patch for you.

**(a) He is hostile to retry loops and open-ended delays, but accepts one
bounded, sited, justified sleep.** The 2023 Jeffery Miller thread is the whole
story:

> "I am not really fond of adding random repeats in the code base. Andrew, do
> you know if the Synaptics device needs certain delay when switching to SMbus
> mode?"
> — https://lore.kernel.org/linux-input/ZFv5VkIzTEVwo2PI@google.com/ (2023-05-10)

> "I do not quite like putting these retries in RMI code. I wonder if we should
> not move the delay into psmouse_smbus_reconnect(): ... `/* Give the device
> time to switch to SMBus mode */ msleep(30);` or even factor it out into
> psmouse_activate_smbus_mode() ..."
> — https://lore.kernel.org/linux-input/ZLsajIm2qTcLE+O7@google.com/ (2023-07-21)

> "Applied, thank you."
> — https://lore.kernel.org/linux-input/ZMCra8UjEhJsEc9S@google.com/ (2023-07-26)

Still true in 2026, on a back-off loop in `synaptics_init()`:

> "Could you enable logging and see where the logic fails for you? I am not too
> keen on simply adding up to 8 seconds delay to the boot time."
> — https://lore.kernel.org/linux-input/ah96mP0RsFT8JNnC@google.com/ (2026-06-03)

**Read: he cares as much about *where* the sleep lives as about its length.** He
personally moved a delay out of RMI4 into psmouse in 2023 — and then, after the
revert, moved it back into RMI4 as `reset_delay_ms` (`5030b2fe6aab`). Patch 2
puts a second, larger delay into RMI4 next to that one. Expect to be asked why
it is not `reset_delay_ms`.

**(b) Quirk tables: he asks "why not userspace?" and "why not detect it?".**

> "Why does this need to be done in kernel instead of having a udev rule to
> toggle this through sysfs: /sys/devices/platform/i8042/serio0/power/wakeup"
> — https://lore.kernel.org/linux-input/5isz34mtyxezwrhmvtedygszhhnstsqa4dmcttb33p5dgw47st@3n6wswp2p6di/ (2025-06-17)

> "Quirks in the kernel should be used when they are needed for booting. When
> configuration can be delayed to [early] userspace then we should try to use
> userspace solutions. This way we are not wasting unswappable kernel memory."
> — https://lore.kernel.org/linux-input/lgedr3vr65tlmdt6p7gsd4cqlhgtadu5gj63ibwpzjuaxgrnwt@vlp3utkui3fh/ (2025-06-17)

> "You should submit a patch to systemd adding an entry for your key to
> hwdb.d/60-keyboard.hwdb based on DMI data for your device."
> — https://lore.kernel.org/linux-input/anQlOWU9YhC-2J-S@google.com/ (2026-08-06)

He also probes the *width* of a match before accepting it:

> "Is this board ID unique to T440p? Or it may be used in other devices as well?"
> — https://lore.kernel.org/linux-input/ajGaB1eqn8GeGW_A@google.com/ (2026-06-16)

and reflexively suggests RMI4/SMBus as the real fix for PS/2 problems:

> "I wonder if the device can work on SMbus/RMI4 mode and if it behaves better
> in RMI configuration?"
> — https://lore.kernel.org/linux-input/ah5iH8TPFnpbyT8a@google.com/ (2026-06-02)

> "I have not looked at the implementation yet, just a high-level question: What
> devices need this? Can they work in SMbus/RMI4 mode instead (which should
> alleviate bandwidth concerns)?"
> — https://lore.kernel.org/linux-input/an9ocXI6b7WEI8D2@google.com/ (2026-08-14)

**Read for patch 3:** the 12-ID table is the exposed one. The strongest defence
is the verified fact that **there is no userspace or DT route to
`doze_interval` for a PS/2-discovered SMBus companion** — no sysfs attribute, and
`syna,doze-interval-ms` only exists for DT-probed transports. Put that sentence
in the commit message.

**(c) Mechanical defects get bounced, tersely.**

> "Thank you for the patch. From checkpatch.pl: WARNING: Assisted-by expects
> 'AGENT_NAME:MODEL_VERSION [TOOL1] [TOOL2]' format"
> — https://lore.kernel.org/linux-input/agTso46UcMSGaIYx@google.com/ (2026-05-13)

> "The patch is whitespace-damaged."
> — https://lore.kernel.org/linux-input/ah5iH8TPFnpbyT8a@google.com/ (2026-06-02)

Small things he fixes himself rather than bouncing:
"If this works no need to resend, I'll fold on my side."
— https://lore.kernel.org/linux-input/aj28fvj34b4_VI3k@google.com/

**(d) Subject prefix.** He does not lecture about it; he just requires the house
style. `Input: <driver> - <lowercase summary>`. For `drivers/input/rmi4/*` the
established prefix is **`Input: synaptics-rmi4 - `** (`5030b2fe6aab`,
`8ff771f8c8d5`, `2593cd1189a2`). `Input: rmi_smbus - ` appears twice
(`5005fa144501` by Sang-Heon Jeon; one of Dmitry's own), so it is tolerated, but
prefer `synaptics-rmi4`. For `drivers/input/mouse/synaptics.c` it is
`Input: synaptics - `.

**(e) Evidence: `Link:` matters more than `Tested-by:`.** No message was found
where he demands a Tested-by, and it demonstrably is not required —
`7890fd28fd12` (DLL0597) was applied with none. What correlates with fast
acceptance is a concrete hardware-identity block plus a `Link:` to the report or
data. The 2023 delay patch's magic number was justified *by a Link to a vendor
message*.

**(f) Latency.** Trivial one-liners can land in hours: DLL0597 posted 2026-06-26
13:12, applied ~18:04. Anything with logic takes months and resends — the T440p
InterTouch change ran v1 (2026-06-16) → v3 → RESEND (08-18, 08-20) → "V2 RESEND"
(09-10) → applied (09-13)
(https://lore.kernel.org/linux-input/20260910164425.12832-1-rlarocque@disroot.org/).
A substantial `psmouse-smbus` rework posted 2026-06-04 still has no reply
(https://lore.kernel.org/linux-input/20260604131211.9442-1-rlarocque@disroot.org/).
**Budget months for patches 2 and 3; resend with `RESEND` after ~4 weeks of
silence.**

**(g) New: an automated reviewer now posts to linux-input.**
`sashiko-bot@kernel.org` ("Sashiko AI review") replies to most linux-input
patches within hours and Dmitry reads it — "Sashiko convinced me that using
mutex_trylock() ... Can you please try the following modification?"
(https://lore.kernel.org/linux-input/aj28fvj34b4_VI3k@google.com/). It picks on
commit-message *accuracy*: on the LEN2058 patch it flagged the claim that
psmouse "ignores" `synaptics_intertouch`, pointing out the passlist is only
consulted when `synaptics_intertouch == SYNAPTICS_INTERTOUCH_NOT_SET`
(https://lore.kernel.org/linux-input/20260514012222.48887C19425@smtp.kernel.org/).
Do not repeat that error in patch 4.

### 3.2 The linux-i2c side — patch 1

Sourcing for this subsection is stronger than for §3.1: the linux-i2c
public-inbox archive was cloned in full
(`git clone https://lore.kernel.org/linux-i2c/0`, 87,345 messages, 2008 →
2026-09) and the quotes below were read from the actual message bodies. The
`https://lore.kernel.org/linux-i2c/<msgid>/` URLs are the canonical form of
those Message-IDs.

#### Andi Shyti — **the** I2C maintainer since v7.2

`MAINTAINERS: hand over I2C to Andi Shyti`, Wolfram Sang, 2026-06-09:

> "After 13.5 years of maintaining I2C, it is finally time for me to move to
> other areas. So, I hereby transfer I2C maintainership to Andi Shyti."
> — thread https://lore.kernel.org/linux-i2c/aiswqff6pLnpfgBX@zenone.zhora.eu/T/#u

with, in the cover letter, "I decided to keep the split in MAINTAINERS between
the I2C core and the host drivers." Until v7.1 Andi sent `[GIT PULL] i2c-host …`
to Wolfram and Wolfram pulled to Linus; **since v7.2 Andi pulls straight to
Linus**. His branches, as named in his own "applied" mails: `i2c/i2c-host`
(next), `i2c/i2c-host-fixes`, `i2c/i2c-host-<version>` staging, and
`i2c/i2c-for-<version>`.

His habits, in the order they will hit this series:

1. **Anything that is not one logical change gets split.**
   > "the `dev_err_probe()` changes are not mentioned in the commit log. Can you
   > please split this patch in two, one for the `devm_reset_control` and one for
   > the `dev_err_probe`?"
   > — https://lore.kernel.org/linux-i2c/aYKj31hi1bF4wmsi@zenone.zhora.eu/

   > "Can you please put this part in a separate patch? They are logically
   > unrelated."
   > — https://lore.kernel.org/linux-i2c/aW-IlK4GXnJlVxpB@zenone.zhora.eu/

   > "Next time this can be on a separate patch as a preparatory patch to make
   > the review of this one a bit easier."
   > — https://lore.kernel.org/linux-i2c/aWeyT8gb8Z31S_V9@zenone.zhora.eu/

2. **Every change in the diff must be described in the log — he invokes bisect.**
   From his review of `i2c-piix4` itself:
   > "I'm not entirely happy with this change, or the others above. If someone
   > runs a git bisect, they would be confused by not seeing this change
   > described in the commit log. While it's true that the accepted line length
   > is now 100 characters, the 80-character limit is still preferred (and
   > personally, I prefer 80, though that's just my opinion)."
   > — https://lore.kernel.org/linux-i2c/xog6iyhri64cml2p53ncja6lxpt256eqceru4jxi7ee4esnb2j@xrbmeheorofv/

   He is also self-correcting: "I apologize for my earlier review of v4 … I'm
   sorry for requesting a new version. PS: I still prefer 80 characters per
   line."
   (https://lore.kernel.org/linux-i2c/oc2l6xnkdgeyv3i5iecd4j3nsny4p2deyjj22sx4vyq2vohnnc@ky5cqp5jmftn/)

3. **A claim in the commit message must be supported by the code.**
   > "If you make a claim in the commit message, I expect the code to support it."
   > — https://lore.kernel.org/linux-i2c/aljCGkhZEQHzZVSW@zenone.zhora.eu/
   > "If the commit message is leaving room for questions then you need to make
   > your commit message clearer."
   > — https://lore.kernel.org/linux-i2c/aljysQFgUHuVDAgK@zenone.zhora.eu/

4. **Naming: driver prefix, never a generic one — said to Shyam about piix4.**
   > "please don't use the `SMBUS_` prefix, this driver has its own prefix which
   > is PIIX4. I suggest calling these enums `PIIX4_SMBUS` and `PIIX4_SB800`."
   > — https://lore.kernel.org/linux-i2c/d4eai4r34suiuwkbpvubtvax2cuqafkiw7j64yi5h3axysxayg@vxe4kqbgjtvh/
   > "It's an unwritten rule that you should avoid using overly generic terms as
   > prefixes in your driver, like `smbus_read()` or `i2c_read()`."
   > — https://lore.kernel.org/linux-i2c/wncr3gah2qsakgvqj5c2rj6ovm5kja3di2ybqemd3t6i6v7hdv@arkg6mvhozxj/

   Our code already uses `piix4_asf_*` / `ASF_*`. Rename the bare `ASF*` macros
   to `PIIX4_ASF_*` before posting; the register-offset names (`ASFSTA`,
   `ASFSLVEN`, …) match `i2c-piix4.h`'s existing unprefixed style and can stay.

5. **checkpatch, and one kind of cleanup per patch.**
   > "Please, fix all the issues you find, including the checkpatch
   > warnings/errors (please keep one patch per kind of checkpatch fix). Last
   > thing, please keep bug fixes separate from…"
   > — https://lore.kernel.org/linux-i2c/ttsii2v6awu3ttglvyjgbk3ybpfy6tetht456uu2qmw4f7dzib@pcw5qfxcgchx/
   > "Please run checkpatch.pl before sending the patches."
   > — https://lore.kernel.org/linux-i2c/3wz36hrpicogoakqhmveppcrt6s52zmlcgjpio3wwpil3rdwdi@ft7tloqqf2zt/

6. **No "This patch …".**
   > "Please, don't start the commit log with 'This patch...', please use the
   > informative form."
   > — https://lore.kernel.org/linux-i2c/puotk7kms35fh3mgmsg24uxwadmcqjfr5iuijr2zknezcg7dtg@zlbrphpd6jn5/

7. **Subject and series mechanics; he uses `b4` and adds `Link:` himself.**
   > "Next time, please use the format '[PATCH v1 1/1]' instead of
   > '[v1,PATCH 1/1]'. Normally for the first version you can omit v1. For
   > single patches you don't need the 0/1 cover letter. Just send as [PATCH].
   > Please read Documentation/SubmittingPatches."
   > — https://lore.kernel.org/linux-i2c/ad7FOoevcOm0AxP8@zenone.zhora.eu/
   > "please, next time don't add the `Link:` tag here, I will add it myself via b4."
   > — https://lore.kernel.org/linux-i2c/iyefoqhlel7dwupjiidn2hcibkk6ooxcwpyjrb53f4tzup7r4v@2pl42nbgifof/

   He will also fix a title himself rather than make you resend:
   "You don't need to resend the patch. Because the changes are only in the
   commit log, I can take care of them."
   (https://lore.kernel.org/linux-i2c/ry4kzh4vr573ymutpjz5sgzmhosn3ekm3jatjy4yfyfm32eqit@cmp376je7viy/)

8. **He asks for RFC when a series is exploratory.**
   > "please, next time, to avoid confusion, make it an RFC; or, if the series is
   > in an advanced state with little things to improve, state it clearly in the
   > cover letter or after the '---' section."
   > — https://lore.kernel.org/linux-i2c/vjfddnykgeihdjlp5wzaeu4d4qn2boc22hufe2ceajt5wazznb@nysgwxk4ksdm/

9. **Etiquette:** he cites RFC 1855 at people repeatedly and expects trimmed
   quoting, no top-posting
   (https://lore.kernel.org/linux-i2c/bhm7ydwoed7lufnjzwtfipmqpbyc2phun5rh7cinwogbpmscp6@s2ulyfqstlro/).

10. On the ASF series he was light-touch and deferred to Andy:
    > "with the suggestions from Andy, I merged your patches to i2c/i2c-host."
    > — https://lore.kernel.org/linux-i2c/l2d5tndztzqlh6uox5os5zivxnka2x6x7tvqkwx2ue2mz7dajj@yw3aloojx2mz/

#### Andy Shevchenko — not a listed maintainer, but the de-facto gatekeeper here

**He is the person who will decide the shape of patch 1.** He reviewed
essentially every patch of Shyam's ASF series, Andi merged it "with the
suggestions from Andy", and — see §4.1 — he is the one who forced that series
out of `i2c-piix4.c` into a separate driver. What he objects to:

> "Now a question, why your case can't have a separate (platform) device driver?
> … Since you have a proper Device object in ACPI, it seems to me that you
> should do other way around, i.e. having a platform device driver for this ACPI
> device (based on _HID) and use piix4 as a library for it."
> — https://lore.kernel.org/linux-i2c/Ztsn8ZqWjY1P3qws@smile.fi.intel.com/ (2024-09-06)

> "Second issue with this is that now you require entire ACPI machinery for the
> previous cases where it wasn't needed. Imagine an embedded system with limited
> amount of memory for which you require +1Mbyte just for nothing. Look how the
> other do (hint: ifdeffery in the code with stubs)."
> — https://lore.kernel.org/linux-i2c/Ztr0alsDWrBodtyv@smile.fi.intel.com/

> "Please, start using inclusive non-offensive terms instead of old
> 'master/slave' terminology"
> — https://lore.kernel.org/linux-i2c/ZtsUZfxeE8Tqf1OD@smile.fi.intel.com/

That last one is why the merged driver says **target**. Our code is full of
`slave`, `ASF_SLV_*`, `piix4_asf_slave_arm()`, "slave listen state". **Rename
all of it to `target` before v1** — it is a guaranteed review round otherwise.
He also nitpicks hard (`(reg & BIT(3)) >> 3` → `? 1 : 0`, "Why signed?" on loop
indices) and asked Shyam twice for a **DSDT excerpt** to justify the ACPI
approach. Include ours.

#### Jean Delvare — still active on i2c-piix4, and he sets the splitting rule

Most recent piix4 review found: 2026-01-12,
https://lore.kernel.org/linux-i2c/20260112104449.26a4bf76@endymion/. Andi waits
for him — "Hi Jean, any thought on this? … Let's wait for Jean."
(https://lore.kernel.org/linux-i2c/aWo_DJRp_GwRG7p1@zenone.zhora.eu/, 2026-01-16).
**The series will stall without him.**

> "As a general rule, do not hesitate to split your changes into smaller steps
> whenever possible. Small changes are easier to review. The introduction of
> `SB800_PIIX4_SMB_MAP_SIZE` is independent from the rest of your changes, so it
> could go into a separate patch."
> — https://lore.kernel.org/linux-i2c/20210907183720.6e0be6b6@endymion/ (2021)

Other habits from the same review: "Now that this is defined, it should be used
consistently in the whole driver."; "It is a good opportunity to use 'SMBus'
instead of 'SMB' in these messages, as 'SMB' is ambiguous."; "Value of retval is
always 0 here, so you should hard-code it for clarity."; and a performance
objection — "While functionally correct, this change has a pretty high cost, as
you turn a single I/O operation into a function call + 2 tests + 2 or 3 I/O
operations." Each patch must build alone:

> "Maybe you build-tested the series as a whole but not individual patches? The
> series did build fine, as the missing curly brace was added back in a later
> patch."
> — https://lore.kernel.org/linux-i2c/20220215093742.3f3894c5@endymion.delvare/

**On sharing the FCH register window** — directly relevant if patch 1 extends
the region request:

> "I was thinking that maybe if the registers accessed by the two drivers
> (i2c-piix4 and sp5100_tco) were disjoint, then each driver could simply request
> subsets of the mapped memory. Unfortunately, while most registers are indeed
> exclusively used by one of the drivers, there's one register (0x00 =
> IsaDecode) which is used by both… If it's not possible then the only safe
> approach would be to migrate i2c-piix4 and sp5100_tco to a true MFD setup with
> 3 separate drivers… That's a much larger change though, so I suppose we'd try
> avoid it if at all possible."
> — https://lore.kernel.org/linux-i2c/20211105170550.746443b9@endymion/

He gives `Reviewed-by:` + `Tested-by:` once satisfied. On DMI quirk tables (from
the i801 Host Notify blacklist):

> "Please consider using `DMI_EXACT_MATCH` if possible, as it is faster. /
> Arrays passed to `dmi_check_system` must be terminated with an empty element."
> — https://lore.kernel.org/all/20180404225643.6b40782f@endymion/

#### Wolfram Sang — no longer the maintainer, but the author of the API we use

He wrote the "Gen 2" Host Notify path (bus driver + i2c slave interface) and
then used it in a bus driver himself. His rules while shaping it:

> "If it is not too much work for you, I think it makes sense to split the series
> into two, i.e. HostNotify and SMBusAlert parts."
> — https://lore.kernel.org/linux-i2c/20200630160500.GA2394@kunai/
> "I came to the conclusion that this code should be in `i2c-smbus.c`. Because it
> is SMBus only… Yes, that means that one needs to `select I2C_SMBUS` in the
> config, too."
> — https://lore.kernel.org/linux-i2c/20200725202733.GA946@kunai/
> "To be robust against multiple write messages in one transfer, we need to reset
> both, after STOP and when `I2C_SLAVE_WRITE_REQUESTED`… I used 'fallthrough' to
> avoid code duplication."
> — https://lore.kernel.org/linux-i2c/20200802191523.GA13339@kunai/

and his parting advice as maintainer, worth heeding for a 1000-line feature:

> "My suggestion: When in doubt, tend to be conservative in changing something.
> Fixes can always be backported, but regression are a real pain."
> — https://lore.kernel.org/linux-i2c/aigJlbxRhEdj1vBy@ninjato/
> "Please don't use 'fixes'. These changes are too intrusive to be added so late
> in the cycle."
> — https://lore.kernel.org/linux-i2c/aifz56BVLCdk-lDu@shikoro/

**Do not tag patch 1 `Fixes:`.** It is merge-window material.

#### Jean Delvare's older rules on Host Notify (Gen 1, 2015–2016)

> "As this is an SMBus feature, can't it go to `drivers/i2c/i2c-smbus.c`?"
> — https://lore.kernel.org/linux-i2c/20150629150035.4c027502@endymion.delvare/
> "You provide stubs for SMBus Host Notify support if `CONFIG_I2C_SMBUS` is not
> selected. There are no such stubs for SMBus Alert support… For consistency I'd
> rather provide stubs for all or none. My preference being for none."
> — https://lore.kernel.org/linux-i2c/20160718113721.2eaa86d3@endymion/

#### Shyam Sundar S K and Mario Limonciello (AMD)

They are not gatekeepers but they will comment, and their recorded positions
cut both ways — see §4.1. Shyam's on-record argument for keeping ASF *inside*
piix4 is our argument too; Mario's on-record suggestion is the opposite.

---

## 4. Self-review checklist per patch

### 4.1 Patch 1 — `i2c: piix4: ...` ASF SMBus Host Notify

**Read this first: our design was already proposed, and rejected, in 2024.**
Shyam Sundar's AMD ASF driver began life as a patch *to `i2c-piix4.c`* and was
pushed out of it by review:

| Version | Date | Title | Shape |
|---|---|---|---|
| v1 | 2024-08-22 | `[PATCH 0/5] Add ASF Controller Support to the i2c-piix4 driver` | `i2c-piix4.c` +381/-9 |
| v3 | 2024-09-06 | `[PATCH v3 0/5] … to the i2c-piix4 driver` | `i2c-piix4.c` +389/-10 |
| **v4** | 2024-09-11 | `[PATCH v4 0/8] Introduce initial AMD ASF Controller driver support` | **new `i2c-amd-asf-plat.c` + `i2c-piix4.h`** |
| v7 | 2024-09-23 | merged | |

v1 https://lore.kernel.org/linux-i2c/20240822142200.686842-1-Shyam-sundar.S-k@amd.com/ ·
v3 https://lore.kernel.org/linux-i2c/20240906071201.2254354-1-Shyam-sundar.S-k@amd.com/ ·
v4 https://lore.kernel.org/linux-i2c/20240911115407.1090046-1-Shyam-sundar.S-k@amd.com/
(v4 changelog: "Carve out a separate _HID driver for ASF / Export i2c_piix4
driver functions as library"). Seven versions in 32 days, ~108 messages.

**Andy Shevchenko forced it**, on grounds that apply verbatim to us:

> "Now a question, why your case can't have a separate (platform) device driver?
> … Since you have a proper Device object in ACPI, it seems to me that you
> should do other way around, i.e. having a platform device driver for this ACPI
> device (based on _HID) and use piix4 as a library for it."
> — https://lore.kernel.org/linux-i2c/Ztsn8ZqWjY1P3qws@smile.fi.intel.com/

> "Second issue with this is that now you require entire ACPI machinery for the
> previous cases where it wasn't needed. Imagine an embedded system with limited
> amount of memory for which you require +1Mbyte just for nothing. Look how the
> other do (hint: ifdeffery in the code with stubs)."
> — https://lore.kernel.org/linux-i2c/Ztr0alsDWrBodtyv@smile.fi.intel.com/

**Shyam's counter-argument — which is also ours, and was never rebutted, he just
conceded:**

> "ASF is a subset of SMBus. If a system has 3 SMBus ports, this change would
> allow one of the ports to handle ASF operations. — In the current i2c_piix4
> driver, the assumption is that the port address 0xb20 is designated for
> auxiliary operations, but this same port can also be used for ASF. This could
> lead to a scenario of port collision… As a result, users might encounter an
> error on platforms that support ASF: `SMBus region 0x%x already in use!` This
> is why I believe it would be more meaningful to integrate the ASF changes into
> the SMBus driver."
> — https://lore.kernel.org/linux-i2c/6a671a3b-d3fc-4a96-acf0-4c12a813fd1e@amd.com/

**And AMD's stated preference for our exact problem is the *other* direction.**
Mario Limonciello, 2024-10-10, replying to a P14s Gen 2 AMD user on this very
issue:

> "there was a very recent submission by Shyam (CC'ed) [1] that adds an ASF
> driver (which is an extension to PIIX4). By default it's going to bind to an
> ACPI ID that isn't present on your system (present on newer systems only) but
> the hardware for ASF /should/ be present even on yours. So I was going to
> suggest if you still are interested in this to play with that series and come
> up with a way to force using ASF (perhaps by a DMI match for your system) and
> see how that goes."
> — https://lore.kernel.org/linux-i2c/3409c03e-35fb-428a-9784-0069b63a83bb@amd.com/

**So the first review comment on patch 1 is near-certain to be "make
`i2c-amd-asf-plat.c` bind this platform instead."** You need a technical answer
ready on day one, in the cover letter, in its own titled section. Here is the
strongest one, verified locally:

> `i2c-amd-asf-plat.c` is a **platform driver**
> (`module_platform_driver(amd_asf_driver)`, `.acpi_match_table =
> amd_asf_acpi_ids`, `{ "AMDI001A" }`). Adding `"SMB0001"` to that table cannot
> work, because the ACPI core refuses to create a platform device for `SMB0001`
> **when it has `_CRS` resources** — `drivers/acpi/acpi_platform.c:155`:
> ```c
> 	{ACPI_SMBUS_MS_HID,  ACPI_ALLOW_WO_RESOURCES},	/* ACPI SMBUS virtual device */
> 	...
> 		if (match->driver_data & ACPI_ALLOW_WO_RESOURCES) {
> 			bool has_resources = false;
> 			acpi_walk_resources(adev->handle, METHOD_NAME__CRS,
> 					    acpi_platform_resource_count, &has_resources);
> 			if (has_resources)
> 				return ERR_PTR(-EINVAL);
> 		}
> ```
> introduced by **Andy Shevchenko himself** in `cefbd80bf52c` ("ACPI: platform:
> Ignore SMB0001 only when it has resources", `Reviewed-by: Andi Shyti`). On
> these machines `SMB0001` *does* carry `_CRS` (IO 0x0B20 length 0x20 +
> `IRQ (Level, ActiveLow, Shared) {7}`), so no platform device is ever created
> and no platform driver can bind. `drivers/i2c/busses/i2c-scmi.c` also already
> claims `ACPI_SMBUS_MS_HID` for the method-based CMI interface.

That is a fact Andy will accept or will tell you how to change — either way you
get a decision in one round instead of four. **Offer both options explicitly**:
(i) this patch, inside the PCI driver that already owns 0x0b20; or (ii) relax
the `acpi_platform.c` rule (or bind `SMB0001` some other way) and put the code
in `i2c-amd-asf-plat.c`. Ask which they want. Note that option (ii) is a change
to Rafael Wysocki's subsystem and would need its own series.

Use `ACPI_SMBUS_MS_HID` from `<acpi/acpi_drivers.h>`, never a literal
`"SMB0001"`.

**Someone already did this out of tree, and documented the blocker.** Miroslav
Bendík posted a working Host Notify hack for piix4 as a mail attachment (never
as a `[PATCH]`) in 2022:
https://lore.kernel.org/linux-i2c/c9b0b147-2907-ff41-4f13-464b3b891c50@wisdomtech.sk/
— "feature host notify is now implemented. Trackpoint / touchpad is working
pretty stable with high sample rate. But … i can't disable interrupts. It can
generate 10 000 interrupts/s in extreme case … Attached patch is full of hacks".
He later explained why he gave up, and it is **exactly the problem our
`module/README.md` describes**:

> "This entry defines the IRQ number, trigger, and polarity. However, the kernel
> ignores this entry and only uses the 'Interrupt Source Override' from the MADT
> table. … The interrupt trigger cannot be changed with irq_set_type because it
> lacks an `ioapic_ir_chip.irq_set_type` implementation … The biggest issue is
> interrupt support, which cannot be resolved with quirks alone. … Given the high
> potential for system instability with minimal gain, my requested feature may
> not be worth pursuing."
> — https://lore.kernel.org/linux-i2c/a77c83fb-45f2-4f77-846c-df441bc15436@gmail.com/ (2024-10-13)

Hans de Goede pointed at the existing escape hatch in the same thread:

> "Note that we already have a quirk table for this because this hits more
> interrupts in the legacy ISA interrupt range, see:
> …/drivers/acpi/resource.c#n659 — note that the MADT table is already alway
> skipped on AMD systems, but currently only for IRQs 1/12 which are the PS/2
> kbd + mouse IRQs."
> — https://lore.kernel.org/linux-i2c/788ae95e-12d4-441e-a417-d04049cb8e2e@redhat.com/

**This is the objection that killed the previous attempt, so it is the one to
answer best.** Our driver re-registers the GSI with the raw `_CRS` attributes
from inside the `_CRS` walk. Compare that against extending
`drivers/acpi/resource.c`'s existing AMD override table (which already special
cases IRQ 1/12) — that is very likely what reviewers will prefer, because it is
where the problem actually lives, and Hans has already named the file. Consider
splitting that into its own patch Cc'd to the ACPI maintainers. Also: Miroslav
explicitly volunteered — "I can maybe help with testing this new ASF driver on
older hardware without specific ACPI ID" — so Cc him for a `Tested-by:`.

Shyam pushed back on the whole idea twice; expect both again:
- "Note that SMBus controller do not support interrupt and the same has been
  documented in the datasheet: D14F0x03C [Interrupt Line] … 00h This module does
  not generate interrupts."
  (https://lore.kernel.org/linux-i2c/e345c93e-224d-425e-9ebf-efe02d6b6718@amd.com/)
  — already rebutted by Miroslav: "There is a ASFx0A ASFStatus with SlaveIntr
  bit. Pointing device on my machine triggers interrupt 7 and it can be cleared
  using ASF … It's possible to implement and enable I2C_CLIENT_HOST_NOTIFY flag
  on this hardware."
  (https://lore.kernel.org/linux-i2c/2130afb8-8bf7-49da-b349-e99194042865@gmail.com/)
  Our working machine is the proof; put the IRQ counters in the commit message.
- "if you want I2C_CLIENT_HOST_NOTIFY flag, then that has to come via a
  software_node property and I don't think we have near future thoughts about
  having this in BIOS."
  (https://lore.kernel.org/linux-i2c/3d6f7f74-3214-4c03-b352-a2a0d27ea42b@amd.com/)
  — this is wrong for our case and can be corrected politely: `I2C_CLIENT_HOST_NOTIFY`
  is set by `synaptics_create_intertouch()` on the `i2c_board_info` it passes to
  `psmouse_smbus_init()` (`synaptics.c:1808`), not by firmware. What is missing
  is the *adapter* functionality bit, not a client property.

**Use the blessed Host Notify API, and say that you are.** There are two
generations:
- Gen 1 (2015–16, Benjamin Tissoires, for i801): the bus driver calls
  `i2c_handle_smbus_host_notify()` directly.
  https://lore.kernel.org/linux-i2c/1437677718-7894-3-git-send-email-benjamin.tissoires@redhat.com/ ,
  https://lore.kernel.org/linux-i2c/1476360640-12901-7-git-send-email-benjamin.tissoires@redhat.com/
- **Gen 2 (2020, Alain Volmat + Wolfram Sang): the bus driver implements the
  i2c slave/target interface and registers
  `i2c_new_slave_host_notify_device()`.** Core helpers applied by Wolfram
  (https://lore.kernel.org/linux-i2c/20200909083950.GF2272@ninjato/), and
  **Wolfram then used it in a bus driver himself** — `i2c: rcar: add HostNotify
  support`,
  https://lore.kernel.org/linux-i2c/20200910091118.13434-1-wsa+renesas@sang-engineering.com/

  Copy `i2c-rcar`'s shape exactly: `select I2C_SLAVE` + `select I2C_SMBUS` in
  Kconfig (`I2C_PIIX4` already selects `I2C_SMBUS`); a flag set at probe when
  firmware describes the feature (rcar reads a DT property; ours is "SMB0001
  present and ASF claimed"); `func()` ORs `I2C_FUNC_SMBUS_HOST_NOTIFY` **only**
  when that flag is set; `i2c_new_slave_host_notify_device(adap)` after
  `i2c_add_adapter()` with an unwind label; `i2c_free_slave_host_notify_device()`
  **before** `i2c_del_adapter()`.

  Our code currently calls `i2c_handle_smbus_host_notify()` directly (Gen 1) and
  decodes the 3-byte message itself. **No one on linux-i2c has ever objected to
  a bus driver using the slave interface for Host Notify — the API exists for
  exactly this and the then-maintainer shipped a driver using it.** Switching to
  Gen 2 removes the whole "why are you hand-rolling this" class of objection.
  The honest counter-argument, if you keep Gen 1: the ASF block delivers a
  *complete* message into a 72-byte bank rather than byte-at-a-time slave
  events, so `i2c_slave_host_notify_cb()` (`i2c-smbus.c:266`, which counts
  `I2C_SLAVE_WRITE_RECEIVED` and fires on `I2C_SLAVE_STOP`) would have to be fed
  synthesised events. Note that `i2c-amd-asf-plat.c` already implements
  `.reg_target`/`.unreg_target` and advertises `I2C_FUNC_SLAVE`, so the
  synthesis is evidently practical on this hardware. **Decide this before v1 and
  justify whichever you pick in the commit message.**

  Counterweight to pre-empt: Host Notify has broken machines before —
  `i2c: i801: blacklist Host Notify on HP EliteBook G3 850`
  (https://lore.kernel.org/all/20180402123435.5587-1-jandryuk@gmail.com/).
  Make ours conditional on positive SMB0001/ASF detection and say how to turn it
  off.

**Terminology: `slave` → `target`.** Andy made Shyam do this and the merged
driver uses `target` throughout. Our diff is full of `ASF_SLV_*`,
`piix4_asf_slave_arm()`, `ASFSLVEN`, "slave listen state", "slave interrupt".
Keep the *register* names (`ASFSLVEN`, `ASFSLVSTA`) since they are the
datasheet's, but rename every function, variable, comment and log string to
`target`. Same for the `i2c_algorithm` hooks: the modern names are
`.reg_target`/`.unreg_target`.

**Split it.** `diff -u ref/i2c-piix4.c module/i2c-piix4.c` is 1013 added / 5
removed lines in one change, adding ~25 functions, a module parameter, a
file-scope singleton, two file-scope mutexes, new PM ops and `.shutdown`.
Precedents: Shyam's v7 8-patch series, and Terry Bowman's EFCH MMIO work (one
big patch in 2021, refused, 9 patches by v4/v5). Jean's rule:

> "As a general rule, do not hesitate to split your changes into smaller steps
> whenever possible. Small changes are easier to review."
> — https://lore.kernel.org/linux-i2c/20210907183720.6e0be6b6@endymion/

A reviewable split, each patch building and behaving on its own:

1. `i2c: piix4: return -EAGAIN on bus collision` — the `-EIO` → `-EAGAIN` change
   in `piix4_transaction()`. **Must be its own patch**: that function is
   `EXPORT_SYMBOL_NS_GPL(..., "PIIX4_SMBUS")` and is called by
   `i2c-amd-asf-plat.c`, so this changes another driver's behaviour. Justify from
   `Documentation/i2c/fault-codes.rst`: "EAGAIN — Returned by I2C adapters when
   they lose arbitration in master transmit mode: some other master was
   transmitting different data at the same time." Cc Shyam Sundar S K.
2. `i2c: piix4: claim the full ASF I/O window when firmware describes one` —
   `SMBIOSIZE` is 9 (`i2c-piix4.c:42`); ASF needs 0x20. Address Jean's
   sp5100_tco/region-sharing concern here.
3. `i2c: piix4: detect the ACPI SMB0001 ASF device` — the `_CRS` walk and
   resource plumbing, no behaviour change yet. Paste the DSDT excerpt.
4. (possibly) `ACPI: resource: honour the _CRS IRQ attributes for SMB0001 on
   AMD` — the trigger/polarity fix, Cc linux-acpi and Rafael, referencing
   `drivers/acpi/resource.c` and Hans de Goede's note.
5. `i2c: piix4: add ASF target arm/listen helpers`
6. `i2c: piix4: interlock aux master transfers with the ASF target`
7. `i2c: piix4: advertise SMBus Host Notify on the ASF adapter` — the payoff.
8. `i2c: piix4: suspend/resume and shutdown for the ASF target`
9. `Documentation: i2c: piix4: document ASF Host Notify` — extend the ACPI
   section added in 2024
   (https://lore.kernel.org/linux-i2c/fnjhtnnwuktkqj7ck7psc3e7potptogz2ioxw2lghkncd2ct7k@pmrk7angjkwd/).
   This pre-empts "where's the documentation?" and it is in Jean's MAINTAINERS
   section.

**Subject format.** `i2c: piix4: <lowercase description>`. Do not use the old
`i2c-piix4:` form (last seen 2019). Do not prefix `[v1,PATCH …]`; use
`[PATCH v2 3/9]` style. Do **not** add `Link:` yourself — Andi adds it via b4.
Do **not** tag anything `Fixes:` (Wolfram: "These changes are too intrusive to
be added so late in the cycle").

**Other things to fix before posting:**
- `static bool asf_host_notify = true; module_param(...)`. The file does have
  `force`/`force_addr` (`i2c-piix4.c:97,103`), so a param is not unprecedented,
  but a feature toggle invites "make it work correctly instead". The `asf_irq=N`
  override in `module/README.md` is worse — drop that one outright.
- The `#ifdef CONFIG_ACPI` twin implementation with `static inline` no-op stubs
  is, unusually, **exactly what Andy asked for** ("hint: ifdeffery in the code
  with stubs") — keep it, and say in the commit message that it follows his
  guidance so nobody re-litigates it. Note Jean's opposite preference on
  Host-Notify stubs ("My preference being for none") and be ready to discuss.
- **Do not add `depends on X86`.** `I2C_PIIX4` is `depends on PCI && HAS_IOPORT`
  since Mario's 2025 change; Shyam tried `X86` at v3 and Andy rejected it.
- checkpatch `--strict` on the diff reports exactly one CHECK ("Please use a
  blank line after function/struct/union/enum declarations", at the
  `static inline int piix4_asf_suspend(...)` stub). Fix it. Also re-wrap to 80
  columns — Andi says so twice.
- Rename bare `ASF_*` macros to `PIIX4_ASF_*` (Andi: "please don't use the
  `SMBUS_` prefix, this driver has its own prefix which is PIIX4").
- `RESUME-PLAN.md` records an unfixed defect: ~100 spurious hard-IRQ entries per
  Host Notify because the level line is held between the hard handler's ack and
  the threaded drain (fix: mask `ASF_SLV_INTR` in the hard handler). Given
  Miroslav's "10 000 interrupts/s" history on this exact hardware, **fix this
  before posting**, and put the measured interrupt rate in the commit message.

**Message contents, per patch:**
- Name the hardware: ThinkPad T14 Gen 2a (AMD Cezanne), PCI `1022:790b`, ACPI
  `SMB0001`, aux SMBus base `0xb20`, IRQ 7 level/active-low, and the DSDT
  excerpt.
- Cite a vendor document for each register touched, the way Jean cited the AMD
  BKDG by document number in `0183eb8bb59d`. If no public AMD document covers
  the ASF block, **say so** and name `i2c-amd-asf-plat.c` as the in-tree
  reference.
- Paste the working dmesg (from `dmesg.out`):
  ```
  piix4_smbus 0000:00:14.0: ASF SMBus slave (SMB0001) at 0x0b20, IRQ 7
  piix4_smbus 0000:00:14.0: SMBus Host Notify enabled via ASF (IRQ 7)
  rmi4_smbus 11-002c: registering SMbus-connected sensor
  rmi4_f01 rmi4-02.fn01: found RMI device, manufacturer: Synaptics, product: TM3471-030
  ```
- Say why an i2c patch matters: without `I2C_FUNC_SMBUS_HOST_NOTIFY` on some
  adapter, `psmouse_smbus_init()` (`psmouse-smbus.c:199`) and `rmi_smb_probe()`
  (`rmi_smbus.c:295`) refuse to attach and the pad stays on PS/2. Cite
  `2fd003ee8ade`, where a Lenovo engineer says exactly that.
- `Link:`/`Closes:` the two open reports (§6) and credit Miroslav Bendík, who
  did the logic-analyser captures proving the Host Notify packet is on the wire.
- Say how many machines were tested. Today the answer is one.

**The `\_SB.ASFC` interaction must be addressed.** `c509ebdb95ee` added a guard
(`i2c-piix4.c:90`, `:1101`) that skips aux-port setup when `\_SB.ASFC` exists.
On gondolin `\_SB.ASFC` is absent — `dmesg.out` shows "Auxiliary SMBus Host
Controller at 0xb20" — so the paths do not overlap here, but state the
interaction and keep that guard winning.

### 4.2 Patch 2 — `Input: synaptics-rmi4 - ...` resume settle delay

**Subject.** `Input: synaptics-rmi4 - let the device settle after the PS/2 reset
on SMBus resume` — good as written; `synaptics-rmi4` is the right prefix for
`drivers/input/rmi4/`.

**Fix before posting:**
- The `From:`/`Signed-off-by:` say `YOUR NAME`. Use a real legal name; a
  pseudonymous or initials-only Signed-off-by is refused under the DCO.
- checkpatch `--strict` is clean at the default 100-column limit but the comment
  `/* time the device needs after the PS/2 reset ... */` is 98 columns and trips
  `--max-line-length=80`. Wrap it.
- The patch has no `index` lines, so `get_maintainer.pl` on the file errors out
  and `git am` would not record a base. Regenerate with `git format-patch`.

**Message contents:**
- Say that the current 0 ms baseline is *not* 0: `reset_delay_ms = 30` is
  already spent inside `rmi_smb_enable_smbus_mode()` before the measurement
  point. Otherwise the table reads as though 0 ms and 30 ms are two different
  experiments when they are 30 ms and 60 ms.
- Name the machine, the pad and the sample sizes as the table already does, and
  add the measurement method in one line (`doze/early.sh`: reset, then a
  configuration pass after DELAY; median first-frame |delta| in device units,
  12 units/mm).
- `Link:` the two user reports this is adjacent to (§6).
- State that the 2023 T14s Gen1 AMD regression on this path
  (`b35726396390` → `e2cb5cc822b6`) was considered, and that the delay is only
  on the SMBus companion's own resume, not in the serio fast-reconnect path.

**Expected first-round objection #1: "use `reset_delay_ms`."** This is near
certain, because Dmitry wrote in `b35726396390` that it "would be better to
actually use "reset_delay" option defined in struct rmi_device_platform_data
and have RMI code handle it for SMBus transport as well", and then implemented
exactly that in `5030b2fe6aab`. A new hardcoded 300 ms constant three lines
below his `reset_delay_ms` msleep is the first thing he will see.

> **Unresolved contradiction in our own data — settle this before posting.**
> `RESUME-PLAN.md` records test **T1: "`reset_delay_ms` 30 → 250" → 7/8 still
> degraded**, while `doze/WAKE-JUMP.md` records fixB (`msleep(300)` after
> `rmi_smb_reset()`) → 7/7 clean. Both delays sit before the configuration pass,
> only ~50 ms apart, so on the face of it these two results conflict. Either
> (a) the threshold really is between 250 and 300 ms — then re-run T1 at 300 ms
> and report the narrow window, or (b) position matters (`reset_delay_ms` is
> consumed *before* `rmi_smb_get_version()` and the mapping-table rebuild, and
> those transfers are themselves what must be ≥300 ms old) — then say so, and it
> becomes the argument for a separate constant. Right now neither answer is
> supported by the notes, and a reviewer who asks "did you just try raising
> reset_delay_ms?" would get an answer that undercuts the patch.

Two prepared sub-answers regardless: `reset_delay_ms` is also consumed on the
*probe* path (`rmi_smb_enable_smbus_mode()` and `rmi_driver.c:866`), so raising
it to 300 costs 270 ms on every boot for every SMBus Synaptics pad, not just
these; and it is per-device platform data set by `synaptics.c`, so changing it
changes behaviour for every pad in `smbus_pnp_ids[]`.

**Objection #2: "why not in `psmouse_smbus_reconnect()`?"** Answer: because the
2023 attempt there was reverted precisely for adding delay to the serio fast
path (`b35726396390`), and because the event being waited on is the PS/2 reset
the touchpad takes from `psmouse_deactivate()`, which is observable only from
the companion's side.

**Objection #3: "poll instead of sleeping."** Have an answer ready. The pad
answers SMBus reads perfectly during the window — `rmi_smb_get_version()`
succeeds at 0 ms — so there is nothing to poll for; the fault is not readiness
but a firmware state that register reads do not expose (`doze/WAKE-JUMP.md`:
"Regdump byte-identical to the working state"). Say this explicitly; it is the
strongest single sentence in the patch.

**Objection #4: "300 ms on every resume."** Quantify: it is on the SMBus
companion's resume work, not the serio fast-reconnect path, and it is ~300 ms
once per system resume. Note that `rmi_smb_resume()` already sleeps
`reset_delay_ms` today.

### 4.3 Patch 3 — `Input: synaptics - ...` doze interval

**Subject.** The file's own convention is `Input: synaptics - <lowercase>`. The
current subject line says "Windows uses" in the filename and "Lenovo's driver
uses" in the `Subject:` header — make them agree. Suggest
`Input: synaptics - set the RMI4 doze interval on affected Lenovo touchpads`.

**Fix before posting:**
- Real name in `From:`/`Signed-off-by:`.
- **Table formatting.** Every existing PnP-ID table in `synaptics.c` is
  one ID per line with a `/* model */` comment. The patch packs 5–7 IDs per
  line with no comments. Reformat to the file's style and add the model each ID
  belongs to (or say "model unknown" where it is). Note also that the file
  writes hex digits lowercase (`LEN040f`, `LEN0402`) while the patch writes
  `LEN040F` — matching is case-insensitive (`psmouse_check_pnp_id()` uses
  `strncasecmp`), so this is cosmetic, but match the file.
- The table must stay inside the existing `#if IS_ENABLED(CONFIG_RMI4_SMB)`
  block or it re-breaks the W=1 build Arnd fixed in `496b7d2e5b93`. The patch
  does place it correctly — keep it that way.

**Message contents:**
- **State the unit.** `doze_interval` is in units of 10 ms
  (`rmi_f01.c:110`), so 6 = 60 ms. Nobody will do that arithmetic for you.
- Name the source file and the exact key, which is verifiable:
  `SynPD.inf`, section `[AdjustFWDozeInterval_AddReg]`,
  `HKR,System\CurrentControlSet\Services\SynTP\Parameters,RMIDozeInterval,0x00010001,0x00000006`,
  referenced from the eight `LENOVO_UWP_GROUP*_InterTouch_Inst` sections that
  cover exactly these twelve `ACPI\LEN....` IDs. The package is Lenovo `r1mst13w.exe`; the INF says `DriverVer=10/23/2022, 19.5.19.95`.
- **Pre-empt "do it in userspace":** there is no sysfs attribute for
  `doze_interval`, and the only other route in is the device-tree property
  `syna,doze-interval-ms` (`rmi_f01.c:367`), which does not exist for a
  PS/2-discovered SMBus companion on x86. Kernel-side is the only mechanism.
  This is the single most important sentence in the patch.
- Keep the measured numbers (20/20 taps vs 6/20; 0 pinches in 145 scroll
  episodes vs ~1 in 10) — that is exactly the evidence style Dmitry accepts.

**Expected objections:**
- *"Can't you read this from the device?"* Answer honestly: the pad reports
  `has_adjustable_doze` but its default (interval 3, wakeup threshold 45,
  holdoff 0) is what misbehaves, so there is nothing to detect — the correct
  value is a vendor-tuning choice, not a capability. Offer, if pushed, to key
  the table on the F01 product/board id (TM3471 / board id 3471) instead of PnP
  IDs.
- *"Is this ID unique to that machine?"* (his exact question in
  https://lore.kernel.org/linux-input/ajGaB1eqn8GeGW_A@google.com/). Be ready
  to defend all twelve, or trim to the IDs you can tie to a real model plus
  those with corroborating user reports — `LEN0411` (L14 Gen 1) has one, see §6.
- *"Untested on 11 of the 12."* True. Say so in the commit message rather than
  letting it be discovered: tested on LEN2073; the other eleven come from the
  vendor's own grouping. That is a defensible position (it is Lenovo's list,
  not ours) but only if stated.
- Be ready for it to be split: 6 = 60 ms for LEN2073 alone first, rest later.

### 4.4 Patch 4 — `Input: synaptics - enable InterTouch on ThinkPad T14/P14s Gen 2 AMD`

This is the easy one *mechanically* and the dangerous one *politically*.

**Copy the shape of `7890fd28fd12` verbatim.** Its accepted message was:
model, board, BIOS revision, Synaptics firmware version, board id, and the
literal `firmware_id` string. Ours:

```
Hardware: LENOVO ThinkPad T14 Gen 2a, PNP: LEN2073 PNP0f13,
Synaptics TM3471-030, board id 3471, fw 10.32.
```
(board id / fw from the user reports; `TM3471-030` and the DMI family
`ThinkPad T14 Gen 2a` from `dmesg.out` and `SHIP-PLAN.md`.)

**Do not repeat the LEN2058 commit-message error** that the review bot caught:
the passlist is only consulted when
`synaptics_intertouch == SYNAPTICS_INTERTOUCH_NOT_SET` (`synaptics.c:1829`);
it does not make `psmouse.synaptics_intertouch=1` be "ignored".

**The objection that will actually be raised, and it is a strong one:**
**a user has already tried this exact patch in public and reported it does not
work.** Rácz Máté, ThinkPad T14 Gen 2 AMD, BIOS R1MET62W, on 7.0-rc3:

> "2. Applied a local patch adding LEN2073 to the Synaptics SMBus whitelist ...
> Behaviour did not change; the touchpad still does not work properly."

with the identical diff hunk `+ "LEN2073", /* T14 Gen 2 */`.
Message-ID `CANkKV93zUMy3333wpsqyMjxOKecMh8-hdABVaG8sVfnKusaE8g@mail.gmail.com`,
https://lore.kernel.org/linux-input/CANkKV93zUMy3333wpsqyMjxOKecMh8-hdABVaG8sVfnKusaE8g@mail.gmail.com/
(fetched and verified via https://marc.info/?l=linux-input&m=177316536931240&w=4).
Thread opened 2026-02-22
(`CANkKV92bTD11PCXYzz60WSxcP-0UCM8xtnY4_WraEwQx6TMjaw@mail.gmail.com`);
Thorsten Leemhuis asked him to bisect
(`68d90523-33dc-451f-a825-72eaa1c4bcb8@leemhuis.info`) and the thread died.

Prepared answer, which is also the honest one and ties the whole project
together: **on a stock kernel the entry is inert**, because
`psmouse_smbus_init()` bails at
`if (!i2c_check_functionality(adapter, I2C_FUNC_SMBUS_HOST_NOTIFY))`
(`psmouse-smbus.c:199`) and no AMD FCH adapter advertises that bit — which is
exactly what Lenovo's Mark Pearson wrote when he removed `LEN2064` in
`2fd003ee8ade` ("intertouch should not be enabled as SMBUS host notify is not
available on these laptops"). Patch 4 is therefore **dependent on patch 1** and
must say so, with a `Link:` to the i2c series on lore.

**Consequence for sequencing:** do not post patch 4 as a standalone quick win
until patch 1 has at least been posted, or you will be asked to withdraw it —
and if it were applied it would re-create the 2022 situation that Lenovo
explicitly reverted. The tempting "one-liner that lands in five hours" is the
one patch here that should go *last*.
---

## 5. Submission mechanics

### Tooling state on this machine

- `scripts/checkpatch.pl` and `scripts/get_maintainer.pl` are present in
  `/home/andrew/Developer/others/linux`.
- **`b4` is not installed** (`pacman -Qq b4` → not found) and **`git send-email`
  is not present** on `PATH`. Install `b4` (AUR/pip) and
  `git-send-email` (the `perl-*` SMTP deps) before posting. `b4 prep`/`b4 send`
  is the current recommended flow and handles `Message-ID`, versioning and
  `Link:` trailers correctly.
- The reference tree is a **depth-1 shallow clone**, so you cannot
  `git format-patch` against it or produce a `base-commit:` line from it. Make a
  separate, non-shallow working clone for patch generation. Do not deepen or
  otherwise write to `/home/andrew/Developer/others/linux`.

### Base

Develop against `torvalds/linux` master (or `dtor/input.git#next` for the input
patches and `andi.shyti/linux.git#i2c/i2c-host` for the i2c one). Verified: both
existing patches apply cleanly to `7f063b2f17ea`:

```
$ patch -p1 --dry-run --forward < upstream/0001-*.patch   # clean
$ patch -p1 --dry-run --forward < upstream/0002-*.patch   # clean
```

and `ref/i2c-piix4.c` and `ref/rmi_smbus.c` are byte-identical to that tree, so
the ASF diff rebases without conflict.

### Commands

```sh
# 0. a real, non-shallow tree
git clone --filter=blob:none https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux-post
cd linux-post

# 1. one branch per series
git checkout -b input-t14-gen2a           # patches 2,3,4
git checkout -b i2c-piix4-asf-hostnotify  # patch 1 (split into ~9, see 4.1)

# 2. generate
git format-patch -v1 --cover-letter --base=auto -o out/input/ master..input-t14-gen2a
git format-patch -v1 --cover-letter --base=auto -o out/i2c/   master..i2c-piix4-asf-hostnotify

# 3. check EVERY patch, strictly
scripts/checkpatch.pl --strict --codespell out/input/*.patch
scripts/checkpatch.pl --strict --codespell out/i2c/*.patch

# 4. recipients (run on the generated patches, which DO have index lines)
scripts/get_maintainer.pl --no-git-fallback out/input/*.patch
scripts/get_maintainer.pl --no-git-fallback out/i2c/*.patch

# 5. send
b4 prep -n t14-gen2a-input -f master        # or: git send-email --annotate ...
b4 send --dry-run
```

`--base=auto` gives the `base-commit:` trailer that both maintainers' CI and
`b4 shazam` want. Do not hand-edit the generated files afterwards.

**Do not add `Link:` trailers to the i2c patches yourself** — Andi adds them via
b4: "please, next time don't add the `Link:` tag here, I will add it myself via
b4." (https://lore.kernel.org/linux-i2c/iyefoqhlel7dwupjiidn2hcibkk6ooxcwpyjrb53f4tzup7r4v@2pl42nbgifof/).
`Link:`/`Closes:` pointing at *bug reports* are still wanted; it is the
`Link:` to your own posting that he adds. On linux-input, Dmitry likewise adds
the `Link: https://patch.msgid.link/...` trailer himself.

Subject numbering: `[PATCH v2 3/9]`, not `[v2,PATCH 3/9]`
(https://lore.kernel.org/linux-i2c/ad7FOoevcOm0AxP8@zenone.zhora.eu/). A single
patch needs no `0/1` cover letter. Andi's tree branches are `i2c/i2c-host`
(next), `i2c/i2c-host-fixes`, and `i2c/i2c-for-<ver>`; since v7.2 he sends pull
requests straight to Linus.

### Which list gets what

| Series | To | Cc | List |
|---|---|---|---|
| `[RFC PATCH 0/9] i2c: piix4: SMBus Host Notify via the ASF target block on SMB0001 platforms` | Andi Shyti `<andi.shyti@kernel.org>`, Jean Delvare `<jdelvare@suse.com>` | **Andy Shevchenko `<andriy.shevchenko@linux.intel.com>`** (the de-facto gatekeeper — see §3.2/§4.1; Cc him on v1, not later), Shyam Sundar S K, Mario Limonciello `<superm1@kernel.org>`, Hans de Goede, Wolfram Sang, Miroslav Bendík `<miroslav.bendik@gmail.com>` and William Luther Zambo `<wlz.litiaina@gmail.com>` (volunteer testers), plus Dmitry Torokhov / linux-input for the payoff | `linux-i2c@vger.kernel.org`, `linux-kernel@vger.kernel.org` |
| `[PATCH 0/3] Input: fix the Synaptics InterTouch touchpad on AMD ThinkPads` | Dmitry Torokhov | Benjamin Tissoires, Mark Pearson `<markpearson@lenovo.com>` | `linux-input@vger.kernel.org`, `linux-kernel@vger.kernel.org` |

Cc'ing **Mark Pearson at Lenovo** on the input series is worth doing: he is the
author of `2fd003ee8ade`, which disabled InterTouch on this hardware family
because Host Notify was missing, and he wrote "we are working with Synaptics to
see if there is a better solution". A `Tested-by:` or even an ack from him would
carry the whole series. Likewise Cc the two reporters (Rácz Máté, Nolan
Provencher, and the L14 Gen 1 reporter) so they can supply `Tested-by:`.

### Cover letters

- **i2c series**: mandatory (9 patches). It needs a **titled section answering
  "why not `i2c-amd-asf-plat.c`?"** — that question is guaranteed, because Andy
  Shevchenko asked it of Shyam in 2024 and Mario Limonciello suggested exactly
  that approach for this hardware (§4.1). The section should: acknowledge the
  v1→v4 history of Shyam's series; state the `acpi_platform.c:155` reason a
  platform driver cannot bind an `SMB0001` node that has `_CRS`; restate Shyam's
  own aux-port-collision argument; and *ask* which shape they want.
  Also required: what ASF is and why the aux adapter is the ASF controller; the
  `SMB0001` DSDT excerpt; the IRQ trigger/polarity problem and how it is handled
  (with a pointer to Miroslav Bendík's 2024 analysis and Hans de Goede's
  `drivers/acpi/resource.c` note); which Host Notify API generation is used and
  why; dmesg before/after; measured interrupt rate; a `Link:` to the input
  series; and the number of machines tested (currently one — say so).
- **input series**: 3 patches, so a cover letter is expected. It must say that
  patches 2 and 3 are independently useful but patch 4 is inert without the i2c
  series, with a `Link:`, and that patch 4 re-enables a family that
  `2fd003ee8ade` deliberately disabled and why that is now safe.
- Single patches (if you split further) do not need one.

### RFC or not?

**Yes — send the i2c series as `[RFC PATCH 0/9]` first.** Reasons, in order:
1. The architecture question is not merely open, it was **already decided
   against this shape once** (§4.1): Shyam's ASF support started inside
   `i2c-piix4.c` at v1–v3 and Andy Shevchenko made him carve it into a separate
   `_HID` platform driver by v4. Posting a non-RFC series that re-does what was
   rejected reads as not having done the homework. An RFC that *opens* with that
   history, and with the `acpi_platform.c` reason a platform driver cannot bind
   `SMB0001`, reads as the opposite.
2. Andi explicitly asks for this when a series is exploratory: "please, next
   time, to avoid confusion, make it an RFC"
   (https://lore.kernel.org/linux-i2c/vjfddnykgeihdjlp5wzaeu4d4qn2boc22hufe2ceajt5wazznb@nysgwxk4ksdm/).
   Wolfram sent even `i2c: rcar: add HostNotify support` as an RFC first.
3. The Gen-1 vs Gen-2 Host Notify API choice (direct
   `i2c_handle_smbus_host_notify()` vs `i2c_new_slave_host_notify_device()`) is
   a design decision worth asking about rather than guessing.
4. The GSI re-registration with raw `_CRS` attributes is intrusive, and it is
   the precise point at which the previous community attempt gave up
   (Miroslav Bendík, 2024: "The biggest issue is interrupt support, which cannot
   be resolved with quirks alone"). Ask whether it belongs in
   `drivers/acpi/resource.c` instead, where Hans de Goede has already pointed.
5. It is tested on exactly one machine, by one person, with no public vendor
   document cited for the register block.
6. ~~`RESUME-PLAN.md` still lists an unfixed defect in this code (the ~100
   spurious hard IRQs per Host Notify).~~ Fixed 2026-09-18: they were host
   transaction-completion interrupts in master mode, acked in the hard
   handler as `i2c-amd-asf-plat.c` does (see RESUME-PLAN "Also pending").
   Given Miroslav's "10 000 interrupts/s" history on this hardware, the
   cover letter should quote the measured rate: about five interrupts per
   frame, none idle.

Do **not** send the input patches as RFC — Dmitry applies ordinary patches and
RFC just delays him. Patch 2 and 3 are normal `[PATCH]`s.

### Ordering

1. ~~Fix the known ASF IRQ storm~~ (done 2026-09-18); rename `slave` → `target` throughout; re-run the
   `reset_delay_ms` 250 vs 300 ms experiment (§4.2) so patch 2's story is
   airtight.
2. **Reply to the two open threads first** (William Luther Zambo's 2026-09-01
   L14 Gen 1 AMD report on linux-i2c/linux-input, which explicitly asks "Is
   support for Host Notify on AMD FCH 1022:790b feasible using the SMB0001 ACPI
   resource (0x0b20 / IRQ 7)?" and offers to test; and the P14s Gen 2 thread).
   Answering a question someone actually asked is the cheapest possible way to
   arrive on the list with standing, and it buys `Tested-by:` and `Closes:`.
3. Post the i2c RFC. Expect a design answer in 1–3 weeks.
4. Post input patches 2 and 3 in parallel — they do not depend on the i2c
   outcome and can be reviewed independently. (Patch 2 *is* observable only on
   a machine that has SMBus working, which today means with the out-of-tree ASF
   module; disclose that.)
5. Post patch 4 only once the i2c series is applied or clearly on its way, with
   a `Link:` to it.
6. Resend with `RESEND` after ~4 weeks of silence on linux-input; linux-i2c
   patches are tracked in patchwork.ozlabs.org and are more likely to get a
   state than a reply.
---

## 6. Already upstream, or in flight, that changes the plan

Checked in the reference tree at `7f063b2f17ea` and against
`patchwork.ozlabs.org` (linux-i2c) and the marc.info linux-input archive.
`lore.kernel.org` and `patchwork.kernel.org` could not be queried directly (§3).

### Nothing duplicates our four patches

- **Host Notify on AMD via piix4** — nothing, confirmed against the **complete**
  linux-i2c public-inbox archive (87,345 messages, 2008 → 2026-09, cloned with
  `git clone https://lore.kernel.org/linux-i2c/0`): every hit for the ASF
  register names `ASFSLVSTA`/`ASFDATABNKSEL` is Shyam's 2024 series or its
  follow-up fixes, and every hit for `HOST_NOTIFY` together with `piix4` is
  discussion, never a patch. **This would be the first submission of the
  feature.** The only code that has ever existed is Miroslav Bendík's
  out-of-tree hack, posted as a mail attachment in 2022, never as a `[PATCH]`:
  https://lore.kernel.org/linux-i2c/c9b0b147-2907-ff41-4f13-464b3b891c50@wisdomtech.sk/
  ("feature host notify is now implemented. Trackpoint / touchpad is working
  pretty stable with high sample rate. But … i can't disable interrupts. It can
  generate 10 000 interrupts/s in extreme case … Attached patch is full of
  hacks"). Credit him.
  In-tree confirmation: `grep` of the tree finds
  `I2C_FUNC_SMBUS_HOST_NOTIFY` / `i2c_handle_smbus_host_notify` only in
  `i2c-i801.c`, `i2c-rcar.c`, `i2c-stm32f7.c`, the i2c core, and the two
  consumers (`psmouse-smbus.c`, `rmi_smbus.c`). `i2c-amd-asf-plat.c` does **not**
  implement Host Notify: `amd_asf_func()` returns
  `I2C_FUNC_SMBUS_WRITE_BLOCK_DATA | I2C_FUNC_SMBUS_BLOCK_DATA |
  I2C_FUNC_SMBUS_BYTE | I2C_FUNC_SMBUS_PEC | I2C_FUNC_SLAVE`. A
  patchwork.ozlabs.org search of linux-i2c for `piix4`, `asf`, `host notify` and
  `SMB0001` returns nothing resembling this work.
- **`LEN2073`** — not in the tree
  (`grep -rn "LEN2073\|LEN2064" --include=*.c --include=*.h` → no hits) and no
  patch has ever been posted (marc.info linux-input search for `LEN2073` returns
  only bug reports, no patches).
- **`rmi_smb_resume()`** — untouched since `5030b2fe6aab` (2023-10-13). The most
  recent change to `rmi_smbus.c` is `5005fa144501` "Input: rmi_smbus - remove
  conditional return with no effect" (Sang-Heon Jeon, 2026-07-30), a Coccinelle
  cleanup in `smb_block_read()` that does not touch the resume path, so patch 2
  still applies.
- **`smbus_pnp_ids[]`** — last touched by `7890fd28fd12` (DLL0597, 2026-06-26).

### Things that do change the plan

1. **`2fd003ee8ade` (2022-09-24, Mark Pearson, Lenovo) is the frame for the
   whole story.** InterTouch was enabled on T14/P14s Gen 1 AMD (`e4ce4d3a939d`,
   `LEN2064`) and removed six months later because, per Synaptics, "SMBUS host
   notify is not available on these laptops". Patch 1 supplies exactly that.
   Lead with this in both cover letters; it turns the series from a personal
   quirk into the fix for a documented four-year-old regression. It also means
   `LEN2064` should probably be *restored* to `smbus_pnp_ids[]` alongside
   `LEN2073` once patch 1 lands — consider making patch 4 cover both, and Cc
   Mark Pearson.

2. **A public negative result on exactly our patch 4.**
   `https://lore.kernel.org/linux-input/CANkKV93zUMy3333wpsqyMjxOKecMh8-hdABVaG8sVfnKusaE8g@mail.gmail.com/`
   (Rácz Máté, 2026-03-10; verified at
   https://marc.info/?l=linux-input&m=177316536931240&w=4) — he added `LEN2073`
   to `smbus_pnp_ids[]` on 7.0-rc3 and reported no change. Must be addressed in
   the commit message (§4.4). Thread start:
   `CANkKV92bTD11PCXYzz60WSxcP-0UCM8xtnY4_WraEwQx6TMjaw@mail.gmail.com`
   (2026-02-22); Thorsten Leemhuis' bisect request:
   `68d90523-33dc-451f-a825-72eaa1c4bcb8@leemhuis.info` (2026-03-09).

3. **Two unanswered user reports that patch 3 (doze) would fix** — use them as
   `Link:` evidence and as `Tested-by:` candidates:
   - `https://lore.kernel.org/linux-input/b2d0af40-876e-4a2d-99a2-236b583e9497@gmail.com/`
     — "[BUG] Touch-pad is stuck on slow poll rate — Thinkpad P14s Gen 2 (AMD)",
     Nolan Provencher, 2025-06-26, Ryzen 5 Pro 5650U, `PNP: LEN2073 PNP0f13`.
     Verified at https://marc.info/?l=linux-input&m=175096229031062&w=4. Never
     answered.
   - **The best single piece of third-party evidence for patch 1**, verified:
     "ThinkPad L14 Gen 1 AMD: Synaptics LEN0411 cannot use RMI4/SMBus and falls
     back to slow SynPS/2", William Luther Zambo, 2026-09-01, message-id
     `CAFw-f_1BYzUnXf=eD2sVe7RrJrtzwDrMrbmmPZvGKvYB53EUJQ@mail.gmail.com`,
     https://lore.kernel.org/linux-input/CAFw-f_1BYzUnXf=eD2sVe7RrJrtzwDrMrbmmPZvGKvYB53EUJQ@mail.gmail.com/
     (fetched at https://marc.info/?l=linux-input&m=178825238688233&w=4).
     Different machine, different user, same chipset — and he has already done
     the diagnosis for us:

     > "Therefore this does not appear to be an InterTouch allowlist or kernel
     > parameter issue." … "The AMD PIIX4 adapters expose SMBus operations but
     > no Host Notify: … SMBus Host Notify no" … "The Lenovo DSDT explicitly
     > exposes an SMBus device at 0x0b20 with IRQ 7: `Device (SMB1) { Name
     > (_HID, "SMB0001") … IO (Decode16, 0x0B20, 0x0B20, 0x20,`"

     `LEN0411` is *already* in `smbus_pnp_ids[]` (added by `c1f342f35f82`) and
     still does not work on the AMD variant — which is independent proof that
     patch 4 alone is not the fix and patch 1 is the missing piece. It is also
     the same pad family as ours (board id 3471, fw 10.32, id 0x1e2a1), and
     `LEN0411` is in the twelve-entry doze list, so this reporter is a strong
     `Tested-by:` candidate for patches 1 and 3 alike. **Reply to this thread**
     rather than starting a new one; it is unanswered.

4. **A 2021 report with the SMB0001 `_CRS` dump for this exact chipset** —
   "Wrong piix4_smbus address / slow trackpoint on Thinkpad P14s gen 2 (AMD)",
   Miroslav Bendik, 2021-12-11, message-id
   `CAPoEpV0ZSidL6aMXvB6LN1uS-3CUHS4ggT8RwFgmkzzCiYJ-XQ@mail.gmail.com`
   (verified at https://marc.info/?l=linux-input&m=163922483826378&w=4). It
   contains the DSDT `Scope (_SB.PCI0) { Device (SMB1) { Name (_HID, "SMB0001")
   ... }` excerpt and shows piix4 reporting base `0xff00`/`0xff20` instead of
   `0xb20` on some BIOSes. Good `Link:` for patch 1, and a warning that the
   `_CRS`-vs-detected-base match in `piix4_asf_detect()` must cope with that
   case (fall back cleanly, do not claim the window).

5. **In flight on `i2c-piix4.c`, unreviewed, touching the same I/O range**:
   "i2c: piix4: Add ACPI region conflict allowlist for Gigabyte X870 EAGLE
   WIFI7" (Guntis Belkovskis, 2026-08-12, state `new`),
   http://patchwork.ozlabs.org/project/linux-i2c/patch/20260812204220.74726-1-guntis.belkovskis@gmail.com/
   — a DMI allowlist that lets piix4 bind when `acpi_check_region()` fails on
   0x0B00/0x0B20. Also still open: "i2c: piix4: Add support for I2C block data
   transactions" (Qing Chang, 2025-12-09, `needs-review-ack`). Neither conflicts
   semantically, but both may cause textual conflicts and both show that
   **`i2c-piix4.c` patches can sit unreviewed for months**. Budget accordingly.

6. **In flight on `synaptics.c`, textually adjacent**: "[PATCH] Input:
   synaptics - enable Synaptics InterTouch for ThinkPad X270" (Mark Alexander,
   2026-06-22, adds `"LEN2046", /* X270  */` two lines from where `LEN2073`
   goes), message-id `1782164489-csup-4866@bionic.bloovis.com`,
   https://marc.info/?l=linux-input&m=178216459232937&w=4 — no reply as of the
   last archive entry. Expect a trivial textual conflict; nothing semantic.

7. **Precedent worth reading before writing patch 4**: `c1f342f35f82`
   "Input: psmouse - enable Synaptics InterTouch for ThinkPad L14 G1"
   (José Pekkarinen, `LEN0411`). Posted 2023-10-08
   (`20231008080129.17931-1-jose.pekkarinen@foxhound.fi`), self-pinged
   2023-10-16 and 2023-10-31, RESENT 2023-11-14, applied 2023-11-15, then
   AUTOSEL'd to stable 6.1 and 6.6 by Sasha Levin. Its evidence was simply the
   before/after dmesg — and the "after" log still said
   "SMbus companion is not ready yet", which nobody caught. Two lessons: the
   bar for evidence on these is low, and *this list has previously accepted a
   PnP-ID addition that did not actually work on AMD hardware.* Do not be the
   second one.

8. **Jean Delvare's address changed**: MAINTAINERS says `jdelvare@suse.com`.
   Older commits show `@suse.de`. Use the MAINTAINERS address.

9. **Wolfram Sang is not the i2c maintainer.** `MAINTAINERS: hand over I2C to
   Andi Shyti` landed 2026-06-09 ("After 13.5 years of maintaining I2C, it is
   finally time for me to move to other areas."), thread
   https://lore.kernel.org/linux-i2c/aiswqff6pLnpfgBX@zenone.zhora.eu/T/#u .
   Since v7.2 Andi sends I2C pull requests to Linus directly. Addressing Wolfram
   as the maintainer would be a visible sign of stale research; Cc him as the
   author of the Host Notify slave API instead.

10. **The single biggest change to the plan: patch 1's architecture was already
    argued out on this list in 2024, and the outcome went against putting ASF in
    `i2c-piix4.c`** — see §4.1. This does not make the patch unpostable (the
    `acpi_platform.c` rule gives a genuine reason `SMB0001` is different from
    `AMDI001A`), but it does mean the series must open by acknowledging that
    history. Discovering it after posting would be much worse than citing it
    first.

### Not verified

- Whether any of the reconstructed `lore.kernel.org` URLs in §3 resolve
  (the archive was unreachable; Message-IDs are real, taken from marc.info).
- Whether the `i2c-amd-asf-plat.c` register sequences our ASF code follows are
  covered by a public AMD document. If they are not, the commit message must say
  the in-tree driver is the reference.
- The SynPD.inf package version/date (the extracted tree is
  `artifacts/windows-driver/extracted/code$GetExtractPath$/`, from
  `r1mst13w.exe`) — **verified**: `DriverVer=10/23/2022, 19.5.19.95`, `Provider` Synaptics, `Copyright (c) 1996-2018, Synaptics Incorporated`.
