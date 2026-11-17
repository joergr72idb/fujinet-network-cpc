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

HTTP works the same way:

```c
network_open("N1:HTTP://example.org/data.txt", OPEN_MODE_HTTP_GET, OPEN_TRANS_NONE);
network_status("N1:", &waiting, &connected, &err);   /* sends the request; 170 = 404 */
n = network_read_nb("N1:", buf, waiting);            /* the body, then err 136 at the end */
network_close("N1:");
```

Underneath it uses the M4 library of
[development-kit-cpc-and-m4](https://github.com/joergr72idb/development-kit-cpc-and-m4).
Own code with the same names, constants and behaviour - no fujinet-lib code.

## What works

| | |
|---|---|
| `network_init` | finds the M4 (`FN_ERR_NO_DEVICE` without one) |
| `network_open` | `Nx:TCP://host:port/` or `Nx:HTTP://host[:port]/path`, host name (M4 DNS) or a.b.c.d, waits for the connection |
| `network_status` | bytes waiting (up to 256 per unit), connected, error (136 = end of data) |
| `network_read_nb` | waits for at least one byte, returns what is there |
| `network_read` | waits for all requested bytes or the end of the connection |
| `network_write`, `network_close`, `network_unit`, `nw_status` / `fn_network_*` | |
| TCP server | `Nx:TCP://:port/` listens; `network_accept`, `network_close_client` |
| Translation | `OPEN_TRANS_CR`, `_LF`, `_CRLF`: line ends to and from the CPC's CR (not `_PET`) |
| JSON | `network_json_parse`, `network_json_query` (documents up to 2 KB) |
| HTTP methods | GET (`OPEN_MODE_HTTP_GET`, `_GET_H`), POST (`_POST`), PUT (`_PUT_H`), DELETE (`_DELETE`, `_DELETE_H`, `network_http_delete`) |
| `network_http_post`, `network_http_post_bin`, `network_http_put` | send the request with its data, any length |
| `network_http_start_add_headers`, `network_http_add_header`, `network_http_end_add_headers` | request headers |
| `network_http_set_channel_mode` | `HTTP_CHAN_MODE_BODY`, `_SET_HEADERS`, `_POST_SET_DATA` (data written in pieces: up to 256 bytes), `_COLLECT_HEADERS`, `_GET_HEADERS` (response headers) |
| `OPEN_MODE_HTTP_PUT` | PUT of everything written (up to 256 bytes), sent with the first read or at close |
| Redirects | 301 and 302 for GET and DELETE, up to 10, to `http://...` or a path on the same server |

Units `N1:`-`N4:` (`N:` = `N1:`), the M4's four sockets.

A TCP server works as on the FujiNet:

```c
network_open("N1:TCP://:6502/", OPEN_MODE_RW, OPEN_TRANS_NONE);   /* no host: listen */
network_status("N1:", &waiting, &connected, &err);   /* connected = 1: a client is waiting */
network_accept("N1:");                               /* then read, write, status are its */
...
network_close_client("N1:");                         /* end it; network_accept takes the next */
network_close("N1:");                                /* stop listening */
```

The errors are the FujiNet's: `network_accept` with nobody there gives `FN_ERR_IO_ERROR` and
209 (no connection waiting), while the last client is still connected 205, on a unit that does
not listen 208; reading or writing without a client 207. When the client closes, its data can
still be read, then 136 (end of file); `connected` turns 1 again as soon as the next client waits.

One difference: the M4 takes one client on its listening socket, which then becomes that
connection and stops listening (that is how the M4 firmware works, see Duke's `tcpserv.s`). So
while a client is connected, others are refused; the library listens again at once when the
client has gone or `network_close_client` ends it. The FujiNet keeps listening and lets the next
ones wait. Each server unit uses one of the M4's four sockets.

HTTP behaves as on the FujiNet: the request goes out with the first `network_status` or read
(until then headers and POST data can be added), an HTTP error shows as the `err` of
`network_status` (404 = 170, 401/403 = 212, 5xx = 215, ...) and its body can still be read.
It is plain HTTP/1.0 with `Connection: close`: the M4 has no TLS, so **no HTTPS**. Redirects
are followed as by the FujiNet firmware: 301 and 302, up to 10 (the 11th comes back as error 144
with its body). Spaces in the path are sent as `%20`.

Response headers work as on the FujiNet:

```c
network_open("N1:HTTP://example.org/", OPEN_MODE_HTTP_GET_H, OPEN_TRANS_NONE);
network_http_set_channel_mode("N1:", HTTP_CHAN_MODE_COLLECT_HEADERS);
network_write("N1:", "Content-Type", 12);             /* one name per write */
network_http_set_channel_mode("N1:", HTTP_CHAN_MODE_GET_HEADERS);
network_status("N1:", &waiting, &connected, &err);   /* sends the request; waiting = 10 + 1 */
network_read("N1:", buf, waiting);                   /* "text/html" and 0x9B */
network_http_set_channel_mode("N1:", HTTP_CHAN_MODE_BODY);   /* then the body as usual */
```

Differences from the FujiNet firmware (2026):
- `OPEN_MODE_HTTP_PUT_H` sends a real PUT, as its documentation says; the firmware sends a POST.
- Response header values come in the order the names were written; the firmware's order is that
  of its internal map. A header that comes twice: the first one counts.
- A redirect to a path (`Location: /new`) is followed on the PC too (the FujiNet-PC firmware
  only follows full URLs). POST and PUT are not redirected (error 144 with the 3xx body): their
  data is not kept. Headers added by the program are not sent again to the new location.
- Limits from the CPC's memory: PUT data and data written in `_POST_SET_DATA` up to 256 bytes
  per unit (`network_http_post_bin` sends any length), response header names up to 64 bytes and
  values up to 192 bytes together, one unit at a time collecting response headers
  (`FN_HDR_NAMES`, `FN_HDR_VALUES`, `FN_RXBUF` when compiling the library).
- An empty `OPEN_MODE_HTTP_PUT` is sent (`Content-Length: 0`); the firmware sends nothing.

**Translation** works as on the FujiNet, with CR as the CPC's end of line (the FujiNet's
default outside the Atari, whose end of line is 0x9B): with `OPEN_TRANS_LF` a received LF becomes
CR and a CR written over TCP is sent as LF; with `OPEN_TRANS_CRLF` a received CR LF becomes CR
(also when the two come in different packets) and a written CR goes as CR LF. `OPEN_TRANS_CR`
changes nothing on the CPC. For HTTP only the received body is translated (as the firmware does).
The bytes waiting are counted after the translation. `OPEN_TRANS_PET` (PETSCII, C64) returns 146.

**JSON** works as on the FujiNet:

```c
network_open("N1:HTTP://example.org/api", OPEN_MODE_HTTP_GET, OPEN_TRANS_NONE);
network_json_parse("N1:");                        /* reads the whole body, checks it */
n = network_json_query("N1:", "/list/0/name", buf);   /* a JSON pointer; buf: "Joe", n = 3 */
network_close("N1:");
```

The result is the FujiNet's: a string without its quotes and with its escapes decoded (`\u00e9`
as UTF-8), `TRUE`, `FALSE`, `NULL`, a number, an object as `key CR value CR ...`, an array as its
values one after the other; the last end of line is cut off, `buf` is 0-terminated, a path that
is not there gives "" and 0. Invalid JSON: `network_json_parse` gives `FN_ERR_IO_ERROR` with 213.
Differences: there is no room for a parsed tree on the CPC, so the document stays as text (up to
`FN_JSON_BUF` = 2048 bytes, nested up to 16 deep; bigger gives error 255) and each query walks
it; one document at a time (parsing on another unit replaces it). Numbers come as written, only
trailing zeros of a fraction are dropped (`3.0` -> `3`, `1.50` -> `1.5`) - the firmware converts
them (`1.5e3` -> `1500`). A `\u` surrogate pair is not combined into one character.
`network_set_eol` and the query flags (`network_set_query_param`) are not there.

**Not yet:** HTTPS, other protocols (TNFS, FTP, ...), UDP. They return `FN_ERR_BAD_CMD` (or
`FN_ERR_IO_ERROR`) with `fn_network_error` = 146 (not implemented).

Size (SDCC 4.5, code / data):

| Build | Code | Data |
|---|---|---|
| everything | 11.9 KB | 3.9 KB (2 KB of it the JSON document) |
| `-DFN_NO_JSON` | 9.4 KB | 1.8 KB |
| `-DFN_NO_HTTP` (TCP only, JSON left out too) | 3.3 KB | 1.1 KB (mostly the 4 receive buffers) |

With `-DFN_NO_HTTP` (`make NO_HTTP=1` here) HTTP opens return "not implemented" and the
`network_http_*` and `network_json_*` functions are left out, so a program that uses them does not
link; `-DFN_NO_JSON` leaves out only JSON. Retro Game Battle's CPC client `RGBTCP.BIN` is about
9.8 KB with `-DFN_NO_HTTP`.

Memory: on the CPC a program's code, data and stack go from &4000 to HIMEM, &A5F7 with the M4 ROM
(about 26 KB). The whole library with the M4 library and `printf` takes more than half of it.
The kit's `crt0.s` gives the program its own 1 KB stack (from kit commit 5deafce): the firmware's
has only about 200 bytes, which this library's calls go beyond.

