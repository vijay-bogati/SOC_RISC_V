#!/usr/bin/env python3
#***************************************************************
# Project name                  : ADR SoC
# File Name                     : ip_ports.py
# Module/class Name             : Python script
# Author                        : Vijay Bogati
# Description                   : Prints the parameter and port tables of one of our modules as Markdown
#***************************************************************

# ADR SoC - print the parameter and port tables of one of our own modules, as Markdown.
# Used for the IP documents in docs/ip/, so their interface tables match the RTL.
#   python3 scripts/ip_ports.py rtl/adr_ip/wdt/rtl/adr_wdt.sv [module_name]
# Handles the ANSI header style used in rtl/adr_soc and rtl/adr_ip; it is not a general parser.

import re
import sys


def strip_block_comments(text):
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def header(text, name):
    m = re.search(r"\bmodule\s+" + re.escape(name) + r"\b(.*?)\)\s*;", text, flags=re.S)
    if not m:
        sys.exit(f"module {name} not found")
    body = m.group(1)
    params, ports = "", body
    pm = re.match(r"\s*(?:import[^;]*;\s*)*#\s*\((.*?)\)\s*\((.*)", body, flags=re.S)
    if pm:
        params, ports = pm.group(1), pm.group(2)
    else:
        ports = re.sub(r"^\s*(?:import[^;]*;\s*)*\(", "", body, flags=re.S)
    return params, ports


def items(block):
    """Split a header list into (code, comment) per declaration, keeping trailing comments."""
    out, cur, com = [], "", []
    depth = 0
    for line in block.splitlines():
        code, _, c = line.partition("//")
        c = c.strip()
        if c and not code.strip():
            # a comment on its own line heads the group of declarations below it
            if cur.strip():
                com.append(c)
            else:
                out.append(("#group", c))
            continue
        for ch in code:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            if ch == "," and depth == 0:
                out.append((cur.strip(), " ".join(com)))
                cur, com = "", []
                continue
            cur += ch
        if c and cur.strip():
            com.append(c)
        elif c and out and not cur.strip():
            # comment after the comma belongs to the item just closed
            code_prev, com_prev = out[-1]
            out[-1] = (code_prev, (com_prev + " " + c).strip())
        cur += " "
    if cur.strip():
        out.append((cur.strip(), " ".join(com)))
    return [(re.sub(r"\s+", " ", a), b) for a, b in out if a]


# Descriptions for ports without a comment, from the SoC's naming rules. A comment in the RTL
# always wins; these only fill the gaps, so every row of a port table says what the port is.
BLOCK_NAMES = {
    "uart0": "UART0", "uart1": "UART1", "gpio": "GPIO", "timer": "the 8-channel timer",
    "spi": "SPI", "qspi": "QSPI", "i2c": "I2C", "pwm": "PWM", "wdt": "the watchdog",
    "aes": "AES", "bus_mon": "the bus error monitor", "sys": "system control", "dma": "the DMA",
    "mux": "the pin mux", "adc": "the ADC controller", "otp": "the OTP controller",
    "aon": "the always-on timer", "eth": "Ethernet", "usb": "the USB device", "ddr": "DDR4",
    "plic": "the PLIC", "clint": "the CLINT", "rom": "the boot ROM", "sram": "the SRAM",
    "cpu": "the CPU", "debug": "the debug module", "jtag": "JTAG",
}
FIXED = {
    "clk_i": "System clock",
    "otp_req_o": "OTP controller macro request, one clock",
    "req_i": "Memory request, one clock per access", "we_i": "Write enable, 1 = write",
    "idx_i": "Word index (address in 64-bit words)", "be_i": "Byte enables for the write",
    "wdata_i": "Write data", "rdata_o": "Read data, the clock after the request",
    "slv": "AXI4 target port (SystemVerilog interface)",
    "rst_ni": "Reset, active low, asynchronous assert",
    "rtc_i": "Real-time clock input (CLINT and always-on timer time base)",
    "boot_pins_i": "Boot pins, read by system control",
    "clk_en_i": "Peripheral clock enables from system control",
    "clk_en_o": "Peripheral clock enables, to the clock gates and the APB bridge",
    "apb_req_o": "APB requests, one per slot",
    "apb_resp_i": "APB responses, one per slot",
    "irq_sources_i": "Interrupt sources to the PLIC, bit n-1 = source n",
    "debug_reset_i": "ndmreset from the debug module",
    "system_reset_req_o": "Watchdog or software system reset request, to adr_rst_gen",
    "slv_req_i": "AXI4 target port, request",
    "slv_resp_o": "AXI4 target port, response",
    "mst_req_o": "AXI4 initiator port, request",
    "mst_resp_i": "AXI4 initiator port, response",
    "read_error_i": "One pulse per read response with an error, per initiator",
    "read_error_o": "One pulse per read response with an error, per initiator",
    "write_error_i": "One pulse per write response with an error, per initiator",
    "write_error_o": "One pulse per write response with an error, per initiator",
    "last_read_addr_i": "Last accepted read address, per initiator",
    "last_read_addr_o": "Last accepted read address, per initiator",
    "last_write_addr_i": "Last accepted write address, per initiator",
    "last_write_addr_o": "Last accepted write address, per initiator",
    "sys_rst_no": "System reset, active low",
    "usb_rst_no": "USB clock domain reset, active low",
    "eth_tx_rst_no": "Ethernet transmit clock domain reset, active low",
    "eth_rx_rst_no": "Ethernet receive clock domain reset, active low",
    "usb_clk_i": "USB clock, 48 MHz",
    "eth_tx_clk_i": "Ethernet SerDes transmit clock",
    "eth_rx_clk_i": "Ethernet SerDes receive clock",
}
PIN_SUFFIX = {
    "channel_o": "input channel select, to the analog side", "dac_code_o": "DAC code, to the analog side",
    "compare_i": "comparator result from the analog side", "req_o": "macro request, one clock",
    "we_o": "macro write (program) select", "addr_o": "macro word address", "wdata_o": "macro bits to program",
    "rdata_i": "macro read data", "done_i": "macro command done, one clock", "o": "outputs",
    "dp_i": "D+ level", "dn_i": "D- level", "dp_o": "D+ drive level", "dn_o": "D- drive level",
    "dp_en_o": "D+ drive enable", "dn_en_o": "D- drive enable", "sense_i": "VBUS sense",
    "dp_pullup_o": "D+ pull-up enable", "dn_pullup_o": "D- pull-up enable (unused)",
    "serdes_tx_data_o": "SerDes transmit block payload", "serdes_tx_hdr_o": "SerDes transmit sync header",
    "serdes_rx_data_i": "SerDes receive block payload", "serdes_rx_hdr_i": "SerDes receive sync header",
    "serdes_rx_bitslip_o": "SerDes bit-slip request", "serdes_rx_reset_req_o": "SerDes receiver reset request",
    "tck_i": "TCK", "tms_i": "TMS", "tdi_i": "TDI", "tdo_o": "TDO", "tdo_oe_o": "TDO output enable", "trst_ni": "TRST, active low",
    "tx_o": "transmit data pin", "rx_i": "receive data pin", "sclk_o": "serial clock pin",
    "csn_o": "chip selects, active low", "mosi_o": "data out pin", "miso_i": "data in pin",
    "sdo_o": "data out pins", "sdi_i": "data in pins", "mode_o": "line mode (single or quad)",
    "scl_i": "SCL level from the bus", "scl_o": "SCL output level", "scl_t": "SCL tri-state, 1 = released",
    "sda_i": "SDA level from the bus", "sda_o": "SDA output level", "sda_t": "SDA tri-state, 1 = released",
    "in_i": "input pins", "out_o": "output pins", "dir_o": "pin directions, 1 = output",
}


