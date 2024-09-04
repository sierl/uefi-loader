const std = @import("std");
const unit = @import("unit.zig");
const mbr = @import("mbr.zig");
const gpt = @import("gpt.zig");
const fat = @import("fat32.zig");
const uuid = @import("uuid.zig");

const mib = unit.mib;
const Mbr = mbr.Mbr;
const UUID = uuid.UUID;

// Global constants
const disk_block_size = 512;

fn write_protective_mbr(
    file: std.fs.File,
    /// The total number of LBAs on the disk.
    number_of_lba: usize,
) std.fs.File.WriteError!void {
    const size_in_lba_clamped: u32 = if (number_of_lba > 0xFFFFFFFF)
        0xFFFFFFFF
    else
        @truncate(number_of_lba - 1);

    // TODO: calulate this from the `number_of_lba`
    const ending_chs: u24 = 0xFFFFFF;

    const mbr_ = Mbr{
        // `boot_code` unused by UEFI systems.
        .boot_code = [_]u8{0} ** 440,

        // Unused. Set to zero.
        .mbr_disk_signature = 0,

        // Unused. Set to zero.
        .unknown = 0,

        // partition record as defined in the GPT spec
        .partition_records = .{
            .{
                // Set to 0x00 to indicate a non-bootable partition.
                // If set to any value other than 0x00 the behavior of this flag on non-UEFI systems is undefined.
                // Must be ignored by UEFI implementations.
                .boot_indicator = 0x0,
                // Set to 0x000200, corresponding to the Starting LBA field.
                .starting_chs = 0x200,
                // Set to 0xEE (i.e., GPT Protective)
                .os_type = 0xEE,
                // Set to the CHS address of the last logical block on the disk.
                // Set to 0xFFFFFF if it is not possible to represent the value in this field.
                .ending_chs = ending_chs,
                // Set to 0x00000001 (i.e., the LBA of the GPT Partition Header).
                .starting_lba = 0x1,
                // Set to the size of the disk minus one.
                // Set to 0xFFFFFFFF if the size of the disk is too large to be represented in this field.
                .size_in_lba = size_in_lba_clamped,
            },
            // three partition records each set to zero.
            .{},
            .{},
            .{},
        },

        // Set to 0xAA55 (i.e., byte 510 contains 0x55 and byte 511 contains 0xAA).
        .signature = 0xAA55,
    };

    // TODO: should we make sure that cursor in file is at the start?
    try file.writeAll(std.mem.asBytes(&mbr_));
}

fn write_gpt(file: std.fs.File, image_description: ImageDescription, random: std.Random, allocator: std.mem.Allocator) !void {
    std.debug.assert(std.mem.isAligned(image_description.size, disk_block_size));
    const number_of_blocks = image_description.size / disk_block_size;

    // FIXME: add support for variable number of partition entries.
    if (image_description.partitions.len > gpt.minimum_number_of_partition_entries) {
        std.debug.panic("Unimplemented: variable number of partition entries", .{});
    }
    const number_of_partition_entries: u32 = gpt.minimum_number_of_partition_entries;

    // TODO: should we make it `catch unreachable`.
    const partition_array_size_in_blocks = try std.math.divCeil(
        u64,
        @sizeOf(gpt.PartitionEntry) * number_of_partition_entries,
        disk_block_size,
    );
    std.debug.print("partition_array_size_in_blocks = {}\n", .{partition_array_size_in_blocks});

    const first_usable_block = 2 + partition_array_size_in_blocks;
    const last_usable_block = number_of_blocks - 2 - partition_array_size_in_blocks;

    std.debug.assert((last_usable_block - first_usable_block) > 0);

    // Block 0 = Protective MBR
    try write_protective_mbr(file, number_of_blocks);

    // var efi_system_partition_entry =
    const partition_alignment = std.math.divExact(usize, gpt.recommended_alignment_of_partitions, disk_block_size) catch |err| {
        std.debug.panic(
            "Unexpected error ({}): gpt.recommended_alignment_of_partitions should be multiple of disk_block_size",
            .{err},
        );
    };

    var next_free_block = first_usable_block;

    var entries = try allocator.alloc(gpt.PartitionEntry, number_of_partition_entries);
    defer allocator.free(entries);
    @memset(std.mem.sliceAsBytes(entries), 0);

    for (image_description.partitions, 0..) |partition, i| {
        const starting_block = std.mem.alignForward(u64, next_free_block, partition_alignment);

        if (starting_block > last_usable_block) {
            std.debug.panic("exceeded disk image size", .{});
        }

        if (partition.size == 0) {
            std.debug.panic("invalid partition with zero size", .{});
        }

        const blocks_in_partition = try std.math.divCeil(u64, partition.size, disk_block_size);

        const partition_type_guid = switch (partition.kind) {
            .Efi => gpt.partition_types.efi_system_partition,
            .Data => gpt.partition_types.microsoft_basic_data_partition,
        };

        const ending_block = starting_block + blocks_in_partition - 1;
        if (ending_block > last_usable_block) {
            std.debug.panic("partition exceeded disk size", .{});
        }

        entries[i] = gpt.PartitionEntry{
            .partition_type_guid = partition_type_guid,
            .unique_partition_guid = UUID.generateV4(random),
            .starting_lba = starting_block,
            .ending_lba = ending_block,
        };

        try make_fat(file, partition, starting_block);

        next_free_block = ending_block + 1;
    }

    const partition_entry_array_crc32 = std.hash.Crc32.hash(std.mem.sliceAsBytes(entries));

    const disk_guid = UUID.generateV4(random);

    // Block 1 = Primary GPT Header
    var primary_header = gpt.Header{
        .my_lba = 1,
        .alternate_lba = number_of_blocks - 1,
        .first_usable_lba = first_usable_block,
        .last_usable_lba = last_usable_block,
        .disk_guid = disk_guid,
        .partition_entry_lba = 2,
        .number_of_partition_entries = number_of_partition_entries,
        .size_of_partition_entry = @sizeOf(gpt.PartitionEntry),
        .partition_entry_array_crc32 = partition_entry_array_crc32,
    };
    primary_header.update_header_hash();

    // Write primary header to file
    try file.writeAll(std.mem.asBytes(&primary_header));
    const remaining_bytes = [_]u8{0} ** (disk_block_size - @sizeOf(gpt.Header));
    try file.writeAll(&remaining_bytes);

    // Write primary gpt partition entry array to file
    std.debug.assert(std.mem.isAligned(std.mem.sliceAsBytes(entries).len, disk_block_size));
    try file.writeAll(std.mem.sliceAsBytes(entries));

    const backup_header = make_backup_header(primary_header, number_of_blocks, partition_array_size_in_blocks);

    // Go to position of backup partition entry array
    try file.seekTo(backup_header.partition_entry_lba * disk_block_size);

    // Write backup gpt partition entry array to file
    try file.writeAll(std.mem.sliceAsBytes(entries));

    // Write backup header to file
    try file.writeAll(std.mem.asBytes(&backup_header));
    try file.writeAll(&remaining_bytes);
}