## Status (2026-11-17)

The library covers what CPC programs need from fujinet-lib's network API: TCP client and server,
HTTP. What is left are extras (see Open). Issues and ideas are welcome.

**Done**
- TCP client: open (host name or a.b.c.d), status, read (blocking and non-blocking), write, close,
  units `N1:`-`N4:` - the calls Retro Game Battle's CPC client needs.
- HTTP client (plain HTTP/1.0): GET, POST (text, in pieces, binary), PUT, DELETE, request headers,
  HTTP errors as FujiNet error codes, body of an error response readable.
- Response headers (`HTTP_CHAN_MODE_COLLECT_HEADERS` / `_GET_HEADERS`), redirects (301/302),
  `OPEN_MODE_HTTP_PUT` (2026-11-17).
- TCP server: listening, `network_accept`, `network_close_client`, one client at a time (2026-11-17).
- Translation of line ends (`OPEN_TRANS_CR`, `_LF`, `_CRLF`) and JSON (parse, query) (2026-11-17).
- TCP-only build (`-DFN_NO_HTTP`), used by Retro Game Battle; `-DFN_NO_JSON`.
- Test programs against a local test server (`make test`, both variants) - in the emulator.

**Open**

| | Note |
|---|---|
| Real CPC + M4 | everything so far runs only in the emulator (CPCSyntaxError with M4 emulation) |
| UDP (a plus) | not offered by the M4 as documented - see the hint below |
| TNFS (a plus) | FujiNet's file protocol, normally over UDP - only with UDP, or if TNFS over TCP works (to be checked) |
| HTTPS | not possible on the M4 (no TLS) - only with FujiNet hardware (see the next goal) |

