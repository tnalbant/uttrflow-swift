import Darwin

/// How long this process has run, from the kernel's start time, so the work before `main` counts.
public enum ProcessAge {
    /// This process's age now, or `nil` when the kernel does not say when it started.
    public static func current() -> Duration? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&request, u_int(request.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        var now = timeval()
        gettimeofday(&now, nil)
        return between(info.kp_proc.p_un.__p_starttime, and: now)
    }

    /// The time from one wall-clock reading to a later one, or `nil` when the clock went backwards.
    static func between(_ start: timeval, and end: timeval) -> Duration? {
        let elapsed =
            Duration.seconds(Int64(end.tv_sec) - Int64(start.tv_sec))
            + .microseconds(Int64(end.tv_usec) - Int64(start.tv_usec))
        return elapsed < .zero ? nil : elapsed
    }
}
