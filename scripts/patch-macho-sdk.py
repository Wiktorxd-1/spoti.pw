#!/usr/bin/env python3
"""Patch Mach-O binary LC_BUILD_VERSION and LC_VERSION_MIN_IPHONEOS sdk fields.

This tells iOS, dyld, FrontBoard and SpringBoard that the application was compiled
against the modern iOS SDK (e.g. iOS 27.2), which enables edge-to-edge display on
the iPhone Duo inner foldable display without pillarbox black bars.
"""

import os
import struct
import sys


def patch_binary(path, target_major=27, target_minor=2, target_patch=0):
    packed_sdk = (target_major << 16) | (target_minor << 8) | target_patch
    if not os.path.isfile(path):
        print(f"Error: {path} not found", file=sys.stderr)
        return 0

    with open(path, "r+b") as f:
        data = f.read()
        if len(data) < 32:
            print("Error: binary too small", file=sys.stderr)
            return 0

        patched_count = 0

        def patch_slice(slice_offset):
            nonlocal patched_count
            if slice_offset + 32 > len(data):
                return
            magic = struct.unpack("<I", data[slice_offset:slice_offset + 4])[0]
            endian = "<"
            is_64 = False
            if magic == 0xfeedfacf:
                is_64 = True
            elif magic == 0xfeedface:
                is_64 = False
            elif magic == 0xcffaedfe:
                is_64 = True
                endian = ">"
            elif magic == 0xcefaedfe:
                is_64 = False
                endian = ">"
            else:
                return

            header_size = 32 if is_64 else 28
            _, _, _, _, ncmds, sizeofcmds, _ = struct.unpack(
                f"{endian}IIIIIII", data[slice_offset:slice_offset + 28]
            )
            cmd_offset = slice_offset + header_size
            LC_BUILD_VERSION = 0x32
            LC_VERSION_MIN_IPHONEOS = 0x25

            for _ in range(ncmds):
                if cmd_offset + 8 > len(data):
                    break
                cmd, cmdsize = struct.unpack(f"{endian}II", data[cmd_offset:cmd_offset + 8])
                if cmdsize <= 0:
                    break
                if cmd == LC_BUILD_VERSION and cmd_offset + 24 <= len(data):
                    # cmd(4) + cmdsize(4) + platform(4) + minos(4) + sdk(4) + ntools(4)
                    platform = struct.unpack(f"{endian}I", data[cmd_offset + 8:cmd_offset + 12])[0]
                    # platform 1 is iOS, platform 2 is tvOS, platform 6 is watchOS, etc.
                    # We patch any iOS or universal platform slice
                    curr_sdk = struct.unpack(f"{endian}I", data[cmd_offset + 16:cmd_offset + 20])[0]
                    f.seek(cmd_offset + 16)
                    f.write(struct.pack(f"{endian}I", packed_sdk))
                    print(
                        f"  [patch-macho-sdk] Patched LC_BUILD_VERSION sdk: "
                        f"{curr_sdk >> 16}.{(curr_sdk >> 8) & 0xff} -> {target_major}.{target_minor}"
                    )
                    patched_count += 1
                elif cmd == LC_VERSION_MIN_IPHONEOS and cmd_offset + 16 <= len(data):
                    # cmd(4) + cmdsize(4) + version(4) + sdk(4)
                    curr_sdk = struct.unpack(f"{endian}I", data[cmd_offset + 12:cmd_offset + 16])[0]
                    f.seek(cmd_offset + 12)
                    f.write(struct.pack(f"{endian}I", packed_sdk))
                    print(
                        f"  [patch-macho-sdk] Patched LC_VERSION_MIN_IPHONEOS sdk: "
                        f"{curr_sdk >> 16}.{(curr_sdk >> 8) & 0xff} -> {target_major}.{target_minor}"
                    )
                    patched_count += 1
                cmd_offset += cmdsize

        magic_be = struct.unpack(">I", data[:4])[0]
        if magic_be in (0xcafebabe, 0xbebafeca):
            nfat = struct.unpack(">I", data[4:8])[0]
            for i in range(nfat):
                _, _, offset, size, _ = struct.unpack(
                    ">IIIII", data[8 + i * 20 : 8 + (i + 1) * 20]
                )
                patch_slice(offset)
        else:
            patch_slice(0)

        f.flush()
        return patched_count


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: patch-macho-sdk.py <binary_path> [major] [minor] [patch]", file=sys.stderr)
        sys.exit(1)

    bin_path = sys.argv[1]
    major = int(sys.argv[2]) if len(sys.argv) > 2 else 27
    minor = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    patch = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    count = patch_binary(bin_path, major, minor, patch)
    print(f"Patched {count} Mach-O load command(s) in {bin_path}")
