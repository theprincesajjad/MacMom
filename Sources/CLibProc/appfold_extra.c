#include "appfold_extra.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <SystemConfiguration/SCNetworkConfiguration.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include <ifaddrs.h>
#include <mach/mach.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

static void copy_cstr(char *dst, size_t dstlen, const char *src) {
    size_t i = 0;
    if (dstlen == 0) {
        return;
    }
    if (src == NULL) {
        dst[0] = '\0';
        return;
    }
    while (i + 1 < dstlen && src[i] != '\0') {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static int cf_int64(CFTypeRef value, int64_t *out) {
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    CFNumberType kind = CFNumberGetType((CFNumberRef)value);
    if (kind == kCFNumberFloat32Type || kind == kCFNumberFloat64Type ||
        kind == kCFNumberFloatType || kind == kCFNumberDoubleType) {
        double number = 0;
        if (!CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &number)) {
            return 0;
        }
        if (number < 0 || number > (double)INT64_MAX) {
            return 0;
        }
        *out = (int64_t)number;
        return 1;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out) ? 1 : 0;
}

static int cf_double(CFTypeRef value, double *out) {
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, out) ? 1 : 0;
}

static int dict_int64(CFDictionaryRef dict, CFStringRef key, int64_t *out) {
    if (dict == NULL) {
        return 0;
    }
    return cf_int64(CFDictionaryGetValue(dict, key), out);
}

static int dict_bool(CFDictionaryRef dict, CFStringRef key, int *out) {
    if (dict == NULL) {
        return 0;
    }
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    if (value == NULL) {
        return 0;
    }
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        *out = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
        return 1;
    }
    int64_t number = 0;
    if (!cf_int64(value, &number)) {
        return 0;
    }
    *out = number != 0;
    return 1;
}

static int copy_cf_string(CFTypeRef value, char *dst, size_t dstlen) {
    if (value == NULL || dstlen == 0) {
        return 0;
    }
    dst[0] = '\0';
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        if (!CFStringGetCString((CFStringRef)value, dst, dstlen, kCFStringEncodingUTF8)) {
            dst[0] = '\0';
            return 0;
        }
        return dst[0] != '\0';
    }
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        CFIndex length = CFDataGetLength((CFDataRef)value);
        const UInt8 *bytes = CFDataGetBytePtr((CFDataRef)value);
        size_t count;
        if (length <= 0 || bytes == NULL) {
            return 0;
        }
        count = (size_t)length;
        if (count >= dstlen) {
            count = dstlen - 1;
        }
        memcpy(dst, bytes, count);
        dst[count] = '\0';
        return dst[0] != '\0';
    }
    return 0;
}

/* macOS publishes this word in Smart Battery units (0.1 K).
   AppleSmartBattery.cpp converts to centi-Celsius only off macOS.
   A raw value below that band is deci-Celsius. */
static int battery_celsius(int64_t raw, double *out) {
    if (raw >= 2300 && raw <= 4000) {
        *out = (double)raw / 10.0 - 273.15;
        return 1;
    }
    if (raw >= -400 && raw <= 1200) {
        *out = (double)raw / 10.0;
        return 1;
    }
    return 0;
}

static int capacities_share_units(int64_t max_capacity, int64_t design_capacity) {
    if (max_capacity > 100 && design_capacity > 100) {
        return 1;
    }
    if (max_capacity > 0 && max_capacity <= 100 && design_capacity > 0 && design_capacity <= 100) {
        return 1;
    }
    return 0;
}

static io_service_t copy_battery_service(void) {
    CFMutableDictionaryRef match = IOServiceMatching("AppleSmartBattery");
    io_service_t service = IO_OBJECT_NULL;
    if (match != NULL) {
        service = IOServiceGetMatchingService(kIOMainPortDefault, match);
        if (service != IO_OBJECT_NULL) {
            return service;
        }
    }
    match = IOServiceMatching("IOPMPowerSource");
    if (match == NULL) {
        return IO_OBJECT_NULL;
    }
    return IOServiceGetMatchingService(kIOMainPortDefault, match);
}

