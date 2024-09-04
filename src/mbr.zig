const std = @import("std");

pub const MbrPartitionRecord = packed struct(u128) {
    boot_indicator: u8 = 0,
    starting_chs: u24 = 0,
    os_type: u8 = 0,
    ending_chs: u24 = 0,
    starting_lba: u32 = 0,
    size_in_lba: u32 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 16);
    }
};

// FIXME: Added align(1) to make this struct packed, find a better way to
// represent this data structure.
pub const Mbr = extern struct {
    boot_code: [440]u8 align(1),
    mbr_disk_signature: u32 align(1),
    unknown: u16 align(1),
    partition_records: [4]MbrPartitionRecord align(1),
    signature: u16 align(1),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 512);
    }
};
