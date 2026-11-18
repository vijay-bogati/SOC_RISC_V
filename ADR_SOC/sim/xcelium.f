/***************************************************************
 Project name                  : ADR SoC
 File Name                     : xcelium.f
 Module/class Name             : File list
 Author                        : Vijay Bogati
 Description                   : Xcelium additions to the design list: library extensions and fixed third-party copies
***************************************************************/

// Xcelium (make ... SIM=xcelium). The Makefile gives the design list first: sim/adr_soc.f with CVA6's
// write buffer replaced by sim/compat_fixes/wt_dcache_wbuffer.sv (generated per build, because Xcelium
// stops on a module defined twice). This list adds the library file extensions for the -y folders and
// the other two fixed copies, which replace modules that are otherwise found through -y.
// Not validated here: these commands are set up for anyone who has Xcelium.
+libext+.sv+.v
${ADR_ROOT}/sim/compat_fixes/id_queue.sv
${ADR_ROOT}/sim/compat_fixes/dm_mem.sv
