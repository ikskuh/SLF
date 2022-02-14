# ⛓ Simple Linking Format

SLF is a very simple object file format that can be used to link programs that don't require distinct sections for code and data.

## Project Status

**Disclaimer: Highly experimental, do not use.**

The project implements a very basic object file format for 16, 32 or 64 bit architectures. It supports only pointer relocations and only a single segment and section (consider each object file a single blob).

Each file can have internal references, as well as imports and exports.

[Read more in the format documentation](docs/module-format.md)

### Available Tools

- `slf-ld` is the standalone linker that can be used to link object files into a flat binary
- `slf-objdump` is a dumper for SLF files. It can list all sections as well as dump the raw binary data.

### TODO

- [ ] Add better diagnostics
  - [ ] Add support for object/file names
- [ ] Support exporting other file types
  - [x] flat binary
  - [ ] intel hex
