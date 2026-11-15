# fujinet-network for the CPC + M4

The network functions of FujiNet's [fujinet-lib](https://github.com/FujiNetWIFI/fujinet-lib)
for the **Amstrad/Schneider CPC** with the **M4 board**, in C for SDCC. A program written for
the FujiNet on the Atari, C64 or Apple II uses the same calls on the CPC:

```c
#include "fujinet-network.h"

network_init();
network_open("N1:TCP://bbs.example.org:6502/", OPEN_MODE_RW, OPEN_TRANS_NONE);
network_write("N1:", "HELLO\r\n", 7);
network_status("N1:", &waiting, &connected, &err);
n = network_read_nb("N1:", buf, waiting);
network_close("N1:");
```

Underneath it uses the M4 library of
[development-kit-cpc-and-m4](https://github.com/joergr72idb/development-kit-cpc-and-m4).
Own code with the same names, constants and behaviour - no fujinet-lib code.

## What works

| | |
|---|---|
| `network_init` | finds the M4 (`FN_ERR_NO_DEVICE` without one) |
| `network_open` | `Nx:TCP://host:port/`, host name (M4 DNS) or a.b.c.d, waits for the connection |
| `network_status` | bytes waiting (up to 256 per unit), connected, error (136 = end of data) |
| `network_read_nb` | waits for at least one byte, returns what is there |
| `network_read` | waits for all requested bytes or the end of the connection |
| `network_write`, `network_close`, `network_unit`, `nw_status` / `fn_network_*` | |

Units `N1:`-`N4:` (`N:` = `N1:`), the M4's four sockets. **Not yet:** other protocols (HTTP,
TNFS, ...), listening for connections, UDP, translation modes other than `OPEN_TRANS_NONE`,
JSON. They return `FN_ERR_BAD_CMD` with `fn_network_error` = 146 (not implemented).

## Build and test

Needs the CPC development kit next to this folder (its setup script run).

```sh
make            # build/fujinet-network.rel + build/m4.rel
make test       # test program FNTEST in the kit's emulator against test/testserver.py: PASS/FAIL
```

Your program: compile with `-I include -I <kit>/lib/m4`, link `build/fujinet-network.rel` and
`build/m4.rel`.

The test covers: 3000 bytes received the usual FujiNet way (status, then `read_nb`) and the end
of the connection, 2000 bytes sent in pieces of 1-1400 bytes, a blocking read of slowly arriving
data, a host name, two units at once, re-opening a unit, a refused connection, an unknown host
and bad devicespecs.

## Used by

- [Retro Game Battle](https://github.com/joergr72idb/retro-game-battle): its CPC client shares the
  protocol code (`clients/common/rgb_core.c`) with the Atari, C64 and Apple II clients, which use
  fujinet-lib. Retro Game Battle carries this library as a git subtree in `lib/fujinet-network-cpc`.

## Tested (2026-11-15, emulator only)

CPCSyntaxError (the kit's, with M4 emulation) on Ubuntu 26.04: `make test` passes. Not yet on a
real CPC + M4.

## Next goal: a FujiNet for the Schneider CPC

This library is a first step. What I'm interested in is a real FujiNet for the Schneider/Amstrad
CPC: hardware based on the work and design of Duke's M4 board, but with an ESP32, the chip
[FujiNet](https://fujinet.online) runs on. The CPC would then get the FujiNet firmware and its
services like the other machines, and programs using this API would run on it without changes.

So far this is only an idea - nothing is built yet. If you're working on something similar or
would like to help, please open an issue.

## Licence

GPL-3.0-or-later, see [LICENSE](LICENSE).

Why GPL and not MIT: the point of this library is that one program builds for the Atari, C64 and
Apple II with FujiNet's fujinet-lib and for the CPC with this one. fujinet-lib is GPL-3, so those
programs are GPL-3 on the other machines anyway. The same licence here keeps the CPC version under
the same terms and lets the code go into the FujiNet project later if that is ever wanted.
