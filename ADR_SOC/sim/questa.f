/***************************************************************
 Project name                  : ADR SoC
 File Name                     : questa.f
 Module/class Name             : File list
 Author                        : Vijay Bogati
 Description                   : Questa file list: the shared design plus fixed copies of three third-party files
***************************************************************/

// Questa file list: the shared design, then the fixed copies of three third-party files
// (sim/compat_fixes/, also used by the VCS and Xcelium lists). The copies must stay last, so they
// replace the upstream versions in the library.
-f ${ADR_ROOT}/sim/adr_soc.f
${ADR_ROOT}/sim/compat_fixes/id_queue.sv
${ADR_ROOT}/sim/compat_fixes/wt_dcache_wbuffer.sv
${ADR_ROOT}/sim/compat_fixes/dm_mem.sv