int appfold_read_battery(appfold_battery *out) {
    io_service_t service;
    CFMutableDictionaryRef props = NULL;
    int64_t current = 0;
    int64_t max_capacity = 0;
    int64_t design = 0;
    int64_t raw_max = 0;
    int64_t cycles = 0;
    int64_t minutes = 0;
    int64_t amperage = 0;
    int64_t voltage = 0;
    int64_t temperature = 0;
    int installed = 1;
    int has_installed = 0;
    int external = 0;
    int has_external = 0;

    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->on_ac_power = 1;

    service = copy_battery_service();
    if (service == IO_OBJECT_NULL) {
        return 0;
    }

    if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS || props == NULL) {
        IOObjectRelease(service);
        out->has_battery = 1;
        out->on_ac_power = 0;
        return 0;
    }
    IOObjectRelease(service);

    has_installed = dict_bool(props, CFSTR("BatteryInstalled"), &installed);
    if (has_installed && !installed) {
        CFRelease(props);
        return 0;
    }
    out->has_battery = 1;

    has_external = dict_bool(props, CFSTR("ExternalConnected"), &external);
    out->on_ac_power = has_external ? external : 0;

    if (dict_int64(props, CFSTR("CurrentCapacity"), &current) &&
        dict_int64(props, CFSTR("MaxCapacity"), &max_capacity) &&
        max_capacity > 0) {
        out->has_percent = 1;
        out->percent = 100.0 * (double)current / (double)max_capacity;
    }

    /* 0xFFFF / 0xFFFFFFFF and negatives are the "calculating" sentinels. */
    if (dict_int64(props, CFSTR("TimeRemaining"), &minutes) && minutes >= 0 && minutes < 65535) {
        out->has_minutes = 1;
        out->minutes_remaining = (int32_t)minutes;
    }

    if (dict_int64(props, CFSTR("CycleCount"), &cycles) && cycles >= 0 && cycles <= INT32_MAX) {
        out->has_cycle_count = 1;
        out->cycle_count = (int32_t)cycles;
    }

    /* Top-level MaxCapacity is 0...100 on Apple Silicon, while DesignCapacity
       stays in mAh. AppleRawMaxCapacity is that max in the same units. */
    if (dict_int64(props, CFSTR("DesignCapacity"), &design) && design > 0) {
        int has_raw = dict_int64(props, CFSTR("AppleRawMaxCapacity"), &raw_max);
        int has_max = dict_int64(props, CFSTR("MaxCapacity"), &max_capacity);
        if (has_raw && raw_max > 0 && design > 100) {
            out->has_health = 1;
            out->health_percent = 100.0 * (double)raw_max / (double)design;
        } else if (has_max && capacities_share_units(max_capacity, design)) {
            out->has_health = 1;
            out->health_percent = 100.0 * (double)max_capacity / (double)design;
        }
    }

    if (dict_int64(props, CFSTR("Amperage"), &amperage) &&
        dict_int64(props, CFSTR("Voltage"), &voltage)) {
        double amps = (double)amperage;
        if (amps < 0) {
            amps = -amps;
        }
        out->has_watts = 1;
        out->watts = amps * (double)voltage / 1000000.0;
    }

    if (dict_int64(props, CFSTR("Temperature"), &temperature)) {
        double celsius = 0;
        if (battery_celsius(temperature, &celsius)) {
            out->has_temperature = 1;
            out->temperature_c = celsius;
        }
    }

    CFRelease(props);
    return 0;
}

static int skip_fstype(const char *fstype) {
    return strcmp(fstype, "devfs") == 0 || strcmp(fstype, "autofs") == 0;
}

static void fill_volume(appfold_volume *out, const struct statfs *fs) {
    const char *mount = fs->f_mntonname;
    const char *slash = strrchr(mount, '/');
    uint64_t block = (uint64_t)fs->f_bsize;
    memset(out, 0, sizeof(*out));
    if (slash != NULL && slash[1] != '\0') {
        copy_cstr(out->name, sizeof(out->name), slash + 1);
    } else {
        copy_cstr(out->name, sizeof(out->name), mount);
    }
    out->free_bytes = fs->f_bavail * block;
    out->total_bytes = fs->f_blocks * block;
}

int appfold_read_volumes(appfold_volume *out, int capacity) {
    int guess;
    int slots;
    int got;
    int root = -1;
    int written = 0;
    int index;
    struct statfs *buf;

    if (out == NULL || capacity <= 0) {
        return 0;
    }
    guess = getfsstat(NULL, 0, MNT_NOWAIT);
    slots = guess > 0 ? guess + 16 : 32;
    buf = calloc((size_t)slots, sizeof(struct statfs));
    if (buf == NULL) {
        return 0;
    }
    got = getfsstat(buf, slots * (int)sizeof(struct statfs), MNT_NOWAIT);
    if (got < 0) {
        free(buf);
        return 0;
    }
    if (got > slots) {
        got = slots;
    }

    for (index = 0; index < got; index++) {
        if (!skip_fstype(buf[index].f_fstypename) && strcmp(buf[index].f_mntonname, "/") == 0) {
            root = index;
            break;
        }
    }
    if (root >= 0 && written < capacity) {
        fill_volume(&out[written], &buf[root]);
        written++;
    }
    for (index = 0; index < got && written < capacity; index++) {
        if (index == root || skip_fstype(buf[index].f_fstypename)) {
            continue;
        }
        fill_volume(&out[written], &buf[index]);
        written++;
    }
    free(buf);
    return written;
}

int appfold_read_memory(appfold_memory *out) {
    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0;
    struct xsw_usage swap;
    size_t swap_size = sizeof(swap);
    uint64_t total = 0;
    size_t total_size = sizeof(total);

    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    memset(&vm, 0, sizeof(vm));

    if (host_page_size(mach_host_self(), &page) == KERN_SUCCESS && page > 0 &&
        host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        uint64_t bytes = (uint64_t)page;
        out->app_bytes = (uint64_t)vm.internal_page_count * bytes;
        out->wired_bytes = (uint64_t)vm.wire_count * bytes;
        out->compressed_bytes = (uint64_t)vm.compressor_page_count * bytes;
        out->cached_bytes = (uint64_t)vm.external_page_count * bytes;
        out->free_bytes = (uint64_t)vm.free_count * bytes;
    }

    memset(&swap, 0, sizeof(swap));
    if (sysctlbyname("vm.swapusage", &swap, &swap_size, NULL, 0) == 0) {
        out->swap_bytes = swap.xsu_used;
    }
    if (sysctlbyname("hw.memsize", &total, &total_size, NULL, 0) == 0) {
        out->total_bytes = total;
    }
    return 0;
}

typedef struct appfold_nic {
    char name[32];
    int is_up;
    uint64_t bytes_in;
    uint64_t bytes_out;
} appfold_nic;

static int collect_iflist2(appfold_nic *out, int capacity) {
    int mib[6] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t needed = 0;
    char *buf;
    char *cursor;
    char *end;
    int count = 0;

    if (sysctl(mib, 6, NULL, &needed, NULL, 0) != 0 || needed == 0) {
        return -1;
    }
    needed += 4096;
    buf = malloc(needed);
    if (buf == NULL) {
        return -1;
    }
    if (sysctl(mib, 6, buf, &needed, NULL, 0) != 0) {
        free(buf);
        return -1;
    }

    cursor = buf;
    end = buf + needed;
    /* Address messages are shorter than if_msghdr, so only the 4-byte prefix is required. */
    while (cursor + 4 <= end && count < capacity) {
        unsigned short message_length = 0;
        unsigned char message_type = (unsigned char)cursor[3];
        memcpy(&message_length, cursor, sizeof(message_length));
        if (message_length < 4 || cursor + message_length > end) {
            break;
        }
        if (message_type == RTM_IFINFO2 && message_length >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *msg = (struct if_msghdr2 *)cursor;
            char name[32];
            name[0] = '\0';
            if ((msg->ifm_addrs & RTA_IFP) != 0) {
                struct sockaddr_dl *link = (struct sockaddr_dl *)(msg + 1);
                const char *message_end = cursor + message_length;
                if ((char *)link + offsetof(struct sockaddr_dl, sdl_data) <= message_end) {
                    unsigned length = link->sdl_nlen;
                    if (length > 0 && length < sizeof(name) &&
                        (char *)link->sdl_data + length <= message_end) {
                        memcpy(name, link->sdl_data, length);
                        name[length] = '\0';
                    }
                }
            }
            if (name[0] == '\0' && if_indextoname(msg->ifm_index, name) == NULL) {
                name[0] = '\0';
            }
            if (name[0] != '\0' && (msg->ifm_flags & IFF_LOOPBACK) == 0) {
                appfold_nic *row = &out[count++];
                memset(row, 0, sizeof(*row));
                copy_cstr(row->name, sizeof(row->name), name);
                row->is_up = (msg->ifm_flags & IFF_UP) != 0;
                row->bytes_in = msg->ifm_data.ifi_ibytes;
                row->bytes_out = msg->ifm_data.ifi_obytes;
            }
        }
        cursor += message_length;
    }
    free(buf);
    return count;
}

static int collect_ifaddrs(appfold_nic *out, int capacity) {
    struct ifaddrs *list = NULL;
    struct ifaddrs *iface;
    int count = 0;
    if (getifaddrs(&list) != 0) {
        return -1;
    }
    for (iface = list; iface != NULL && count < capacity; iface = iface->ifa_next) {
        struct if_data *data;
        appfold_nic *row;
        if (iface->ifa_addr == NULL || iface->ifa_addr->sa_family != AF_LINK) {
            continue;
        }
        if (iface->ifa_name == NULL || (iface->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        data = (struct if_data *)iface->ifa_data;
        row = &out[count++];
        memset(row, 0, sizeof(*row));
        copy_cstr(row->name, sizeof(row->name), iface->ifa_name);
        row->is_up = (iface->ifa_flags & IFF_UP) != 0;
        if (data != NULL) {
            row->bytes_in = data->ifi_ibytes;
            row->bytes_out = data->ifi_obytes;
        }
    }
    freeifaddrs(list);
    return count;
}

static int copy_primary_name(char *dst, size_t dstlen) {
    SCDynamicStoreRef store;
    const CFStringRef entities[] = {kSCEntNetIPv4, kSCEntNetIPv6};
    int found = 0;
    size_t index;

    dst[0] = '\0';
    store = SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("appfold"), NULL, NULL);
    if (store == NULL) {
        return 0;
    }
    for (index = 0; index < sizeof(entities) / sizeof(entities[0]) && !found; index++) {
        CFStringRef key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            kCFAllocatorDefault, kSCDynamicStoreDomainState, entities[index]);
        CFDictionaryRef dict;
        if (key == NULL) {
            continue;
        }
        dict = SCDynamicStoreCopyValue(store, key);
        CFRelease(key);
        if (dict == NULL) {
            continue;
        }
        if (CFGetTypeID(dict) == CFDictionaryGetTypeID()) {
            CFTypeRef primary = CFDictionaryGetValue(dict, kSCDynamicStorePropNetPrimaryInterface);
            if (primary != NULL && CFGetTypeID(primary) == CFStringGetTypeID() &&
                CFStringGetCString((CFStringRef)primary, dst, dstlen, kCFStringEncodingUTF8) &&
                dst[0] != '\0') {
                found = 1;
            }
        }
        CFRelease(dict);
    }
    CFRelease(store);
    return found;
}

static void interface_kind(const char *bsd_name, char *dst, size_t dstlen) {
    CFArrayRef all;
    CFStringRef wanted;
    CFIndex count;
    CFIndex index;

    copy_cstr(dst, dstlen, bsd_name);
    all = SCNetworkInterfaceCopyAll();
    if (all == NULL) {
        return;
    }
    wanted = CFStringCreateWithCString(kCFAllocatorDefault, bsd_name, kCFStringEncodingUTF8);
    if (wanted == NULL) {
        CFRelease(all);
        return;
    }
    count = CFArrayGetCount(all);
    for (index = 0; index < count; index++) {
        SCNetworkInterfaceRef iface = (SCNetworkInterfaceRef)CFArrayGetValueAtIndex(all, index);
        CFStringRef name = SCNetworkInterfaceGetBSDName(iface);
        CFStringRef type;
        if (name == NULL || !CFEqual(name, wanted)) {
            continue;
        }
        type = SCNetworkInterfaceGetInterfaceType(iface);
        if (type != NULL && CFEqual(type, kSCNetworkInterfaceTypeIEEE80211)) {
            copy_cstr(dst, dstlen, "Wi-Fi");
        } else if (type != NULL && CFEqual(type, kSCNetworkInterfaceTypeEthernet)) {
            copy_cstr(dst, dstlen, "Ethernet");
        }
        break;
    }
    CFRelease(wanted);
    CFRelease(all);
}

static int pick_interface(const appfold_nic *nics, int count, const char *primary) {
    int chosen = -1;
    int index;
    uint64_t best = 0;

    if (primary != NULL && primary[0] != '\0') {
        for (index = 0; index < count; index++) {
            if (strcmp(nics[index].name, primary) == 0) {
                return index;
            }
        }
    }
    for (index = 0; index < count; index++) {
        uint64_t traffic;
        if (!nics[index].is_up) {
            continue;
        }
        traffic = nics[index].bytes_in + nics[index].bytes_out;
        if (traffic == 0) {
            continue;
        }
        if (chosen < 0 || traffic > best) {
            chosen = index;
            best = traffic;
        }
    }
    if (chosen >= 0) {
        return chosen;
    }
    for (index = 0; index < count; index++) {
        if (nics[index].is_up) {
            return index;
        }
    }
    return count > 0 ? 0 : -1;
}

int appfold_read_primary_interface(appfold_interface *out) {
    appfold_nic nics[64];
    int count;
    int chosen;
    char primary[32];

    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    count = collect_iflist2(nics, 64);
    if (count <= 0) {
        count = collect_ifaddrs(nics, 64);
    }
    if (count <= 0) {
        return 0;
    }
    if (count > 64) {
        count = 64;
    }
    copy_primary_name(primary, sizeof(primary));
    chosen = pick_interface(nics, count, primary);
    if (chosen < 0) {
        return 0;
    }
    copy_cstr(out->bsd_name, sizeof(out->bsd_name), nics[chosen].name);
    interface_kind(nics[chosen].name, out->kind, sizeof(out->kind));
    out->bytes_in = nics[chosen].bytes_in;
    out->bytes_out = nics[chosen].bytes_out;
    return 0;
}

static int dict_named_double(CFDictionaryRef dict, const char *const *keys, double *out) {
    size_t index;
    for (index = 0; keys[index] != NULL; index++) {
        CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, keys[index], kCFStringEncodingUTF8);
        CFTypeRef value;
        if (key == NULL) {
            continue;
        }
        value = CFDictionaryGetValue(dict, key);
        CFRelease(key);
        if (cf_double(value, out)) {
            return 1;
        }
    }
    return 0;
}

static int dict_named_uint64(CFDictionaryRef dict, const char *const *keys, uint64_t *out) {
    size_t index;
    for (index = 0; keys[index] != NULL; index++) {
        CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, keys[index], kCFStringEncodingUTF8);
        int64_t number = 0;
        CFTypeRef value;
        if (key == NULL) {
            continue;
        }
        value = CFDictionaryGetValue(dict, key);
        CFRelease(key);
        if (cf_int64(value, &number) && number >= 0) {
            *out = (uint64_t)number;
            return 1;
        }
    }
    return 0;
}

static void consider_gpu(io_service_t service, appfold_gpu *best, int *best_score) {
    static const char *util_keys[] = {
        "Device Utilization %",
        "GPU Activity(%)",
        "GPU Activity (%)",
        "GPU Activity",
        "GPU Utilization %",
        NULL
    };
    static const char *memory_keys[] = {
        "In use system memory",
        "In use system memory (bytes)",
        "vramUsedBytes",
        "VRAM Used",
        NULL
    };
    CFMutableDictionaryRef props = NULL;
    appfold_gpu candidate;
    int score = 0;
    CFTypeRef stats;

    memset(&candidate, 0, sizeof(candidate));
    if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS || props == NULL) {
        IOObjectRelease(service);
        return;
    }
    if (copy_cf_string(CFDictionaryGetValue(props, CFSTR("model")), candidate.name, sizeof(candidate.name))) {
        score += 4;
    } else {
        io_name_t class_name;
        class_name[0] = '\0';
        if (IOObjectGetClass(service, class_name) == KERN_SUCCESS) {
            copy_cstr(candidate.name, sizeof(candidate.name), class_name);
        }
    }

    stats = CFDictionaryGetValue(props, CFSTR("PerformanceStatistics"));
    if (stats != NULL && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
        double util = 0;
        uint64_t memory = 0;
        score += 2;
        if (dict_named_double((CFDictionaryRef)stats, util_keys, &util)) {
            candidate.has_utilization = 1;
            candidate.utilization_percent = util;
            score += 1;
        }
        if (dict_named_uint64((CFDictionaryRef)stats, memory_keys, &memory)) {
            candidate.has_memory = 1;
            candidate.memory_bytes = memory;
        }
    }

    if (score > *best_score) {
        *best = candidate;
        *best_score = score;
    }
    CFRelease(props);
    IOObjectRelease(service);
}

static void read_gpu_class(const char *class_name, appfold_gpu *best, int *best_score) {
    CFMutableDictionaryRef match = IOServiceMatching(class_name);
    io_iterator_t iterator = IO_OBJECT_NULL;
    io_service_t service;
    if (match == NULL) {
        return;
    }
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) != KERN_SUCCESS) {
        return;
    }
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        consider_gpu(service, best, best_score);
    }
    IOObjectRelease(iterator);
}

int appfold_read_gpu(appfold_gpu *out) {
    int score = -1;
    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    read_gpu_class("IOAccelerator", out, &score);
    if (score < 0) {
        read_gpu_class("AGXAccelerator", out, &score);
    }
    return 0;
}
