#!/usr/bin/env python3
"""Clear the executable bit from PT_GNU_STACK in ELF files.

Some of UniFi Video's bundled JNI libraries are linked without a .note.GNU-stack
section, so the linker conservatively marks the stack RWE. glibc then tries to
mprotect the thread stack executable at dlopen() time, which current kernels refuse:
  cannot enable executable stack as shared object requires: Permission denied
The libraries do not actually execute from the stack; the flag is a build artifact.
"""
import struct, sys

PT_GNU_STACK = 0x6474e551
rc = 0
for path in sys.argv[1:]:
    try:
        with open(path, 'r+b') as f:
            hdr = f.read(64)
            if hdr[:4] != b'\x7fELF':
                print(f"  {path}: not an ELF file"); continue
            if hdr[4] != 2:
                print(f"  {path}: not ELF64, skipping"); continue
            en = '<' if hdr[5] == 1 else '>'
            e_phoff    = struct.unpack_from(en + 'Q', hdr, 0x20)[0]
            e_phentsize= struct.unpack_from(en + 'H', hdr, 0x36)[0]
            e_phnum    = struct.unpack_from(en + 'H', hdr, 0x38)[0]
            for i in range(e_phnum):
                off = e_phoff + i * e_phentsize
                f.seek(off)
                p_type, p_flags = struct.unpack(en + 'II', f.read(8))
                if p_type != PT_GNU_STACK:
                    continue
                if p_flags & 0x1:
                    f.seek(off + 4)
                    f.write(struct.pack(en + 'I', p_flags & ~0x1))
                    print(f"  {path}: flags {p_flags} -> {p_flags & ~0x1} (X cleared)")
                else:
                    print(f"  {path}: already non-executable")
                break
            else:
                print(f"  {path}: no PT_GNU_STACK segment")
    except OSError as e:
        print(f"  {path}: {e}"); rc = 1
sys.exit(rc)
