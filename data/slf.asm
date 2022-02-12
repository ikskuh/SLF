%macro symtable_start 1
%1: DD (%1_end - %1 - 4) / 8
%endmacro

%macro symtable_end 1
%1_end:
%endmacro

%macro defsymbol 2
  DD %1 - strings
  DD %2 - data
%endmacro

%macro relocs_start 1
%1: DD (%1_end - %1 - 4) / 4
%endmacro

%macro relocs_end 1
%1_end:
%endmacro

%macro stringtable_start 1
%1: DD (%1_end - %1)
%endmacro

%macro stringtable_end 1
%1_end:
%endmacro

%macro string 1
DD %%end_str - %%start_str
%%start_str:
DB %1
%%end_str:
DB 0
%endmacro

ORG 0x0000
DB 0xFB, 0xAD, 0xB6, 0x02
DD exports         ; export_table
DD imports         ; import_table
DD relocs          ; relocation_table
DD strings         ; string_table
DD data            ; section_start
DD data_end - data ; section_size
DB 2               ; symbol_size
DB 0,0,0           ; padding