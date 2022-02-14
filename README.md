# ⛓ Simple Linking Format

SLF is a very simple object file format that can be used to link programs that don't require distinct sections for code and data.

## Documentation

- [Binary Format](docs/module-format.md)

## Available Tools

- `slf-ld` is the standalone linker that can be used to link object files into a flat binary
- `slf-objdump` is a dumper for SLF files. It can list all sections as well as dump the raw binary data.

## Available APIs

`src/slf.zig` is a package that exports several APIs:

- `slf.View` allows introspection of in-memory SLF files.
- `slf.Linker` allows linking SLF files together.
- `slf.Builder` allows the creation of new SLF files.

## Project Status

[![Build](https://github.com/MasterQ32/SLF/actions/workflows/cross-build.yml/badge.svg)](https://github.com/MasterQ32/SLF/actions/workflows/cross-build.yml)

**Disclaimer: Feature complete, but still highly experimental.**

### TODO

- [ ] Add better diagnostics
  - [ ] Add support for object/file names
- [ ] Support exporting other file types
  - [x] flat binary
  - [ ] intel hex
