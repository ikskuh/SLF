symtable_start exports
defsymbol str_reset, reset_def
symtable_end exports

symtable_start imports
defsymbol str_strcpy, patch_location
symtable_end imports

stringtable_start strings
str_reset: string 'reset'
str_strcpy: string 'strcpy'
stringtable_end strings


data:

reset_def:
DB "This is the reset symbol", 0

patch_location:
DW 1111
DW 0
DW 2222

data_end: