// Read-only macOS per-process CPU and wakeup sampling. No desktop data is read.
#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: measure_process PID SECONDS\n"); return 2; }
    int pid = atoi(argv[1]), seconds = atoi(argv[2]);
    if (pid <= 0 || seconds < 1 || seconds > 60) return 2;
    struct rusage_info_v2 before = {0}, after = {0};
    struct timespec start, end;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&before)) { perror("proc_pid_rusage"); return 1; }
    clock_gettime(CLOCK_MONOTONIC, &start);
    sleep((unsigned)seconds);
    clock_gettime(CLOCK_MONOTONIC, &end);
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&after)) { perror("proc_pid_rusage"); return 1; }
    double elapsed = (end.tv_sec-start.tv_sec) + (end.tv_nsec-start.tv_nsec)/1e9;
    double cpu = (after.ri_user_time-before.ri_user_time + after.ri_system_time-before.ri_system_time)/1e9;
    printf("{\"seconds\":%.3f,\"cpu_percent_one_core\":%.4f,\"cpu_seconds\":%.6f,\"interrupt_wakeups_per_second\":%.3f,\"package_wakeups_per_second\":%.3f,\"physical_memory_mib\":%.2f}\n",
        elapsed, cpu/elapsed*100, cpu,
        (after.ri_interrupt_wkups-before.ri_interrupt_wkups)/elapsed,
        (after.ri_pkg_idle_wkups-before.ri_pkg_idle_wkups)/elapsed,
        after.ri_phys_footprint/1048576.0);
}
