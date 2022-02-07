symtable_start exports
defsymbol str_interrupts, lbl_interrupts
symtable_end exports

symtable_start imports
defsymbol str_reset, reset_ref
symtable_end imports

stringtable_start strings
str_reset: string 'reset'
str_interrupts: string 'interrupts'
stringtable_end strings


data:

lbl_interrupts:
reset_ref: DW 1
DW 2
DW 3
DW 4
DW 5
DW 6
DW 7
DW 8

lbl_init:
DB "Here be dragons"

data_end: