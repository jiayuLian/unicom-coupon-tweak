#!/usr/bin/env python3
# ldid_python.py — 极简 Mach-O ad-hoc 伪签名器 (iOS arm64 dylib)
# 不依赖任何外部工具, 纯 Python。在文件末尾追加 LC_CODE_SIGNATURE (ad-hoc),
# 并把所有指向数据区的文件偏移 +SHIFT 校正。
# 注: TrollStore 注入 dylib 时也会自动 ldid 一次, 本脚本是双保险。

import sys
import struct
import hashlib

PAGE = 4096
SHIFT = 16  # LC_CODE_SIGNATURE 占 16 字节

# LC 命令
LC_SEGMENT_64        = 0x19
LC_SYMTAB            = 0x2
LC_DYSYMTAB          = 0xb
LC_DYLD_INFO_ONLY    = 0x22
LC_CODE_SIGNATURE    = 0x1d
LC_FUNCTION_STARTS   = 0x26
LC_DATA_IN_CODE      = 0x29
LC_SEGMENT_SPLIT_INFO= 0x2e
LC_DYLIB_CODE_SIGN_DRS = 0x2b
LC_LINKER_OPTIMIZATION_HINT = 0x32
LC_DYLD_EXPORTS_TRIE = 0x33
LC_DYLD_CHAINED_FIXUPS = 0x34

# 含 dataoff 字段 (offset 0x8, 4字节) 的 LC
DATAOFF_LCS = {LC_FUNCTION_STARTS, LC_DATA_IN_CODE, LC_CODE_SIGNATURE,
               LC_SEGMENT_SPLIT_INFO, LC_DYLIB_CODE_SIGN_DRS,
               LC_LINKER_OPTIMIZATION_HINT, LC_DYLD_EXPORTS_TRIE, LC_DYLD_CHAINED_FIXUPS}


def bump_fileoff(data, lo, fields):
    for f in fields:
        v = struct.unpack_from('<I', data, lo + f)[0]
        if v:
            struct.pack_into('<I', data, lo + f, v + SHIFT)


def patch_lc_offsets(data, lc_offsets):
    """把所有指向数据区的文件偏移 +SHIFT。"""
    for (lo, cmd, cs) in lc_offsets:
        if cmd == LC_SEGMENT_64:
            # fileoff @ 0x28 (8 bytes), 然后每个 section_64.offset @ 0x30
            fo = struct.unpack_from('<Q', data, lo + 0x28)[0]
            struct.pack_into('<Q', data, lo + 0x28, fo + SHIFT)
            nsects = struct.unpack_from('<I', data, lo + 0x40)[0]
            sec = lo + 0x48
            for _ in range(nsects):
                so = struct.unpack_from('<Q', data, sec + 0x30)[0]
                if so:
                    struct.pack_into('<Q', data, sec + 0x30, so + SHIFT)
                sec += 0x50  # sizeof(section_64) = 80
        elif cmd == LC_SYMTAB:
            bump_fileoff(data, lo, (0x8, 0xc))
        elif cmd == LC_DYSYMTAB:
            bump_fileoff(data, lo, (0x20, 0x28, 0x30, 0x38, 0x40, 0x48))
        elif cmd == LC_DYLD_INFO_ONLY:
            bump_fileoff(data, lo, (0x8, 0xc, 0x10, 0x14, 0x18))
        elif cmd in DATAOFF_LCS:
            bump_fileoff(data, lo, (0x8,))


def build_blob(code_limit):
    ident = b"couponhook\x00"
    nslots = (code_limit + PAGE - 1) // PAGE

    # CodeDirectory (version 0x20001, big-endian)
    # 头部固定 44 字节: 9*uint32(magic..codeLimit) + 4*uint8(hashSize,hashType,platform,pageSize) + uint32(spare2)
    CD_HEADER = 44
    cd_magic = 0xFADE0C02
    cd_version = 0x20001
    cd_flags = 0x0
    ident_offset = CD_HEADER
    hash_offset = CD_HEADER + len(ident)
    n_special = 0
    n_code = nslots
    hash_size = 20      # SHA1
    hash_type = 1
    spare1 = 0          # platform 字段
    page_size = 12      # log2(4096)
    spare2 = 0
    cd_length = hash_offset + n_code * hash_size

    cd = struct.pack('>IIIIIIIIIBBBBI',
                     cd_magic, cd_length, cd_version, cd_flags,
                     hash_offset, ident_offset, n_special, n_code,
                     code_limit, hash_size, hash_type, spare1, page_size, spare2)
    cd += ident
    # 先占位 code slots, 稍后填真实 hash
    cd += b'\x00' * (n_code * hash_size)

    # SuperBlob (big-endian)
    sb_magic = 0xFADE0CC0
    sb_count = 1
    sb_index_type = 0x0     # CSSLOT_CODEDIRECTORY
    sb_index_offset = 12 + 8  # superblob header(12) + 1 index(8)
    sb_length = sb_index_offset + cd_length
    sb = struct.pack('>III', sb_magic, sb_length, sb_count)
    sb += struct.pack('>II', sb_index_type, sb_index_offset)
    sb += cd
    return sb, nslots


