# ⛓ Simple Linking Format

SLF is a very simple object file format that can be used to link programs that don't require distinct sections for code and data.

## Project Status

Highly experimental, do not use.

### TODO

- [ ] Add support for internal references
- [ ] Add better diagnostics
  - [ ] Add support for object/file names
- [ ] Make `slf-ld` have a better command line interface
  - [ ] Accept files on the CLI
  - [ ] Specify poiner size and module alignment
- [ ] Implement `slf-objdump` to debug view `.slf` files
