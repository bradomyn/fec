target = "altera"
action = "synthesis"

fetchto = "../../../ip_cores"

syn_device = "ep2agx125ef"
syn_grade = "c5"
syn_package = "29"
syn_top = "scu_top"
syn_project = "scu"

quartus_preflow = "scu.tcl"

modules = {"local" : [ "../../../", "../../../top/gsi_scu/wr_core_demo"]}
