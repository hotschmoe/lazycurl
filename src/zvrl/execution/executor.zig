const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Stream = enum { stdout, stderr };
pub const OutputHandler = *const fn (ctx: ?*anyopaque, stream: Stream, chunk: []const u8) void;

pub const OutputSink = struct {
    ctx: ?*anyopaque = null,
    handler: ?OutputHandler = null,

    pub fn emit(self: *const OutputSink, stream: Stream, chunk: []const u8) void {
        if (self.handler) |handler| {
            handler(self.ctx, stream, chunk);
        }
    }
};

pub const ExecutionResult = struct {
    command: []u8,
    exit_code: ?u8,
    stdout: []u8,
    stderr: []u8,
    duration_ns: u64,
    error_message: ?[]u8,

    pub fn deinit(self: *ExecutionResult, allocator: Allocator) void {
        allocator.free(self.command);
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

pub const ExecutionError = error{
    InvalidCommand,
    SpawnFailed,
};

pub const CommandExecutor = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) CommandExecutor {
        return .{ .allocator = allocator };
    }

    pub fn start(self: *CommandExecutor, command: []const u8) !ExecutionJob {
        var argv_storage = try parseArgv(self.allocator, command);
        errdefer argv_storage.deinit(self.allocator);

        const argv = argv_storage.items;
        if (argv.len == 0 or !std.mem.eql(u8, argv[0], "curl")) {
            argv_storage.deinit(self.allocator);
            return ExecutionError.InvalidCommand;
        }

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        child.expand_arg0 = .expand;

        child.spawn() catch return ExecutionError.SpawnFailed;

        const poller = std.Io.poll(self.allocator, Stream, .{
            .stdout = child.stdout.?,
            .stderr = child.stderr.?,
        });

        const started_at = std.time.Instant.now() catch null;
        return .{
            .allocator = self.allocator,
            .command = try self.allocator.dupe(u8, command),
            .argv_storage = argv_storage,
            .child = child,
            .poller = poller,
            .stdout = try std.ArrayList(u8).initCapacity(self.allocator, 0),
            .stderr = try std.ArrayList(u8).initCapacity(self.allocator, 0),
            .start = started_at,
        };
    }

    pub fn execute(self: *CommandExecutor, command: []const u8, sink: ?OutputSink) !ExecutionResult {
        var job = try self.start(command);
        defer job.deinit();

        while (true) {
            if (try job.poll(50 * std.time.ns_per_ms, sink)) break;
        }
        return job.finish();
    }
};

pub const ExecutionJob = struct {
    allocator: Allocator,
    command: []u8,
    argv_storage: std.ArrayList([]const u8),
    child: std.process.Child,
    poller: std.Io.Poller(Stream),
    stdout: std.ArrayList(u8),
    stderr: std.ArrayList(u8),
    start: ?std.time.Instant,
    term: ?std.process.Child.Term = null,
    done: bool = false,

    pub fn poll(self: *ExecutionJob, timeout_ns: u64, sink: ?OutputSink) !bool {
        if (self.done) return true;

        if (try self.poller.pollTimeout(timeout_ns)) {
            self.flushStream(.stdout, sink);
            self.flushStream(.stderr, sink);
            return false;
        }

        self.flushStream(.stdout, sink);
        self.flushStream(.stderr, sink);
        self.term = try self.child.wait();
        self.done = true;
        return true;
    }

    pub fn finish(self: *ExecutionJob) !ExecutionResult {
        if (!self.done) {
            while (true) {
                if (try self.poll(50 * std.time.ns_per_ms, null)) break;
            }
        }

        const duration = if (self.start) |start| blk: {
            const end = std.time.Instant.now() catch break :blk 0;
            break :blk end.since(start);
        } else 0;

        const command_owned = self.command;
        self.command = &.{};

        var error_message: ?[]u8 = null;
        var exit_code: ?u8 = null;
        if (self.term) |term| {
            switch (term) {
                .Exited => |code| {
                    exit_code = code;
                    if (code != 0) {
                        error_message = try std.fmt.allocPrint(self.allocator, "Command failed with exit code {d}: {s}", .{
                            code,
                            curlErrorMessage(code),
                        });
                    }
                },
                .Signal => |sig| {
                    error_message = try std.fmt.allocPrint(self.allocator, "Process terminated by signal {d}", .{sig});
                },
                .Stopped => |sig| {
                    error_message = try std.fmt.allocPrint(self.allocator, "Process stopped by signal {d}", .{sig});
                },
                .Unknown => |code| {
                    error_message = try std.fmt.allocPrint(self.allocator, "Process terminated with status {d}", .{code});
                },
            }
        }

        return .{
            .command = command_owned,
            .exit_code = exit_code,
            .stdout = try self.stdout.toOwnedSlice(self.allocator),
            .stderr = try self.stderr.toOwnedSlice(self.allocator),
            .duration_ns = duration,
            .error_message = error_message,
        };
    }

    fn flushStream(self: *ExecutionJob, stream: Stream, sink: ?OutputSink) void {
        const reader = self.poller.reader(stream);
        const buffered = reader.buffered();
        if (buffered.len == 0) return;

        if (sink) |actual| {
            actual.emit(stream, buffered);
        }

        if (stream == .stdout) {
            _ = self.stdout.appendSlice(self.allocator, buffered) catch {};
        } else {
            _ = self.stderr.appendSlice(self.allocator, buffered) catch {};
        }
        reader.seek = reader.end;
    }

    pub fn deinit(self: *ExecutionJob) void {
        self.poller.deinit();
        self.stdout.deinit(self.allocator);
        self.stderr.deinit(self.allocator);
        self.argv_storage.deinit(self.allocator);
        if (self.command.len != 0) {
            self.allocator.free(self.command);
        }
    }
};

