const std = @import("std");
const mbr = @import("mbr.zig");
const gpt = @import("gpt.zig");
const uuid = @import("uuid.zig");
const unit = @import("unit.zig");

const Mbr = mbr.Mbr;
const UUID = uuid.UUID;
const mib = unit.mib;

// Global constants
const lba_size = 512;

const efi_system_partition_size = 33 * mib;
const data_partition_size = 1 * mib;

const padding = (gpt.recommended_alignment_of_partitions * 2) + (lba_size * 67);
const image_size = efi_system_partition_size + data_partition_size + padding;

fn make_gpt(number_of_blocks: u64) void {
    var rand = std.Random.DefaultPrng.init(std.crypto.random.int(u64));
    const random = rand.random();

    const first_usable_block = 1 + 1 + 32;

    const gpt_hdr = gpt.Header{
        .my_lba = 1,
        .alternate_lba = number_of_blocks - 1,
        // MBR + GPT header + primary gpt table
        .first_usable_lba = first_usable_block,

        // 2nd GPT header + table
        .last_usable_lba = number_of_blocks - 1 - 1 - 32,
        .disk_guid = UUID.generateV4(random),

        // After MBR + GPT header
        .partition_entry_lba = 2,
        .number_of_partition_entries = gpt.minimum_number_of_partition_entries,
        .size_of_partition_entry = @sizeOf(gpt.PartitionEntry),
        .partition_entry_array_crc32 = 0,
    };
    std.debug.print("{any}\n", .{gpt_hdr});

    // Fill out primary table partition entries
    // Gpt_Partition_Entry gpt_table[NUMBER_OF_GPT_TABLE_ENTRIES] = {
    //     // EFI System Paritition
    //     {
    //         .partition_type_guid = ESP_GUID,
    //         .unique_guid = new_guid(),
    //         .starting_lba = esp_lba,
    //         .ending_lba = esp_lba + esp_size_lbas,
    //         .attributes = 0,
    //         .name = u"EFI SYSTEM",
    //     },

    //     // Basic Data Paritition
    //     {
    //         .partition_type_guid = BASIC_DATA_GUID,
    //         .unique_guid = new_guid(),
    //         .starting_lba = data_lba,
    //         .ending_lba = data_lba + data_size_lbas,
    //         .attributes = 0,
    //         .name = u"BASIC DATA",
    //     },
    // };
    const partition_alignment = gpt.recommended_alignment_of_partitions / lba_size;
    // var gpt_partition_entries: [gpt.minimum_number_of_partition_entries]gpt.PartitionEntry = .{} ** gpt.minimum_number_of_partition_entries;
    // gpt_partition_entries[0] = .{

    // };
    const starting_block = std.mem.alignForward(usize, first_usable_block, partition_alignment);

    const p = gpt.PartitionEntry{
        .partition_type_guid = gpt.partition_types.efi_system_partition,
        .unique_partition_guid = UUID.generateV4(random),
        .starting_lba = starting_block,
    };
}

pub fn main() !void {
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
                // .starting_chs = 0x200,
                .start_head = 0,
                .start_sector = 2,
                .start_track = 0,
                // Set to 0xEE (i.e., GPT Protective)
                .os_type = 0xEE,
                // Set to the CHS address of the last logical block on the disk.
                // Set to 0xFFFFFF if it is not possible to represent the value in this field.
                // .ending_chs = ending_chs,
                .end_head = 0xFF,
                .end_sector = 0xFF,
                .end_track = 0xFF,
                // Set to 0x00000001 (i.e., the LBA of the GPT Partition Header).
                .starting_lba = 0x1,
                // Set to the size of the disk minus one.
                // Set to 0xFFFFFFFF if the size of the disk is too large to be represented in this field.
                .size_in_lba = 0xdead,
            },
            .{},
            .{},
            .{},
        },

        // three partition records each set to zero.
        // .record2 = .{},
        // .record3 = .{},
        // .record4 = .{},

        // Set to 0xAA55 (i.e., byte 510 contains 0x55 and byte 511 contains 0xAA).
        .signature = 0xAA55,
    };
    std.debug.print("{any}\n", .{mbr_});

    const file = try std.fs.cwd().createFile("out.img", .{ .truncate = true });
    defer file.close();

    try file.writeAll(std.mem.asBytes(&mbr_));

    if (!std.mem.isAligned(image_size, lba_size)) {
        std.debug.panic("image size is not a multiple of 512 bytes", .{});
        return;
    }

    const number_of_blocks = image_size / lba_size;
    make_gpt(number_of_blocks);
}

// fn create_and_map_disk_image(disk_image_path: []const u8, disk_size: usize) ![]align(std.mem.page_size) u8 {
//     var parent_directory = try std.fs.cwd().makeOpenPath(std.fs.path.dirname(disk_image_path).?, .{});
//     defer parent_directory.close();

//     const file = try parent_directory.createFile(std.fs.path.basename(disk_image_path), .{ .truncate = true, .read = true });
//     defer file.close();

//     // const file = try std.fs.cwd().createFile(disk_image_path, .{ .truncate = true });
//     // defer file.close();

//     try file.setEndPos(disk_size.value);

//     return std.posix.mmap(
//         null,
//         disk_size.value,
//         std.posix.PROT.READ | std.posix.PROT.WRITE,
//         .{ .TYPE = .SHARED },
//         file.handle,
//         0,
//     );
// }

// inline fn as_ptr(comptime T: type, file_contents: []u8, index: usize, item_size: usize) T {
//     return @ptrCast(@alignCast(file_contents.ptr + (index * item_size)));
// }