def sign(path):
    with open(path, 'rb') as f:
        data = bytearray(f.read())

    magic = struct.unpack_from('<I', data, 0)[0]
    # 小端 Mach-O 64: MH_MAGIC_64 = 0xfeedfacf。0xcffaedfe 是 MH_CIGAM_64 (大端/字节序反转), 不是我们要的。
    if magic == 0xcffaedfe:
        raise SystemExit("file is MH_CIGAM_64 (big-endian / byte-swapped); expected MH_MAGIC_64 (got 0x%08x)" % magic)
    if magic != 0xfeedfacf:
        raise SystemExit("not MH_MAGIC_64 (got 0x%08x)" % magic)

    ncmds = struct.unpack_from('<I', data, 16)[0]
    old_sizeofcmds = struct.unpack_from('<I', data, 20)[0]
    LCS_OFF = 32

    # 解析所有 LC
    lc_offsets = []
    off = LCS_OFF
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        lc_offsets.append((off, cmd, cmdsize))
        off += cmdsize

    # 已经签过名就跳过
    for (_, cmd, _) in lc_offsets:
        if cmd == LC_CODE_SIGNATURE:
            print("[*] already has LC_CODE_SIGNATURE, skip")
            return

    # 校正所有文件偏移
    patch_lc_offsets(data, lc_offsets)

    # 新 LCs = 旧 LCs + 新 LC_CODE_SIGNATURE(占位)
    old_lcs = bytes(data[LCS_OFF:LCS_OFF + old_sizeofcmds])
    new_sizeofcmds = old_sizeofcmds + SHIFT

    # 组装新文件: header + new_lcs + 旧 data 区
    old_data = bytes(data[LCS_OFF + old_sizeofcmds:])
    out = bytearray()
    out += data[0:LCS_OFF]
    out += old_lcs
    out += b'\x00' * SHIFT   # 给新 LC 留位
    out += old_data
    # 此刻 out 末尾即 blob 位置
    code_limit = len(out)

    # 计算 code slots 的真实 hash (对 out[0:code_limit] 按页)
    sb, nslots = build_blob(code_limit)
    sb = bytearray(sb)  # 字节需要可写, 下面要回填 hash slot
    # 填 hash: 找到 cd 中 hash 区起点 (sb_index_offset 之后)
    cd_start = 12 + 8  # superblob header + index, 在 sb 内
    hash_area = cd_start + 44 + len(b"couponhook\x00")  # cd header(44) + ident
    for i in range(nslots):
        page = out[i * PAGE:(i + 1) * PAGE]
        if len(page) < PAGE:
            page = page + b'\x00' * (PAGE - len(page))
        h = hashlib.sha1(page).digest()
        sb[hash_area + i * 20: hash_area + i * 20 + 20] = h

    # 写回 LC_CODE_SIGNATURE (在 out 的 LCS_OFF+old_sizeofcmds 处)
    dataoff = code_limit
    new_lc = struct.pack('<IIII', LC_CODE_SIGNATURE, SHIFT, dataoff, 0)
    out[LCS_OFF + old_sizeofcmds: LCS_OFF + new_sizeofcmds] = new_lc

    # 更新 header
    struct.pack_into('<I', out, 16, ncmds + 1)
    struct.pack_into('<I', out, 20, new_sizeofcmds)

    # 追加 blob
    out += sb

    with open(path, 'wb') as f:
        f.write(out)
    print("[*] signed %s (size=%d, pages=%d)" % (path, len(out), nslots))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("usage: ldid_python.py <dylib>")
        sys.exit(1)
    sign(sys.argv[1])
