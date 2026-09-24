#ifndef APPFOLD_EXTRA_H
#define APPFOLD_EXTRA_H

#include <stdint.h>

/* has_* is 1 only when the OS published that reading.
   A 0 value is real solely when its has_* flag is set. */

typedef struct appfold_battery {
    int has_battery;
    int on_ac_power;
    int has_percent;
    double percent;
    int has_minutes;
    int32_t minutes_remaining;
    int has_cycle_count;
    int32_t cycle_count;
    int has_health;
    double health_percent;
    int has_watts;
    double watts;
    int has_temperature;
    double temperature_c;
} appfold_battery;

typedef struct appfold_volume {
    char name[256];
    uint64_t free_bytes;
    uint64_t total_bytes;
} appfold_volume;

typedef struct appfold_memory {
    uint64_t wired_bytes;
    uint64_t compressed_bytes;
    uint64_t cached_bytes;
    uint64_t free_bytes;
    uint64_t swap_bytes;
    uint64_t total_bytes;
} appfold_memory;

typedef struct appfold_interface {
    char bsd_name[32];
    char kind[32];
    uint64_t bytes_in;
    uint64_t bytes_out;
} appfold_interface;

typedef struct appfold_gpu {
    char name[128];
    int has_utilization;
    double utilization_percent;
    int has_memory;
    uint64_t memory_bytes;
} appfold_gpu;

int appfold_read_battery(appfold_battery *out);
int appfold_read_volumes(appfold_volume *out, int capacity);
int appfold_read_memory(appfold_memory *out);
int appfold_read_primary_interface(appfold_interface *out);
int appfold_read_gpu(appfold_gpu *out);

#endif