**Hint: UDP on the M4** (checked 2026-11-17). Duke's command documentation
([m4info.txt](http://www.spinpoint.org/cpc/m4info.txt), updated 2024-11-27) says of `C_NETSOCKET`
(0x4331): "Only TCP protocol for now". There is no sendto/recvfrom command, the socket table has
no sender address for datagrams, the changelog has no UDP entry and Duke's examples
([M4examples](https://github.com/M4Duke/M4examples)) are TCP only. CPCSyntaxError's M4 emulation
also makes every socket TCP. Not checked: the M4's Wi-Fi firmware (not public) - an undocumented
UDP path could be tried on a real M4 with `C_NETSOCKET` type 2, protocol 17 (connect, send, look
for the datagram on the PC). Until then `UDP://` returns 146 (not implemented), and UDP and TNFS
would come with FujiNet hardware for the CPC (see the next goal).

## Build and test

Needs the CPC development kit next to this folder (its setup script run), from commit 5deafce
on (`m4_listen` in its M4 library, its own stack in `crt0.s`).

```sh
make            # build/fujinet-network.rel + build/m4.rel
make test       # FNTEST, FNHTTP, FNJSON in the kit's emulator against test/testserver.py: PASS/FAIL
make test NO_HTTP=1   # FNTEST only, with the TCP-only library (-DFN_NO_HTTP)
```

Your program: compile with `-I include -I <kit>/lib/m4` (plus `-DFN_NO_HTTP` for TCP only),
link `build/fujinet-network.rel` and `build/m4.rel`.

The tests are three programs - one with everything would not fit in the CPC's memory: FNTEST
(TCP client and server, translation, errors; linked with the library without JSON), FNHTTP
(HTTP, the same library) and FNJSON (JSON, the whole library). The Makefile checks that each ends
below HIMEM (&A5F7) - "too big for the CPC" otherwise. For a real CPC: `make fntest SERVER=<the
PC's address>` puts them on `fntest.dsk`; `python3 test/testserver.py` on the PC; `RUN"FNTEST"`,
then the server again for `RUN"FNHTTP"` and `RUN"FNJSON"`.

The test covers: the CPC as a TCP server (T5: two clients one after the other - the test server
connects to the address the CPC called it from - with the errors before, between and after
them, the end of the first client, `network_close_client` for the second), 3000 bytes received the usual FujiNet way (status, then `read_nb`) and the end
of the connection, 2000 bytes sent in pieces of 1-1400 bytes, a blocking read of slowly arriving
data, a host name, two units at once, re-opening a unit, a refused connection, an unknown host
and bad devicespecs. HTTP (against an HTTP server in `test/testserver.py`, port 6512): a
3000-byte GET through the 256-byte buffer with a 400-byte response header line, a request
header, a 404 with its body, POST as text, in pieces and as 1000 bytes of binary data, PUT,
DELETE, a path with a space; redirects (to another host name, to a path, for DELETE, and not
followed: more than 10, to https, for POST); response headers collected through a redirect
(order, case, an EOL after the name, a missing one, a second unit refused, read again, then the
body); `OPEN_MODE_HTTP_PUT` sent by a read and by the close (with an HTTP error from the close);
an HTTP body with `OPEN_TRANS_LF`; and HTTPS (not supported). Translation over TCP (T6, T7): LF
and CR LF both ways, a CR LF split over two packets, the bytes waiting after it, PETSCII refused.
JSON (FNJSON): 21 queries on a pretty printed document with CR LF (every type, escapes, `\u`,
`~0`/`~1` in a path, an array, an object, empty ones, a missing path, a query without `/`), the
whole document, a query before parsing and after closing, invalid JSON, too deep, too big, a 404
body.

## Used by

- [Retro Game Battle](https://github.com/joergr72idb/retro-game-battle): its CPC client shares the
  protocol code (`clients/common/rgb_core.c`) with the Atari, C64 and Apple II clients, which use
  fujinet-lib. Retro Game Battle carries this library as a git subtree in `lib/fujinet-network-cpc`.

## Tested (2026-11-17, emulator only)

CPCSyntaxError (the kit's, with M4 emulation) on Ubuntu 26.04 and Debian 13: `make test` passes
(both variants). Not yet on a real CPC + M4.

Note for SDCC 4.5.0: it can mix up registers in some expressions (seen: `p + i` computed as
`p + 80` after `port = 80`, and `return f(), 0;` losing what `f` set). Where it happened the
code is written around it, with a comment.

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
