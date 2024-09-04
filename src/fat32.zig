const std = @import("std");

// FAT32 Volume Boot Record (VBR)
pub const Vbr = extern struct {
    BS_jmpBoot: [3]u8 align(1) = [_]u8{ 0xEB, 0x58, 0x90 },
    BS_OEMName: [8]u8 align(1),
    BPB_BytesPerSec: u16 align(1),
    BPB_SecPerClus: u8,
    BPB_RsvdSecCnt: u16 align(1),
    BPB_NumFATs: u8,
    BPB_RootEntCnt: u16 align(1),
    BPB_TotSec16: u16 align(1) = 0,
    BPB_Media: u8,
    BPB_FATSz16: u16 align(1) = 0,
    BPB_SecPerTrk: u16 align(1),
    BPB_NumHeads: u16 align(1),
    BPB_HiddSec: u32 align(1),
    BPB_TotSec32: u32 align(1),

    // Extended
    BPB_FATSz32: u32 align(1),
    BPB_ExtFlags: u16 align(1),
    BPB_FSVer: u16 align(1),
    BPB_RootClus: u32 align(1),
    BPB_FSInfo: u16 align(1),
    BPB_BkBootSec: u16 align(1),
    BS_Reserved0: u64 align(1) = 0,
    BS_Reserved1: u32 align(1) = 0,
    BS_DrvNum: u8,
    BS_Reserved2: u8 = 0,
    BS_BootSig: u8,
    BS_VolID: u32 align(1),
    BS_VolLab: [11]u8 align(1),
    BS_FilSysType: [8]u8 align(1) = [_]u8{ 'F', 'A', 'T', '3', '2', ' ', ' ', ' ' },

    // Not in fatgen103.pdf tables
    boot_code: [420]u8 align(1) = [_]u8{0} ** 420,
    signature: u16 align(1) = 0xAA55,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 512);
    }
};

pub const FSInfo = extern struct {
    FSI_LeadSig: u32 align(1) = 0x41615252,

    FSI_Reserved1: [480]u8 align(1) = [_]u8{0} ** 480,

    FSI_StrucSig: u32 align(1) = 0x61417272,

    FSI_Free_Count: u32 align(1),

    FSI_Nxt_Free: u32 align(1),

    FSI_Reserved2: [12]u8 align(1) = [_]u8{0} ** 12,

    FSI_TrailSig: u32 align(1) = 0xAA550000,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 512);
    }
};
