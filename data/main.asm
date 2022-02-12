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

relocs_start relocs
DD reloc_loc - data
relocs_end relocs

ALIGN 16
data:

reset_def:
DB "This is the reset symbol", 0

DW 0x1111
patch_location:
DW 0
DW 0x2222


ALIGN 2
DB "XXXX"
reloc_loc:
DW 0x8788
DB "XXXX"

data_end:
