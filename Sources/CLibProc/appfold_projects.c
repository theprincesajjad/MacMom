#include <arpa/inet.h>
#include <libproc.h>
#include <netinet/in.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>

/* One process must not turn a project scan into an unbounded fd walk. */
enum { APPFOLD_MAX_FDS = 256 };

int appfold_process_cwd(int32_t pid, char *buffer, int length);
int appfold_listening_ports(int32_t pid, int32_t *ports, int capacity);

/* inp_lport is copied into socket_info in network byte order. */
static int host_port(int raw) {
    unsigned low = (unsigned)raw & 0xffffu;
    if (low == 0) {
        return 0;
    }
    int port = (int)ntohs((uint16_t)low);
    if (port <= 0 || port > 65535) {
        return 0;
    }
    return port;
}

static int listening_tcp_port(const struct socket_info *si) {
    if (si->soi_family != AF_INET && si->soi_family != AF_INET6) {
        return 0;
    }
    int tcp_kind = si->soi_kind == SOCKINFO_TCP;
    if ((!tcp_kind && si->soi_protocol != IPPROTO_TCP) || si->soi_type != SOCK_STREAM) {
        return 0;
    }

    const struct in_sockinfo *ini = tcp_kind ? &si->soi_proto.pri_tcp.tcpsi_ini : &si->soi_proto.pri_in;
    int local = host_port(ini->insi_lport);
    if (local == 0) {
        return 0;
    }
    int foreign = host_port(ini->insi_fport);

    int listening = 0;
    int saw_tcp_state = 0;
    if (tcp_kind) {
        saw_tcp_state = 1;
        if (si->soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN) {
            listening = 1;
        }
    }
    if (((unsigned short)si->soi_options & SO_ACCEPTCONN) != 0 || si->soi_qlimit > 0) {
        listening = 1;
    }
    if (listening) {
        return local;
    }
    /* TCP state is present and it is not LISTEN. Do not guess a client port. */
    if (saw_tcp_state) {
        return 0;
    }
    /* No listen flag in the public info. A bound server has no peer. */
    if (foreign != 0) {
        return 0;
    }
    if ((si->soi_state & (SOI_S_ISCONNECTED | SOI_S_ISCONNECTING)) != 0) {
        return 0;
    }
    return local;
}

int appfold_process_cwd(int32_t pid, char *buffer, int length) {
    if (buffer == NULL || length <= 0) {
        return 0;
    }
    buffer[0] = '\0';
    if (pid <= 0) {
        return 0;
    }

    struct proc_vnodepathinfo info;
    memset(&info, 0, sizeof(info));
    int got = proc_pidinfo((int)pid, PROC_PIDVNODEPATHINFO, 0, &info, (int)sizeof(info));
    if (got <= 0) {
        return 0;
    }
    info.pvi_cdir.vip_path[MAXPATHLEN - 1] = '\0';
    const char *path = info.pvi_cdir.vip_path;
    if (path[0] == '\0') {
        return 0;
    }

    int max_copy = length - 1;
    int written = 0;
    while (written < max_copy && path[written] != '\0') {
        buffer[written] = path[written];
        written++;
    }
    buffer[written] = '\0';
    return written;
}

int appfold_listening_ports(int32_t pid, int32_t *ports, int capacity) {
    if (pid <= 0 || ports == NULL || capacity <= 0) {
        return 0;
    }

    struct proc_fdinfo fds[APPFOLD_MAX_FDS];
    memset(fds, 0, sizeof(fds));
    int listed = proc_pidinfo((int)pid, PROC_PIDLISTFDS, 0, fds, (int)sizeof(fds));
    if (listed <= 0) {
        return 0;
    }
    int count = listed / (int)sizeof(struct proc_fdinfo);
    if (count > APPFOLD_MAX_FDS) {
        count = APPFOLD_MAX_FDS;
    }
    if (count < 0) {
        count = 0;
    }

    int written = 0;
    for (int index = 0; index < count && written < capacity; index++) {
        if (fds[index].proc_fdtype != PROX_FDTYPE_SOCKET) {
            continue;
        }
        struct socket_fdinfo socket_info;
        memset(&socket_info, 0, sizeof(socket_info));
        int got = proc_pidfdinfo(
            (int)pid,
            fds[index].proc_fd,
            PROC_PIDFDSOCKETINFO,
            &socket_info,
            (int)sizeof(socket_info));
        if (got <= 0) {
            continue;
        }
        int port = listening_tcp_port(&socket_info.psi);
        if (port <= 0) {
            continue;
        }
        int already = 0;
        for (int seen = 0; seen < written; seen++) {
            if (ports[seen] == (int32_t)port) {
                already = 1;
                break;
            }
        }
        if (already) {
            continue;
        }
        ports[written++] = (int32_t)port;
    }
    return written;
}
