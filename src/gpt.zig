const std = @import("std");
const uuid = @import("uuid.zig");
const unit = @import("unit.zig");

const UUID = uuid.UUID;
const Crc32 = std.hash.Crc32;
const kib = unit.kib;
const mib = unit.mib;

/// The minimum size that must be reserved for the GPT partition entry array.
pub const minimum_size_of_partition_entry_array = 16 * kib;

/// The minimum number of partition entries due to the minimum size reserved for the partition array.
pub const minimum_number_of_partition_entries: u32 = minimum_size_of_partition_entry_array / @sizeOf(PartitionEntry);

/// Almost every tool generates partitions with this alignment.
/// https://en.wikipedia.org/wiki/Logical_Disk_Manager#Advantages_of_using_a_1-MB_alignment_boundary
pub const recommended_alignment_of_partitions = 1 * mib;

/// Defines a GUID Partition Table (GPT) header.
pub const Header = extern struct {
    /// Identifies EFI-compatible partition table header.
    ///
    /// This value must contain the ASCII string “EFI PART”, encoded as the 64-bit constant 0x5452415020494645.
    signature: u64 align(1) = 0x5452415020494645,

    /// The revision number for this header.
    ///
    /// This revision value is not related to the UEFI Specification version.
    /// This header is version 1.0, so the correct value is 0x00010000.
    revision: u32 align(1) = 0x00010000,

    /// Size in bytes of the GPT Header.
    ///
    /// This must be greater than or equal to 92 and must be less than or equal to the logical block size.
    header_size: u32 align(1) = @sizeOf(Header),

    /// CRC32 checksum for the GPT Header structure.
    ///
    /// This value is computed by setting this field to 0, and computing the 32-bit CRC for `header_size` bytes.
    header_crc32: u32 align(1) = 0,

    /// Must be zero
    reserved: u32 align(1) = 0,

    /// The LBA that contains this data structure.
    my_lba: u64 align(1),

    /// LBA address of the alternate GPT Header.
    alternate_lba: u64 align(1),

    /// The first usable logical block that may be used by a partition described by a GUID Partition Entry.
    first_usable_lba: u64 align(1),

    /// The last usable logical block that may be used by a partition described by a GUID Partition Entry.
    last_usable_lba: u64 align(1),

    /// GUID that can be used to uniquely identify the disk.
    disk_guid: UUID align(1),

    /// The starting LBA of the GUID Partition Entry array.
    partition_entry_lba: u64 align(1),

    /// The number of Partition Entries in the GUID Partition Entry array.
    number_of_partition_entries: u32 align(1),

    /// The size, in bytes, of each the GUID Partition Entry structures in the GUID Partition Entry array.
    ///
    /// This field shall be set to a value of 128 x 2n where n is an integer greater than
    /// or equal to zero (e.g., 128, 256, 512, etc.).
    ///
    /// NOTE: Previous versions of UEFI specification allowed any multiple of 8.
    size_of_partition_entry: u32 align(1),

    /// The CRC32 of the GUID Partition Entry array.
    ///
    /// Starts at `partition_entry_lba` and is computed over a byte length of `number_of_partition_entries * size_of_partition_entry`.
    partition_entry_array_crc32: u32 align(1),

    const Self = @This();

    comptime {
        std.debug.assert(@sizeOf(Self) == 92);
    }

    /// Updates the `header_crc32` field with the CRC32 checksum.
    ///
    /// Anytime a field in this structure is modified, the CRC should be recomputed.
    ///
    /// This includes any changes to the partition entry array as it's checksum is stored in the header as well.
    pub fn update_header_hash(self: *Self) void {
        // const header_bytes = std.mem.asBytes(self);
        const header_bytes = @as([*]u8, @ptrCast(self))[0..self.header_size];
        self.header_crc32 = 0;
        self.header_crc32 = Crc32.hash(header_bytes);
    }
};

/// Defines a GUID Partition Table (GPT) partition entry.
///
/// This structure contains metadata about a single partition like type, name, starting/ending LBA, attributes, etc.
pub const PartitionEntry = extern struct {
    /// Unique ID that defines the purpose and type of this Partition.
    ///
    /// A value of zero defines that this partition entry is not being used.
    partition_type_guid: UUID align(1),

    /// GUID that is unique for every partition entry.
    /// Every partition ever created will have a unique GUID.
    unique_partition_guid: UUID align(1),

    /// Starting LBA of the partition defined by this entry.
    starting_lba: u64 align(1),

    /// Ending LBA of the partition defined by this entry.
    ending_lba: u64 align(1),

    /// Attribute bits, all bits reserved by UEFI.
    attributes: u64 align(1) = 0,

    /// Null-terminated string containing a human-readable name of the partition.
    ///
    /// UNICODE16-LE encoded.
    partition_name: [36]u16 align(1) = [_]u16{0} ** 36,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 128);
    }
};

/// Partition Type GUIDs
///
/// List available: https://en.wikipedia.org/wiki/GUID_Partition_Table#Partition_type_GUIDs
pub const partition_types = struct {
    /// Unused Entry
    ///
    /// Defined by the UEFI specification.
    pub const unused: UUID = UUID.parse("00000000-0000-0000-0000-000000000000") catch unreachable;

    /// EFI System Partition
    ///
    /// Defined by the UEFI specification.
    pub const efi_system_partition: UUID = UUID.parse("C12A7328-F81F-11D2-BA4B-00A0C93EC93B") catch unreachable;

    /// Partition containing a legacy MBR
    ///
    /// Defined by the UEFI specification.
    pub const partition_containing_legacy_mbr: UUID = UUID.parse("024DEE41-33E7-11D3-9D69-0008C781F39F") catch unreachable;

    /// Microsoft Basic Data Partition
    ///
    /// https://en.wikipedia.org/wiki/Microsoft_basic_data_partition
    ///
    /// According to Microsoft, the basic data partition is the equivalent to master boot record (MBR) partition types
    /// 0x06 (FAT16B), 0x07 (NTFS or exFAT), and 0x0B (FAT32).
    ///
    /// In practice, it is also equivalent to 0x01 (FAT12), 0x04 (FAT16), 0x0C (FAT32 with logical block addressing),
    /// and 0x0E (FAT16 with logical block addressing) types as well.
    pub const microsoft_basic_data_partition: UUID = UUID.parse("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7") catch unreachable;

    pub const linux_filesystem_data: UUID = UUID.parse("0FC63DAF-8483-4772-8E79-3D69D8477DE4") catch unreachable;
};