def describe(name):
    """A description from the port name, or '' when no rule applies."""
    if name in FIXED:
        return FIXED[name]
    for key, block in sorted(BLOCK_NAMES.items(), key=lambda kv: -len(kv[0])):
        if not name.startswith(key + "_"):
            continue
        rest = name[len(key) + 1:]
        if rest == "apb_req_i":
            return f"APB request to {block}"
        if rest == "apb_resp_o":
            return f"APB response from {block}"
        if rest == "irq_o":
            return f"Interrupt from {block}, to the PLIC"
        if rest in ("req_i", "req_o"):
            return f"AXI4 request, {block} port"
        if rest in ("resp_i", "resp_o"):
            return f"AXI4 response, {block} port"
        if rest in PIN_SUFFIX:
            label = block[4:] if block.startswith("the ") else block
            return f"{label[0].upper() + label[1:]} {PIN_SUFFIX[rest]}"
    return ""


def md_escape(s):
    return s.replace("|", "\\|")


def main():
    path = sys.argv[1]
    text = strip_block_comments(open(path).read())
    name = sys.argv[2] if len(sys.argv) > 2 else re.search(r"\bmodule\s+(\w+)", text).group(1)
    params, ports = header(text, name)

    print(f"Module `{name}`, file `{path}`.\n")
    plist = items(params) if params.strip() else []
    if plist:
        print("| Parameter | Declaration | Description |")
        print("|---|---|---|")
        for code, com in plist:
            if code == "#group":
                print(f"| *{md_escape(com)}* | | |")
                continue
            code = re.sub(r"^parameter\s+", "", code)
            m = re.match(r"(.*?)\b(\w+)\s*=\s*(.*)$", code)
            pname, decl = (m.group(2), code) if m else (code, code)
            print(f"| `{pname}` | `{md_escape(decl)}` | {md_escape(com)} |")
        print()
    print("| Port | Direction | Type | Description |")
    print("|---|---|---|---|")
    last_dir, last_type = "", ""
    for code, com in items(ports):
        if code == "#group":
            print(f"| *{md_escape(com)}* | | | |")
            continue
        m = re.match(r"(input|output|inout)?\s*(.*?)\s*\b(\w+)\s*(\[[^\]]*\])?\s*$", code)
        if not m:
            print(f"| `{md_escape(code)}` | | | {md_escape(com)} |")
            continue
        d, t, n, unpacked = m.groups()
        d = d or last_dir
        t = t or last_type
        last_dir, last_type = d, t
        t = (t + (" " + unpacked if unpacked else "")).strip()
        print(f"| `{n}` | {d} | `{md_escape(t)}` | {md_escape(com or describe(n))} |")


if __name__ == "__main__":
    main()
