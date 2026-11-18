/***************************************************************
 Project name                  : ADR SoC
 File Name                     : usb_files.sv
 Module/class Name             : OpenTitan USB device sources (include list)
 Author                        : Vijay Bogati
 Description                   : The OpenTitan files for the USB device, compiled as one unit
***************************************************************/

// ADR SoC - the OpenTitan files for the USB device, compiled as one unit.
// Some of them use assertion macros without including their definitions, so they rely on being
// compiled together. Those macros also have the same names as the ones in common_cells, with
// different arguments. Keeping them in this one file separates the two on both simulators.

// With SIMULATION defined, the synchronizers add a random-delay model that our simulator version
// can't compile. It is off by default, so leaving it out changes nothing.
`undef SIMULATION

`include "prim_assert.sv"
`include "prim_util_pkg.sv"
`include "top_pkg.sv"
`include "prim_mubi_pkg.sv"
`include "prim_secded_pkg.sv"
`include "prim_alert_pkg.sv"
`include "prim_subreg_pkg.sv"
`include "prim_ram_1p_pkg.sv"
`include "prim_cipher_pkg.sv"
`include "prim_count_pkg.sv"
`include "tlul_pkg.sv"
`include "usb_consts_pkg.sv"
`include "usbdev_pkg.sv"
`include "usbdev_reg_pkg.sv"
`include "prim_alert_sender.sv"
`include "prim_count.sv"
`include "prim_diff_decode.sv"
`include "prim_edge_detector.sv"
`include "prim_fifo_async.sv"
`include "prim_fifo_sync.sv"
`include "prim_fifo_sync_cnt.sv"
`include "prim_filter.sv"
`include "prim_generic_buf.sv"
`include "prim_generic_clock_mux2.sv"
`include "prim_generic_flop.sv"
`include "prim_generic_flop_2sync.sv"
`include "prim_generic_ram_1p.sv"
`include "prim_intr_hw.sv"
`include "prim_onehot_check.sv"
`include "prim_pulse_sync.sv"
`include "prim_ram_1p_adv.sv"
`include "prim_reg_cdc.sv"
`include "prim_reg_cdc_arb.sv"
`include "prim_reg_we_check.sv"
`include "prim_sec_anchor_buf.sv"
`include "prim_sec_anchor_flop.sv"
`include "prim_secded_inv_22_16_dec.sv"
`include "prim_secded_inv_22_16_enc.sv"
`include "prim_secded_inv_39_32_dec.sv"
`include "prim_secded_inv_39_32_enc.sv"
`include "prim_secded_inv_64_57_dec.sv"
`include "prim_secded_inv_64_57_enc.sv"
`include "prim_secded_inv_hamming_22_16_dec.sv"
`include "prim_secded_inv_hamming_22_16_enc.sv"
`include "prim_secded_inv_hamming_39_32_dec.sv"
`include "prim_secded_inv_hamming_39_32_enc.sv"
`include "prim_subreg.sv"
`include "prim_subreg_arb.sv"
`include "prim_subreg_ext.sv"
`include "prim_sync_reqack.sv"
`include "tlul_adapter_reg.sv"
`include "tlul_adapter_sram.sv"
`include "tlul_cmd_intg_chk.sv"
`include "tlul_cmd_intg_gen.sv"
`include "tlul_data_integ_dec.sv"
`include "tlul_data_integ_enc.sv"
`include "tlul_err.sv"
`include "tlul_err_resp.sv"
`include "tlul_fifo_async.sv"
`include "tlul_fifo_sync.sv"
`include "tlul_rsp_intg_gen.sv"
`include "tlul_socket_1n.sv"
`include "tlul_sram_byte.sv"
`include "usb_fs_nb_in_pe.sv"
`include "usb_fs_nb_out_pe.sv"
`include "usb_fs_nb_pe.sv"
`include "usb_fs_rx.sv"
`include "usb_fs_tx.sv"
`include "usb_fs_tx_mux.sv"
`include "usbdev.sv"
`include "usbdev_counter.sv"
`include "usbdev_iomux.sv"
`include "usbdev_linkstate.sv"
`include "usbdev_reg_top.sv"
`include "usbdev_usbif.sv"
`include "prim_cdc_rand_delay.sv"

// Put the common_cells macros back for everything compiled after this file.
`undef COMMON_CELLS_ASSERTIONS_SVH
`include "common_cells/assertions.svh"