fn parseArgv(allocator: Allocator, command: []const u8) !std.ArrayList([]const u8) {
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    var it = std.mem.tokenizeAny(u8, command, " \t\r\n");
    while (it.next()) |token| {
        try argv.append(allocator, token);
    }
    return argv;
}

fn curlErrorMessage(exit_code: u8) []const u8 {
    return switch (exit_code) {
        1 => "Unsupported protocol",
        2 => "Failed to initialize",
        3 => "URL malformed",
        4 => "A feature or option that was needed to perform the desired request was not enabled",
        5 => "Couldn't resolve proxy",
        6 => "Couldn't resolve host",
        7 => "Failed to connect to host",
        8 => "FTP weird server reply",
        9 => "FTP access denied",
        10 => "FTP accept failed",
        11 => "FTP weird PASS reply",
        12 => "FTP accept timeout",
        13 => "FTP weird PASV reply",
        14 => "FTP weird 227 format",
        15 => "FTP can't get host",
        16 => "HTTP/2 framing layer error",
        17 => "FTP couldn't set binary",
        18 => "Partial file transfer",
        19 => "FTP couldn't download/access the given file",
        20 => "FTP write error",
        21 => "FTP quote error",
        22 => "HTTP page not retrieved",
        23 => "Write error",
        24 => "Upload failed",
        25 => "Failed to open/read local data",
        26 => "Read error",
        27 => "Out of memory",
        28 => "Operation timeout",
        29 => "FTP PORT failed",
        30 => "FTP couldn't use REST",
        31 => "HTTP range error",
        32 => "HTTP post error",
        33 => "SSL connect error",
        34 => "FTP bad download resume",
        35 => "FILE couldn't read file",
        36 => "LDAP cannot bind",
        37 => "LDAP search failed",
        38 => "Function not found",
        39 => "Aborted by callback",
        40 => "Bad function argument",
        41 => "Bad calling order",
        42 => "HTTP Interface operation failed",
        43 => "Bad password entered",
        44 => "Too many redirects",
        45 => "Unknown option specified",
        46 => "Malformed telnet option",
        47 => "The peer certificate cannot be authenticated",
        48 => "Unknown TELNET option specified",
        49 => "Malformed telnet option",
        51 => "The peer's SSL certificate or SSH MD5 fingerprint was not OK",
        52 => "The server didn't reply anything",
        53 => "SSL crypto engine not found",
        54 => "Cannot set SSL crypto engine as default",
        55 => "Failed sending network data",
        56 => "Failure in receiving network data",
        58 => "Problem with the local certificate",
        59 => "Couldn't use specified cipher",
        60 => "Peer certificate cannot be authenticated with known CA certificates",
        61 => "Unrecognized transfer encoding",
        62 => "Invalid LDAP URL",
        63 => "Maximum file size exceeded",
        64 => "Requested FTP SSL level failed",
        65 => "Sending the data requires a rewind that failed",
        66 => "Failed to initialise SSL Engine",
        67 => "The user name, password, or similar was not accepted and curl failed to log in",
        68 => "File not found on TFTP server",
        69 => "Permission problem on TFTP server",
        70 => "Out of disk space on TFTP server",
        71 => "Illegal TFTP operation",
        72 => "Unknown transfer ID",
        73 => "File already exists",
        74 => "No such user",
        75 => "Character conversion failed",
        76 => "Character conversion functions required",
        77 => "Problem with reading the SSL CA cert",
        78 => "The resource referenced in the URL does not exist",
        79 => "An unspecified error occurred during the SSH session",
        80 => "Failed to shut down the SSL connection",
        82 => "Could not load CRL file",
        83 => "Issuer check failed",
        84 => "The FTP PRET command failed",
        85 => "RTSP: mismatch of CSeq numbers",
        86 => "RTSP: mismatch of Session Identifiers",
        87 => "Unable to parse FTP file list",
        88 => "FTP chunk callback reported error",
        89 => "No connection available, the session will be queued",
        90 => "SSL public key does not matched pinned public key",
        91 => "Invalid SSL certificate status",
        92 => "Stream error in HTTP/2 framing layer",
        93 => "An API function was called from inside a callback",
        94 => "An authentication function returned an error",
        95 => "A problem was detected in the HTTP/3 layer",
        96 => "QUIC connection error",
        else => "Unknown error",
    };
}

test "curl error message mapping" {
    try std.testing.expectEqualStrings("Unsupported protocol", curlErrorMessage(1));
    try std.testing.expectEqualStrings("Unknown error", curlErrorMessage(255));
}

test "parse argv tokens" {
    var argv = try parseArgv(std.testing.allocator, "curl -v https://example.com");
    defer argv.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), argv.items.len);
    try std.testing.expectEqualStrings("curl", argv.items[0]);
}