fn make_backup_header(primary_header: gpt.Header, number_of_blocks: usize, partition_array_size_in_blocks: usize) gpt.Header {
    var backup_header = primary_header;

    backup_header.my_lba = primary_header.alternate_lba;
    backup_header.alternate_lba = primary_header.my_lba;

    backup_header.partition_entry_lba = number_of_blocks - 1 - partition_array_size_in_blocks;

    backup_header.update_header_hash();

    return backup_header;
}

fn make_fat(file: std.fs.File, partition: Partition, starting_block: u64) !void {
    std.debug.assert(std.mem.isAligned(partition.size, disk_block_size));

    const reserved_sectors = 32;
    const partition_alignment = gpt.recommended_alignment_of_partitions / disk_block_size;

    const vbr = fat.Vbr{
        .BS_OEMName = [_]u8{ 'O', 'E', 'M', ' ', 'N', 'A', 'M', 'E' },
        .BPB_BytesPerSec = disk_block_size,
        .BPB_SecPerClus = 1,
        .BPB_RsvdSecCnt = reserved_sectors,
        .BPB_NumFATs = 2,
        .BPB_RootEntCnt = 0,
        .BPB_Media = 0xF8, // "Fixed" non-removable media
        .BPB_SecPerTrk = 0,
        .BPB_NumHeads = 0,
        .BPB_HiddSec = @intCast(starting_block - 1),
        .BPB_TotSec32 = @intCast(partition.size / disk_block_size),

        .BPB_FATSz32 = (partition_alignment - reserved_sectors) / 2, // Align data region on alignment value
        .BPB_ExtFlags = 0, // Mirrored FATs
        .BPB_FSVer = 0,
        .BPB_RootClus = 2, // Clusters 0 & 1 are reserved; root dir cluster starts at 2
        .BPB_FSInfo = 1, // Sector 0 = this VBR; FS Info sector follows it
        .BPB_BkBootSec = 6,
        .BS_DrvNum = 0x80, // 1st hard drive
        .BS_BootSig = 0x29,
        .BS_VolID = 0,
        .BS_VolLab = [_]u8{ 'N', 'O', ' ', 'N', 'A', 'M', 'E', ' ', ' ', ' ', ' ' },
    };

    const fs_info = fat.FSInfo{
        .FSI_Free_Count = 0xFFFFFFFF,
        .FSI_Nxt_Free = 0xFFFFFFFF,
    };

    // Write VBR and FSInfo sector
    try file.seekTo(starting_block * disk_block_size);

    try file.writeAll(std.mem.asBytes(&vbr));
    try file.writeAll(std.mem.asBytes(&fs_info));

    // Go to backup boot sector location
    try file.seekBy(vbr.BPB_BkBootSec * disk_block_size);

    // Write VBR and FSInfo at backup location
    try file.writeAll(std.mem.asBytes(&vbr));
    try file.writeAll(std.mem.asBytes(&fs_info));
}

const Partition = struct {
    /// Total size of the partition.
    ///
    /// Must be a multiple of 512 bytes.
    size: u64,
    kind: Kind,

    const Kind = enum {
        Efi,
        Data,
    };
};

const ImageDescription = struct {
    /// Total size of the image.
    ///
    /// Must be a multiple of 512 bytes.
    size: u64,

    partitions: []const Partition,
};

pub fn main() !void {
    // Describe the required disk image
    var image_description = ImageDescription{
        .size = undefined, // will calculate later
        .partitions = &.{
            .{
                .size = 33 * mib,
                .kind = .Efi,
            },
            .{
                .size = 1 * mib,
                .kind = .Data,
            },
        },
    };
    var sum: usize = 0;
    for (image_description.partitions) |partition| {
        sum += partition.size;
    }
    image_description.size = sum + (gpt.recommended_alignment_of_partitions * 2) + (disk_block_size * 67);

    var rand = std.Random.DefaultPrng.init(std.crypto.random.int(u64));
    const random = rand.random();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // open file
    const file = try std.fs.cwd().createFile("out.img", .{ .truncate = true });
    defer file.close();

    // make gpt
    try write_gpt(file, image_description, random, allocator);
}
