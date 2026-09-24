#include "appfold_proc.h"

#include <ifaddrs.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/mach_time.h>
#include <mach/vm_statistics.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>

static uint64_t ticks_to_ns(uint64_t ticks) {
    static uint64_t numer = 0;
    static uint64_t denom = 1;
    if (numer == 0) {
        mach_timebase_info_data_t info;
        if (mach_timebase_info(&info) == KERN_SUCCESS && info.denom != 0) {
            numer = info.numer;
            denom = info.denom;
        } else {
            numer = 1;
            denom = 1;
        }
    }
    return ticks * numer / denom;
}

int appfold_suggested_capacity(void) {
    /* proc_listpids returns a byte count. proc_listallpids does not. */
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes < (int)sizeof(pid_t)) {
        return 256;
    }
    return bytes / (int)sizeof(pid_t) + 64;
}

int appfold_list_processes(appfold_proc *out, int capacity) {
    if (out == NULL || capacity <= 0) {
        return 0;
    }

    int bytesNeeded = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytesNeeded < (int)sizeof(pid_t)) {
        bytesNeeded = 256 * (int)sizeof(pid_t);
    }
    int slots = bytesNeeded / (int)sizeof(pid_t) + 128;
    pid_t *pids = calloc((size_t)slots, sizeof(pid_t));
    if (pids == NULL) {
        return 0;
    }

    int got = proc_listpids(PROC_ALL_PIDS, 0, pids, slots * (int)sizeof(pid_t));
    int npids = got > 0 ? got / (int)sizeof(pid_t) : 0;
    if (npids > slots) {
        npids = slots;
    }
    int written = 0;

    for (int i = 0; i < npids && written < capacity; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) {
            continue;
        }

        struct proc_bsdinfo bsd;
        memset(&bsd, 0, sizeof(bsd));
        int bsdBytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, (int)sizeof(bsd));

        struct proc_taskinfo task;
        memset(&task, 0, sizeof(task));
        proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, (int)sizeof(task));

        struct rusage_info_v4 usage;
        memset(&usage, 0, sizeof(usage));
        int usageOK = proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0;

        appfold_proc *row = &out[written];
        memset(row, 0, sizeof(*row));
        row->pid = (int32_t)pid;
        row->ppid = bsdBytes == (int)sizeof(bsd) ? (int32_t)bsd.pbi_ppid : 0;

        if (usageOK && usage.ri_phys_footprint > 0) {
            row->memory_bytes = usage.ri_phys_footprint;
        } else {
            row->memory_bytes = task.pti_resident_size;
        }

        uint64_t cpuTicks = 0;
        if (usageOK) {
            cpuTicks = usage.ri_user_time + usage.ri_system_time;
            row->disk_bytes = usage.ri_diskio_bytesread + usage.ri_diskio_byteswritten;
            row->energy = usage.ri_billed_energy;
        } else {
            cpuTicks = task.pti_total_user + task.pti_total_system;
        }
        row->cpu_time_ns = ticks_to_ns(cpuTicks);

        proc_name((int)pid, row->name, (uint32_t)sizeof(row->name));
        row->name[sizeof(row->name) - 1] = '\0';
        int pathBytes = proc_pidpath((int)pid, row->path, (uint32_t)sizeof(row->path));
        if (pathBytes <= 0) {
            row->path[0] = '\0';
        } else {
            row->path[sizeof(row->path) - 1] = '\0';
        }

        written++;
    }

    free(pids);
    return written;
}

int appfold_read_host(appfold_host *out) {
    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    host_cpu_load_info_data_t load;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    kern_return_t status = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t)&load, &count);
    if (status == KERN_SUCCESS) {
        out->cpu_user = load.cpu_ticks[CPU_STATE_USER];
        out->cpu_system = load.cpu_ticks[CPU_STATE_SYSTEM];
        out->cpu_idle = load.cpu_ticks[CPU_STATE_IDLE];
        out->cpu_nice = load.cpu_ticks[CPU_STATE_NICE];
    }

    vm_statistics64_data_t vm;
    mach_msg_type_number_t vmCount = HOST_VM_INFO64_COUNT;
    vm_size_t pageSize = 0;
    if (host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS &&
        host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &vmCount) == KERN_SUCCESS) {
        uint64_t pages = (uint64_t)vm.active_count + (uint64_t)vm.wire_count + (uint64_t)vm.compressor_page_count;
        out->memory_used = pages * (uint64_t)pageSize;
    }

    int mib[2] = {CTL_HW, HW_MEMSIZE};
    uint64_t total = 0;
    size_t totalSize = sizeof(total);
    if (sysctl(mib, 2, &total, &totalSize, NULL, 0) == 0) {
        out->memory_total = total;
    }

    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        uint64_t bytes = 0;
        for (struct ifaddrs *iface = interfaces; iface != NULL; iface = iface->ifa_next) {
            if (iface->ifa_addr == NULL || iface->ifa_addr->sa_family != AF_LINK) {
                continue;
            }
            if ((iface->ifa_flags & IFF_LOOPBACK) != 0) {
                continue;
            }
            struct if_data *data = (struct if_data *)iface->ifa_data;
            if (data == NULL) {
                continue;
            }
            bytes += (uint64_t)data->ifi_ibytes + (uint64_t)data->ifi_obytes;
        }
        freeifaddrs(interfaces);
        out->network_bytes = bytes;
    }

    return 0;
}
