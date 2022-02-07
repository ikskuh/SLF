symtable_start exports
defsymbol str_strcpy, strcpy_def
symtable_end exports

symtable_start imports
defsymbol str_interrupts, patch_location
symtable_end imports

stringtable_start strings
str_strcpy: string 'strcpy'
str_interrupts: string 'interrupts'
stringtable_end strings


data:

strcpy_def:
DB "This is the strcpy symbol", 0

patch_location:
DW 3333
DW 0
DW 4444

data_end: