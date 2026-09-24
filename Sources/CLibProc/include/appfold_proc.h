#ifndef APPFOLD_PROC_H
#define APPFOLD_PROC_H

#include <stdint.h>

typedef struct appfold_proc {
    int32_t pid;
    int32_t ppid;
    int64_t start_unix;
    uint64_t memory_bytes;
    uint64_t cpu_time_ns;
    uint64_t disk_bytes;
    uint64_t disk_read_bytes;
    uint64_t disk_write_bytes;
    uint64_t energy;
    char name[128];
    char path[1024];
} appfold_proc;

typedef struct appfold_host {
    uint64_t cpu_user;
    uint64_t cpu_system;
    uint64_t cpu_idle;
    uint64_t cpu_nice;
    uint64_t memory_used;
    uint64_t memory_total;
    uint64_t network_bytes;
} appfold_host;

int appfold_suggested_capacity(void);
int appfold_list_processes(appfold_proc *out, int capacity);
int appfold_read_host(appfold_host *out);

#endif
