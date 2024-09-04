#define _CRT_SECURE_NO_DEPRECATE
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
    uint8_t boot_indicator;
    uint8_t starting_chs[3];
    uint8_t os_type;
    uint8_t ending_chs[3];
    uint32_t starting_lba;
    uint32_t size_in_lba;
} __attribute__((packed)) MbrPartition;

static_assert(sizeof(MbrPartition) == 16, "Packing of MBR partition is not correct");

typedef struct {
    uint8_t boot_code[440];
    uint32_t disk_signature;
    uint16_t unknown;
    MbrPartition partition_records[4];
    uint16_t signature;
} __attribute__((packed)) Mbr;

static_assert(sizeof(Mbr) == 512, "Packing of MBR is not correct");

// Return false on failure
bool write_mbr(FILE *file) {
    Mbr mbr = {
        .boot_code = { 0 },
        .disk_signature = 0,
        .unknown = 0,
        .partition_records[0] = {
            .boot_indicator = 0,
            .starting_chs = { 0x00, 0x02, 0x00 },
            .os_type = 0xEE,
            .ending_chs = { 0xFF, 0xFF, 0xFF },
            .starting_lba = 0x00000001,
            .size_in_lba = 0xdead,
        },
        .signature = 0xAA55,
    };

    size_t bytes_written = fwrite(&mbr, 1, sizeof(Mbr), file);
    if (bytes_written != sizeof(Mbr)) {
        return false;
    }

    return true;
}

int main() {
    char const *file_name = "out.img";
    FILE *file = fopen(file_name, "wb+");
    if (file == NULL) {
        fprintf(stderr, "Error: could not open file %s\n", file_name);
        return 1;
    }

    if (!write_mbr(file)) {
        fprintf(stderr, "Failed to write to file %s\n", file_name);
    }

    fclose(file);

    return 0;
}
