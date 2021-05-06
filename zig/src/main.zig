const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const ast = std.zig.ast;
const warn = std.log.warn;

const Compilation = @import("Compilation.zig");
const link = @import("link.zig");
const Package = @import("Package.zig");
const zir = @import("zir.zig");
const build_options = @import("build_options");
const introspect = @import("introspect.zig");
const LibCInstallation = @import("libc_installation.zig").LibCInstallation;
const translate_c = @import("translate_c.zig");
const Cache = @import("Cache.zig");
const target_util = @import("target.zig");
const ThreadPool = @import("ThreadPool.zig");

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.emerg(format, args);
    process.exit(1);
}

pub const max_src_size = 2 * 1024 * 1024 * 1024; // 2 GiB

pub const Color = enum {
    auto,
    off,
    on,
};

const usage =
    \\Usage: zig [command] [options]
    \\
    \\Commands:
    \\
    \\  build            Build project from build.zig
    \\  build-exe        Create executable from source or object files
    \\  build-lib        Create library from source or object files
    \\  build-obj        Create object from source or object files
    \\  cc               Use Zig as a drop-in C compiler
    \\  c++              Use Zig as a drop-in C++ compiler
    \\  env              Print lib path, std path, cache directory, and version
    \\  fmt              Reformat Zig source into canonical form
    \\  help             Print this help and exit
    \\  init-exe         Initialize a `zig build` application in the cwd
    \\  init-lib         Initialize a `zig build` library in the cwd
    \\  libc             Display native libc paths file or validate one
    \\  run              Create executable and run immediately
    \\  translate-c      Convert C code to Zig code
    \\  targets          List available compilation targets
    \\  test             Create and run a test build
    \\  version          Print version number and exit
    \\  zen              Print Zen of Zig and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage
    \\
;

pub const log_level: std.log.Level = switch (std.builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast => .info,
    .ReleaseSmall => .crit,
};

var log_scopes: std.ArrayListUnmanaged([]const u8) = .{};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Hide debug messages unless:
    // * logging enabled with `-Dlog`.
    // * the --debug-log arg for the scope has been provided
    if (@enumToInt(level) > @enumToInt(std.log.level) or
        @enumToInt(level) > @enumToInt(std.log.Level.info))
    {
        if (!build_options.enable_logging) return;

        const scope_name = @tagName(scope);
        for (log_scopes.items) |log_scope| {
            if (mem.eql(u8, log_scope, scope_name))
                break;
        } else return;
    }

    // We only recognize 4 log levels in this application.
    const level_txt = switch (level) {
        .emerg, .alert, .crit, .err => "error",
        .warn => "warning",
        .notice, .info => "info",
        .debug => "debug",
    };
    const prefix1 = level_txt;
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    // Print the message to stderr, silently ignoring any errors
    std.debug.print(prefix1 ++ prefix2 ++ format ++ "\n", args);
}

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    const gpa = if (std.builtin.link_libc)
        std.heap.raw_c_allocator
    else
        &general_purpose_allocator.allocator;
    defer if (!std.builtin.link_libc) {
        _ = general_purpose_allocator.deinit();
    };
    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = &arena_instance.allocator;

    const args = try process.argsAlloc(arena);
    return mainArgs(gpa, arena, args);
}

pub fn mainArgs(gpa: *Allocator, arena: *Allocator, args: []const []const u8) !void {
    if (args.len <= 1) {
        std.log.info("{s}", .{usage});
        fatal("expected command argument", .{});
    }

    if (std.process.can_execv and std.os.getenvZ("ZIG_IS_DETECTING_LIBC_PATHS") != null) {
        // In this case we have accidentally invoked ourselves as "the system C compiler"
        // to figure out where libc is installed. This is essentially infinite recursion
        // via child process execution due to the CC environment variable pointing to Zig.
        // Here we ignore the CC environment variable and exec `cc` as a child process.
        // However it's possible Zig is installed as *that* C compiler as well, which is
        // why we have this additional environment variable here to check.
        var env_map = try std.process.getEnvMap(arena);

        const inf_loop_env_key = "ZIG_IS_TRYING_TO_NOT_CALL_ITSELF";
        if (env_map.get(inf_loop_env_key) != null) {
            fatal("The compilation links against libc, but Zig is unable to provide a libc " ++
                "for this operating system, and no --libc " ++
                "parameter was provided, so Zig attempted to invoke the system C compiler " ++
                "in order to determine where libc is installed. However the system C " ++
                "compiler is `zig cc`, so no libc installation was found.", .{});
        }
        try env_map.set(inf_loop_env_key, "1");

        // Some programs such as CMake will strip the `cc` and subsequent args from the
        // CC environment variable. We detect and support this scenario here because of
        // the ZIG_IS_DETECTING_LIBC_PATHS environment variable.
        if (mem.eql(u8, args[1], "cc")) {
            return std.process.execve(arena, args[1..], &env_map);
        } else {
            const modified_args = try arena.dupe([]const u8, args);
            modified_args[0] = "cc";
            return std.process.execve(arena, modified_args, &env_map);
        }
    }

    defer log_scopes.deinit(gpa);

    const cmd = args[1];
    const cmd_args = args[2..];
    if (mem.eql(u8, cmd, "build-exe")) {
        return buildOutputType(gpa, arena, args, .{ .build = .Exe });
    } else if (mem.eql(u8, cmd, "build-lib")) {
        return buildOutputType(gpa, arena, args, .{ .build = .Lib });
    } else if (mem.eql(u8, cmd, "build-obj")) {
        return buildOutputType(gpa, arena, args, .{ .build = .Obj });
    } else if (mem.eql(u8, cmd, "test")) {
        return buildOutputType(gpa, arena, args, .zig_test);
    } else if (mem.eql(u8, cmd, "run")) {
        return buildOutputType(gpa, arena, args, .run);
    } else if (mem.eql(u8, cmd, "cc")) {
        return buildOutputType(gpa, arena, args, .cc);
    } else if (mem.eql(u8, cmd, "c++")) {
        return buildOutputType(gpa, arena, args, .cpp);
    } else if (mem.eql(u8, cmd, "translate-c")) {
        return buildOutputType(gpa, arena, args, .translate_c);
    } else if (mem.eql(u8, cmd, "clang") or
        mem.eql(u8, cmd, "-cc1") or mem.eql(u8, cmd, "-cc1as"))
    {
        return punt_to_clang(arena, args);
    } else if (mem.eql(u8, cmd, "ld.lld") or
        mem.eql(u8, cmd, "ld64.lld") or
        mem.eql(u8, cmd, "lld-link") or
        mem.eql(u8, cmd, "wasm-ld"))
    {
        return punt_to_lld(arena, args);
    } else if (mem.eql(u8, cmd, "build")) {
        return cmdBuild(gpa, arena, cmd_args);
    } else if (mem.eql(u8, cmd, "fmt")) {
        return cmdFmt(gpa, cmd_args);
    } else if (mem.eql(u8, cmd, "libc")) {
        return cmdLibC(gpa, cmd_args);
    } else if (mem.eql(u8, cmd, "init-exe")) {
        return cmdInit(gpa, arena, cmd_args, .Exe);
    } else if (mem.eql(u8, cmd, "init-lib")) {
        return cmdInit(gpa, arena, cmd_args, .Lib);
    } else if (mem.eql(u8, cmd, "targets")) {
        const info = try detectNativeTargetInfo(arena, .{});
        const stdout = io.getStdOut().writer();
        return @import("print_targets.zig").cmdTargets(arena, cmd_args, stdout, info.target);
    } else if (mem.eql(u8, cmd, "version")) {
        try std.io.getStdOut().writeAll(build_options.version ++ "\n");
    } else if (mem.eql(u8, cmd, "env")) {
        try @import("print_env.zig").cmdEnv(arena, cmd_args, io.getStdOut().writer());
    } else if (mem.eql(u8, cmd, "zen")) {
        try io.getStdOut().writeAll(info_zen);
    } else if (mem.eql(u8, cmd, "help") or mem.eql(u8, cmd, "-h") or mem.eql(u8, cmd, "--help")) {
        try io.getStdOut().writeAll(usage);
    } else {
        std.log.info("{s}", .{usage});
        fatal("unknown command: {s}", .{args[1]});
    }
}

const usage_build_generic =
    \\Usage: zig build-exe <options> [files]
    \\       zig build-lib <options> [files]
    \\       zig build-obj <options> [files]
    \\       zig test <options> [files]
    \\       zig run <options> [file] [-- [args]]
    \\
    \\Supported file types:
    \\                    .zig    Zig source code
    \\                      .o    ELF object file
    \\                      .o    MACH-O (macOS) object file
    \\                    .obj    COFF (Windows) object file
    \\                    .lib    COFF (Windows) static library
    \\                      .a    ELF static library
    \\                     .so    ELF shared object (dynamic link)
    \\                    .dll    Windows Dynamic Link Library
    \\                  .dylib    MACH-O (macOS) dynamic library
    \\                    .tbd    (macOS) text-based dylib definition
    \\                      .s    Target-specific assembly source code
    \\                      .S    Assembly with C preprocessor (requires LLVM extensions)
    \\                      .c    C source code (requires LLVM extensions)
    \\                    .cpp    C++ source code (requires LLVM extensions)
    \\                            Other C++ extensions: .C .cc .cxx
    \\
    \\General Options:
    \\  -h, --help                Print this help and exit
    \\  --watch                   Enable compiler REPL
    \\  --color [auto|off|on]     Enable or disable colored error messages
    \\  -femit-bin[=path]         (default) Output machine code
    \\  -fno-emit-bin             Do not output machine code
    \\  -femit-asm[=path]         Output .s (assembly code)
    \\  -fno-emit-asm             (default) Do not output .s (assembly code)
    \\  -femit-llvm-ir[=path]     Produce a .ll file with LLVM IR (requires LLVM extensions)
    \\  -fno-emit-llvm-ir         (default) Do not produce a .ll file with LLVM IR
    \\  -femit-h[=path]           Generate a C header file (.h)
    \\  -fno-emit-h               (default) Do not generate a C header file (.h)
    \\  -femit-docs[=path]        Create a docs/ dir with html documentation
    \\  -fno-emit-docs            (default) Do not produce docs/ dir with html documentation
    \\  -femit-analysis[=path]    Write analysis JSON file with type information
    \\  -fno-emit-analysis        (default) Do not write analysis JSON file with type information
    \\  --show-builtin            Output the source of @import("builtin") then exit
    \\  --cache-dir [path]        Override the local cache directory
    \\  --global-cache-dir [path] Override the global cache directory
    \\  --override-lib-dir [path] Override path to Zig installation lib directory
    \\  --enable-cache            Output to cache directory; print path to stdout
    \\
    \\Compile Options:
    \\  -target [name]            <arch><sub>-<os>-<abi> see the targets command
    \\  -mcpu [cpu]               Specify target CPU and feature set
    \\  -mcmodel=[default|tiny|   Limit range of code and data virtual addresses
    \\            small|kernel|
    \\            medium|large]
    \\  -mred-zone                Force-enable the "red-zone"
    \\  -mno-red-zone             Force-disable the "red-zone"
    \\  --name [name]             Override root name (not a file path)
    \\  -O [mode]                 Choose what to optimize for
    \\    Debug                   (default) Optimizations off, safety on
    \\    ReleaseFast             Optimizations on, safety off
    \\    ReleaseSafe             Optimizations on, safety on
    \\    ReleaseSmall            Optimize for small binary, safety off
    \\  --pkg-begin [name] [path] Make pkg available to import and push current pkg
    \\  --pkg-end                 Pop current pkg
    \\  --main-pkg-path           Set the directory of the root package
    \\  -fPIC                     Force-enable Position Independent Code
    \\  -fno-PIC                  Force-disable Position Independent Code
    \\  -fPIE                     Force-enable Position Independent Executable
    \\  -fno-PIE                  Force-disable Position Independent Executable
    \\  -flto                     Force-enable Link Time Optimization (requires LLVM extensions)
    \\  -fno-lto                  Force-disable Link Time Optimization
    \\  -fstack-check             Enable stack probing in unsafe builds
    \\  -fno-stack-check          Disable stack probing in safe builds
    \\  -fsanitize-c              Enable C undefined behavior detection in unsafe builds
    \\  -fno-sanitize-c           Disable C undefined behavior detection in safe builds
    \\  -fvalgrind                Include valgrind client requests in release builds
    \\  -fno-valgrind             Omit valgrind client requests in debug builds
    \\  -fsanitize-thread         Enable Thread Sanitizer
    \\  -fno-sanitize-thread      Disable Thread Sanitizer
    \\  -fdll-export-fns          Mark exported functions as DLL exports (Windows)
    \\  -fno-dll-export-fns       Force-disable marking exported functions as DLL exports
    \\  -fLLVM                    Force using LLVM as the codegen backend
    \\  -fno-LLVM                 Prevent using LLVM as a codegen backend
    \\  -fClang                   Force using Clang as the C/C++ compilation backend
    \\  -fno-Clang                Prevent using Clang as the C/C++ compilation backend
    \\  --strip                   Omit debug symbols
    \\  --single-threaded         Code assumes it is only used single-threaded
    \\  -ofmt=[mode]              Override target object format
    \\    elf                     Executable and Linking Format
    \\    c                       Compile to C source code
    \\    wasm                    WebAssembly
    \\    pe                      Portable Executable (Windows)
    \\    coff                    Common Object File Format (Windows)
    \\    macho                   macOS relocatables
    \\    spirv                   Standard, Portable Intermediate Representation V (SPIR-V)
    \\    hex    (planned)        Intel IHEX
    \\    raw    (planned)        Dump machine code directly
    \\  -dirafter [dir]           Add directory to AFTER include search path
    \\  -isystem  [dir]           Add directory to SYSTEM include search path
    \\  -I[dir]                   Add directory to include search path
    \\  -D[macro]=[value]         Define C [macro] to [value] (1 if [value] omitted)
    \\  --libc [file]             Provide a file which specifies libc paths
    \\  -cflags [flags] --        Set extra flags for the next positional C source files
    \\  -ffunction-sections       Places each function in a separate section
    \\
    \\Link Options:
    \\  -l[lib], --library [lib]       Link against system library
    \\  -L[d], --library-directory [d] Add a directory to the library search path
    \\  -T[script], --script [script]  Use a custom linker script
    \\  --version-script [path]        Provide a version .map file
    \\  --dynamic-linker [path]        Set the dynamic interpreter path (usually ld.so)
    \\  --version [ver]                Dynamic library semver
    \\  -fsoname[=name]                (Linux) Override the default SONAME value
    \\  -fno-soname                    (Linux) Disable emitting a SONAME
    \\  -fLLD                          Force using LLD as the linker
    \\  -fno-LLD                       Prevent using LLD as the linker
    \\  -fcompiler-rt                  Always include compiler-rt symbols in output
    \\  -fno-compiler-rt               Prevent including compiler-rt symbols in output
    \\  -rdynamic                      Add all symbols to the dynamic symbol table
    \\  -rpath [path]                  Add directory to the runtime library search path
    \\  -feach-lib-rpath               Ensure adding rpath for each used dynamic library
    \\  -fno-each-lib-rpath            Prevent adding rpath for each used dynamic library
    \\  -fallow-shlib-undefined        Allows undefined symbols in shared libraries
    \\  -fno-allow-shlib-undefined     Disallows undefined symbols in shared libraries
    \\  --eh-frame-hdr                 Enable C++ exception handling by passing --eh-frame-hdr to linker
    \\  --emit-relocs                  Enable output of relocation sections for post build tools
    \\  -dynamic                       Force output to be dynamically linked
    \\  -static                        Force output to be statically linked
    \\  -Bsymbolic                     Bind global references locally
    \\  --subsystem [subsystem]        (Windows) /SUBSYSTEM:<subsystem> to the linker
    \\  --stack [size]                 Override default stack size
    \\  --image-base [addr]            Set base address for executable image
    \\  -framework [name]              (Darwin) link against framework
    \\  -F[dir]                        (Darwin) add search path for frameworks
    \\
    \\Test Options:
    \\  --test-filter [text]           Skip tests that do not match filter
    \\  --test-name-prefix [text]      Add prefix to all tests
    \\  --test-cmd [arg]               Specify test execution command one arg at a time
    \\  --test-cmd-bin                 Appends test binary path to test cmd args
    \\  --test-evented-io              Runs the test in evented I/O mode
    \\
    \\Debug Options (Zig Compiler Development):
    \\  -ftime-report                Print timing diagnostics
    \\  -fstack-report               Print stack size diagnostics
    \\  --verbose-link               Display linker invocations
    \\  --verbose-cc                 Display C compiler invocations
    \\  --verbose-tokenize           Enable compiler debug output for tokenization
    \\  --verbose-ast                Enable compiler debug output for AST parsing
    \\  --verbose-ir                 Enable compiler debug output for Zig IR
    \\  --verbose-llvm-ir            Enable compiler debug output for LLVM IR
    \\  --verbose-cimport            Enable compiler debug output for C imports
    \\  --verbose-llvm-cpu-features  Enable compiler debug output for LLVM CPU features
    \\  --debug-log [scope]          Enable printing debug/info log messages for scope
    \\
;

const repl_help =
    \\Commands:
    \\  update   Detect changes to source files and update output files.
    \\    help   Print this text
    \\    exit   Quit this repl
    \\
;

const SOName = union(enum) {
    no,
    yes_default_value,
    yes: []const u8,
};

const EmitBin = union(enum) {
    no,
    yes_default_path,
    yes: []const u8,
    yes_a_out,
};

const Emit = union(enum) {
    no,
    yes_default_path,
    yes: []const u8,

    const Resolved = struct {
        data: ?Compilation.EmitLoc,
        dir: ?fs.Dir,

        fn deinit(self: *Resolved) void {
            if (self.dir) |*dir| {
                dir.close();
            }
        }
    };

    fn resolve(emit: Emit, default_basename: []const u8) !Resolved {
        var resolved: Resolved = .{ .data = null, .dir = null };
        errdefer resolved.deinit();

        switch (emit) {
            .no => {},
            .yes_default_path => {
                resolved.data = Compilation.EmitLoc{
                    .directory = .{ .path = null, .handle = fs.cwd() },
                    .basename = default_basename,
                };
            },
            .yes => |full_path| {
                const basename = fs.path.basename(full_path);
                if (fs.path.dirname(full_path)) |dirname| {
                    const handle = try fs.cwd().openDir(dirname, .{});
                    resolved = .{
                        .dir = handle,
                        .data = Compilation.EmitLoc{
                            .basename = basename,
                            .directory = .{
                                .path = dirname,
                                .handle = handle,
                            },
                        },
                    };
                } else {
                    resolved.data = Compilation.EmitLoc{
                        .basename = basename,
                        .directory = .{ .path = null, .handle = fs.cwd() },
                    };
                }
            },
        }
        return resolved;
    }
};

fn optionalBoolEnvVar(arena: *Allocator, name: []const u8) !bool {
    if (std.process.getEnvVarOwned(arena, name)) |value| {
        return true;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => |e| return e,
    }
}

fn optionalStringEnvVar(arena: *Allocator, name: []const u8) !?[]const u8 {
    if (std.process.getEnvVarOwned(arena, name)) |value| {
        return value;
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => |e| return e,
    }
}

fn buildOutputType(
    gpa: *Allocator,
    arena: *Allocator,
    all_args: []const []const u8,
    arg_mode: union(enum) {
        build: std.builtin.OutputMode,
        cc,
        cpp,
        translate_c,
        zig_test,
        run,
    },
) !void {
    var color: Color = .auto;
    var optimize_mode: std.builtin.Mode = .Debug;
    var provided_name: ?[]const u8 = null;
    var link_mode: ?std.builtin.LinkMode = null;
    var dll_export_fns: ?bool = null;
    var root_src_file: ?[]const u8 = null;
    var version: std.builtin.Version = .{ .major = 0, .minor = 0, .patch = 0 };
    var have_version = false;
    var strip = false;
    var single_threaded = false;
    var function_sections = false;
    var watch = false;
    var verbose_link = try optionalBoolEnvVar(arena, "ZIG_VERBOSE_LINK");
    var verbose_cc = try optionalBoolEnvVar(arena, "ZIG_VERBOSE_CC");
    var verbose_tokenize = false;
    var verbose_ast = false;
    var verbose_ir = false;
    var verbose_llvm_ir = false;
    var verbose_cimport = false;
    var verbose_llvm_cpu_features = false;
    var time_report = false;
    var stack_report = false;
    var show_builtin = false;
    var emit_bin: EmitBin = .yes_default_path;
    var emit_asm: Emit = .no;
    var emit_llvm_ir: Emit = .no;
    var emit_docs: Emit = .no;
    var emit_analysis: Emit = .no;
    var target_arch_os_abi: []const u8 = "native";
    var target_mcpu: ?[]const u8 = null;
    var target_dynamic_linker: ?[]const u8 = null;
    var target_ofmt: ?[]const u8 = null;
    var output_mode: std.builtin.OutputMode = undefined;
    var emit_h: Emit = .no;
    var soname: SOName = undefined;
    var ensure_libc_on_non_freestanding = false;
    var ensure_libcpp_on_non_freestanding = false;
    var link_libc = false;
    var link_libcpp = false;
    var want_native_include_dirs = false;
    var enable_cache: ?bool = null;
    var want_pic: ?bool = null;
    var want_pie: ?bool = null;
    var want_lto: ?bool = null;
    var want_sanitize_c: ?bool = null;
    var want_stack_check: ?bool = null;
    var want_red_zone: ?bool = null;
    var want_valgrind: ?bool = null;
    var want_tsan: ?bool = null;
    var want_compiler_rt: ?bool = null;
    var rdynamic: bool = false;
    var linker_script: ?[]const u8 = null;
    var version_script: ?[]const u8 = null;
    var disable_c_depfile = false;
    var linker_gc_sections: ?bool = null;
    var linker_allow_shlib_undefined: ?bool = null;
    var linker_bind_global_refs_locally: ?bool = null;
    var linker_z_nodelete = false;
    var linker_z_defs = false;
    var linker_tsaware = false;
    var linker_nxcompat = false;
    var linker_dynamicbase = false;
    var test_evented_io = false;
    var stack_size_override: ?u64 = null;
    var image_base_override: ?u64 = null;
    var use_llvm: ?bool = null;
    var use_lld: ?bool = null;
    var use_clang: ?bool = null;
    var link_eh_frame_hdr = false;
    var link_emit_relocs = false;
    var each_lib_rpath: ?bool = null;
    var libc_paths_file: ?[]const u8 = try optionalStringEnvVar(arena, "ZIG_LIBC");
    var machine_code_model: std.builtin.CodeModel = .default;
    var runtime_args_start: ?usize = null;
    var test_filter: ?[]const u8 = null;
    var test_name_prefix: ?[]const u8 = null;
    var override_local_cache_dir: ?[]const u8 = try optionalStringEnvVar(arena, "ZIG_LOCAL_CACHE_DIR");
    var override_global_cache_dir: ?[]const u8 = null;
    var override_lib_dir: ?[]const u8 = try optionalStringEnvVar(arena, "ZIG_LIB_DIR");
    var main_pkg_path: ?[]const u8 = null;
    var clang_preprocessor_mode: Compilation.ClangPreprocessorMode = .no;
    var subsystem: ?std.Target.SubSystem = null;
    var major_subsystem_version: ?u32 = null;
    var minor_subsystem_version: ?u32 = null;

    var system_libs = std.ArrayList([]const u8).init(gpa);
    defer system_libs.deinit();

    var clang_argv = std.ArrayList([]const u8).init(gpa);
    defer clang_argv.deinit();

    var extra_cflags = std.ArrayList([]const u8).init(gpa);
    defer extra_cflags.deinit();

    var lld_argv = std.ArrayList([]const u8).init(gpa);
    defer lld_argv.deinit();

    var lib_dirs = std.ArrayList([]const u8).init(gpa);
    defer lib_dirs.deinit();

    var rpath_list = std.ArrayList([]const u8).init(gpa);
    defer rpath_list.deinit();

    var c_source_files = std.ArrayList(Compilation.CSourceFile).init(gpa);
    defer c_source_files.deinit();

    var link_objects = std.ArrayList([]const u8).init(gpa);
    defer link_objects.deinit();

    var framework_dirs = std.ArrayList([]const u8).init(gpa);
    defer framework_dirs.deinit();

    var frameworks = std.ArrayList([]const u8).init(gpa);
    defer frameworks.deinit();

    // null means replace with the test executable binary
    var test_exec_args = std.ArrayList(?[]const u8).init(gpa);
    defer test_exec_args.deinit();

    // This package only exists to clean up the code parsing --pkg-begin and
    // --pkg-end flags. Use dummy values that are safe for the destroy call.
    var pkg_tree_root: Package = .{
        .root_src_directory = .{ .path = null, .handle = fs.cwd() },
        .root_src_path = &[0]u8{},
        .namespace_hash = Package.root_namespace_hash,
    };
    defer freePkgTree(gpa, &pkg_tree_root, false);
    var cur_pkg: *Package = &pkg_tree_root;

    switch (arg_mode) {
        .build, .translate_c, .zig_test, .run => {
            var optimize_mode_string: ?[]const u8 = null;
            switch (arg_mode) {
                .build => |m| {
                    output_mode = m;
                },
                .translate_c => {
                    emit_bin = .no;
                    output_mode = .Obj;
                },
                .zig_test, .run => {
                    output_mode = .Exe;
                },
                else => unreachable,
            }

            soname = .yes_default_value;
            const args = all_args[2..];
            var i: usize = 0;
            args_loop: while (i < args.len) : (i += 1) {
                const arg = args[i];
                if (mem.startsWith(u8, arg, "-")) {
                    if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                        try io.getStdOut().writeAll(usage_build_generic);
                        return cleanExit();
                    } else if (mem.eql(u8, arg, "--")) {
                        if (arg_mode == .run) {
                            // The index refers to all_args so skip `zig` `run`
                            // and `--`
                            runtime_args_start = i + 3;
                            break :args_loop;
                        } else {
                            fatal("unexpected end-of-parameter mark: --", .{});
                        }
                    } else if (mem.eql(u8, arg, "--pkg-begin")) {
                        if (i + 2 >= args.len) fatal("Expected 2 arguments after {s}", .{arg});
                        i += 1;
                        const pkg_name = args[i];
                        i += 1;
                        const pkg_path = args[i];

                        const new_cur_pkg = Package.create(
                            gpa,
                            fs.path.dirname(pkg_path),
                            fs.path.basename(pkg_path),
                        ) catch |err| {
                            fatal("Failed to add package at path {s}: {s}", .{ pkg_path, @errorName(err) });
                        };
                        try cur_pkg.addAndAdopt(gpa, pkg_name, new_cur_pkg);
                        cur_pkg = new_cur_pkg;
                    } else if (mem.eql(u8, arg, "--pkg-end")) {
                        cur_pkg = cur_pkg.parent orelse
                            fatal("encountered --pkg-end with no matching --pkg-begin", .{});
                    } else if (mem.eql(u8, arg, "--main-pkg-path")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        main_pkg_path = args[i];
                    } else if (mem.eql(u8, arg, "-cflags")) {
                        extra_cflags.shrinkRetainingCapacity(0);
                        while (true) {
                            i += 1;
                            if (i >= args.len) fatal("expected -- after -cflags", .{});
                            if (mem.eql(u8, args[i], "--")) break;
                            try extra_cflags.append(args[i]);
                        }
                    } else if (mem.eql(u8, arg, "--color")) {
                        if (i + 1 >= args.len) {
                            fatal("expected [auto|on|off] after --color", .{});
                        }
                        i += 1;
                        const next_arg = args[i];
                        color = std.meta.stringToEnum(Color, next_arg) orelse {
                            fatal("expected [auto|on|off] after --color, found '{s}'", .{next_arg});
                        };
                    } else if (mem.eql(u8, arg, "--subsystem")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        if (mem.eql(u8, args[i], "console")) {
                            subsystem = .Console;
                        } else if (mem.eql(u8, args[i], "windows")) {
                            subsystem = .Windows;
                        } else if (mem.eql(u8, args[i], "posix")) {
                            subsystem = .Posix;
                        } else if (mem.eql(u8, args[i], "native")) {
                            subsystem = .Native;
                        } else if (mem.eql(u8, args[i], "efi_application")) {
                            subsystem = .EfiApplication;
                        } else if (mem.eql(u8, args[i], "efi_boot_service_driver")) {
                            subsystem = .EfiBootServiceDriver;
                        } else if (mem.eql(u8, args[i], "efi_rom")) {
                            subsystem = .EfiRom;
                        } else if (mem.eql(u8, args[i], "efi_runtime_driver")) {
                            subsystem = .EfiRuntimeDriver;
                        } else {
                            fatal("invalid: --subsystem: '{s}'. Options are:\n{s}", .{
                                args[i],
                                \\  console
                                \\  windows
                                \\  posix
                                \\  native
                                \\  efi_application
                                \\  efi_boot_service_driver
                                \\  efi_rom
                                \\  efi_runtime_driver
                                \\
                            });
                        }
                    } else if (mem.eql(u8, arg, "-O")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        optimize_mode_string = args[i];
                    } else if (mem.eql(u8, arg, "--stack")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        stack_size_override = std.fmt.parseUnsigned(u64, args[i], 0) catch |err| {
                            fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                        };
                    } else if (mem.eql(u8, arg, "--image-base")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        image_base_override = std.fmt.parseUnsigned(u64, args[i], 0) catch |err| {
                            fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                        };
                    } else if (mem.eql(u8, arg, "--name")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        provided_name = args[i];
                    } else if (mem.eql(u8, arg, "-rpath")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try rpath_list.append(args[i]);
                    } else if (mem.eql(u8, arg, "--library-directory") or mem.eql(u8, arg, "-L")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try lib_dirs.append(args[i]);
                    } else if (mem.eql(u8, arg, "-F")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try framework_dirs.append(args[i]);
                    } else if (mem.eql(u8, arg, "-framework")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try frameworks.append(args[i]);
                    } else if (mem.eql(u8, arg, "-T") or mem.eql(u8, arg, "--script")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        linker_script = args[i];
                    } else if (mem.eql(u8, arg, "--version-script")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        version_script = args[i];
                    } else if (mem.eql(u8, arg, "--library") or mem.eql(u8, arg, "-l")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        // We don't know whether this library is part of libc or libc++ until we resolve the target.
                        // So we simply append to the list for now.
                        i += 1;
                        try system_libs.append(args[i]);
                    } else if (mem.eql(u8, arg, "-D") or
                        mem.eql(u8, arg, "-isystem") or
                        mem.eql(u8, arg, "-I") or
                        mem.eql(u8, arg, "-dirafter"))
                    {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try clang_argv.append(arg);
                        try clang_argv.append(args[i]);
                    } else if (mem.eql(u8, arg, "--version")) {
                        if (i + 1 >= args.len) {
                            fatal("expected parameter after --version", .{});
                        }
                        i += 1;
                        version = std.builtin.Version.parse(args[i]) catch |err| {
                            fatal("unable to parse --version '{s}': {s}", .{ args[i], @errorName(err) });
                        };
                        have_version = true;
                    } else if (mem.eql(u8, arg, "-target")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        target_arch_os_abi = args[i];
                    } else if (mem.eql(u8, arg, "-mcpu")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        target_mcpu = args[i];
                    } else if (mem.eql(u8, arg, "-mcmodel")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        machine_code_model = parseCodeModel(args[i]);
                    } else if (mem.startsWith(u8, arg, "-ofmt=")) {
                        target_ofmt = arg["-ofmt=".len..];
                    } else if (mem.startsWith(u8, arg, "-mcpu=")) {
                        target_mcpu = arg["-mcpu=".len..];
                    } else if (mem.startsWith(u8, arg, "-mcmodel=")) {
                        machine_code_model = parseCodeModel(arg["-mcmodel=".len..]);
                    } else if (mem.startsWith(u8, arg, "-O")) {
                        optimize_mode_string = arg["-O".len..];
                    } else if (mem.eql(u8, arg, "--dynamic-linker")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        target_dynamic_linker = args[i];
                    } else if (mem.eql(u8, arg, "--libc")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        libc_paths_file = args[i];
                    } else if (mem.eql(u8, arg, "--test-filter")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        test_filter = args[i];
                    } else if (mem.eql(u8, arg, "--test-name-prefix")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        test_name_prefix = args[i];
                    } else if (mem.eql(u8, arg, "--test-cmd")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        try test_exec_args.append(args[i]);
                    } else if (mem.eql(u8, arg, "--cache-dir")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        override_local_cache_dir = args[i];
                    } else if (mem.eql(u8, arg, "--global-cache-dir")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        override_global_cache_dir = args[i];
                    } else if (mem.eql(u8, arg, "--override-lib-dir")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        override_lib_dir = args[i];
                    } else if (mem.eql(u8, arg, "--debug-log")) {
                        if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                        i += 1;
                        if (!build_options.enable_logging) {
                            std.log.warn("Zig was compiled without logging enabled (-Dlog). --debug-log has no effect.", .{});
                        } else {
                            try log_scopes.append(gpa, args[i]);
                        }
                    } else if (mem.eql(u8, arg, "-fcompiler-rt")) {
                        want_compiler_rt = true;
                    } else if (mem.eql(u8, arg, "-fno-compiler-rt")) {
                        want_compiler_rt = false;
                    } else if (mem.eql(u8, arg, "-feach-lib-rpath")) {
                        each_lib_rpath = true;
                    } else if (mem.eql(u8, arg, "-fno-each-lib-rpath")) {
                        each_lib_rpath = false;
                    } else if (mem.eql(u8, arg, "--enable-cache")) {
                        enable_cache = true;
                    } else if (mem.eql(u8, arg, "--test-cmd-bin")) {
                        try test_exec_args.append(null);
                    } else if (mem.eql(u8, arg, "--test-evented-io")) {
                        test_evented_io = true;
                    } else if (mem.eql(u8, arg, "--watch")) {
                        watch = true;
                    } else if (mem.eql(u8, arg, "-ftime-report")) {
                        time_report = true;
                    } else if (mem.eql(u8, arg, "-fstack-report")) {
                        stack_report = true;
                    } else if (mem.eql(u8, arg, "-fPIC")) {
                        want_pic = true;
                    } else if (mem.eql(u8, arg, "-fno-PIC")) {
                        want_pic = false;
                    } else if (mem.eql(u8, arg, "-fPIE")) {
                        want_pie = true;
                    } else if (mem.eql(u8, arg, "-fno-PIE")) {
                        want_pie = false;
                    } else if (mem.eql(u8, arg, "-flto")) {
                        want_lto = true;
                    } else if (mem.eql(u8, arg, "-fno-lto")) {
                        want_lto = false;
                    } else if (mem.eql(u8, arg, "-fstack-check")) {
                        want_stack_check = true;
                    } else if (mem.eql(u8, arg, "-fno-stack-check")) {
                        want_stack_check = false;
                    } else if (mem.eql(u8, arg, "-mred-zone")) {
                        want_red_zone = true;
                    } else if (mem.eql(u8, arg, "-mno-red-zone")) {
                        want_red_zone = false;
                    } else if (mem.eql(u8, arg, "-fsanitize-c")) {
                        want_sanitize_c = true;
                    } else if (mem.eql(u8, arg, "-fno-sanitize-c")) {
                        want_sanitize_c = false;
                    } else if (mem.eql(u8, arg, "-fvalgrind")) {
                        want_valgrind = true;
                    } else if (mem.eql(u8, arg, "-fno-valgrind")) {
                        want_valgrind = false;
                    } else if (mem.eql(u8, arg, "-fsanitize-thread")) {
                        want_tsan = true;
                    } else if (mem.eql(u8, arg, "-fno-sanitize-thread")) {
                        want_tsan = false;
                    } else if (mem.eql(u8, arg, "-fLLVM")) {
                        use_llvm = true;
                    } else if (mem.eql(u8, arg, "-fno-LLVM")) {
                        use_llvm = false;
                    } else if (mem.eql(u8, arg, "-fLLD")) {
                        use_lld = true;
                    } else if (mem.eql(u8, arg, "-fno-LLD")) {
                        use_lld = false;
                    } else if (mem.eql(u8, arg, "-fClang")) {
                        use_clang = true;
                    } else if (mem.eql(u8, arg, "-fno-Clang")) {
                        use_clang = false;
                    } else if (mem.eql(u8, arg, "-rdynamic")) {
                        rdynamic = true;
                    } else if (mem.eql(u8, arg, "-fsoname")) {
                        soname = .yes_default_value;
                    } else if (mem.startsWith(u8, arg, "-fsoname=")) {
                        soname = .{ .yes = arg["-fsoname=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-soname")) {
                        soname = .no;
                    } else if (mem.eql(u8, arg, "-femit-bin")) {
                        emit_bin = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-bin=")) {
                        emit_bin = .{ .yes = arg["-femit-bin=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-bin")) {
                        emit_bin = .no;
                    } else if (mem.eql(u8, arg, "-femit-h")) {
                        emit_h = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-h=")) {
                        emit_h = .{ .yes = arg["-femit-h=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-h")) {
                        emit_h = .no;
                    } else if (mem.eql(u8, arg, "-femit-asm")) {
                        emit_asm = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-asm=")) {
                        emit_asm = .{ .yes = arg["-femit-asm=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-asm")) {
                        emit_asm = .no;
                    } else if (mem.eql(u8, arg, "-femit-llvm-ir")) {
                        emit_llvm_ir = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-llvm-ir=")) {
                        emit_llvm_ir = .{ .yes = arg["-femit-llvm-ir=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-llvm-ir")) {
                        emit_llvm_ir = .no;
                    } else if (mem.eql(u8, arg, "-femit-docs")) {
                        emit_docs = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-docs=")) {
                        emit_docs = .{ .yes = arg["-femit-docs=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-docs")) {
                        emit_docs = .no;
                    } else if (mem.eql(u8, arg, "-femit-analysis")) {
                        emit_analysis = .yes_default_path;
                    } else if (mem.startsWith(u8, arg, "-femit-analysis=")) {
                        emit_analysis = .{ .yes = arg["-femit-analysis=".len..] };
                    } else if (mem.eql(u8, arg, "-fno-emit-analysis")) {
                        emit_analysis = .no;
                    } else if (mem.eql(u8, arg, "-dynamic")) {
                        link_mode = .Dynamic;
                    } else if (mem.eql(u8, arg, "-static")) {
                        link_mode = .Static;
                    } else if (mem.eql(u8, arg, "-fdll-export-fns")) {
                        dll_export_fns = true;
                    } else if (mem.eql(u8, arg, "-fno-dll-export-fns")) {
                        dll_export_fns = false;
                    } else if (mem.eql(u8, arg, "--show-builtin")) {
                        show_builtin = true;
                        emit_bin = .no;
                    } else if (mem.eql(u8, arg, "--strip")) {
                        strip = true;
                    } else if (mem.eql(u8, arg, "--single-threaded")) {
                        single_threaded = true;
                    } else if (mem.eql(u8, arg, "-ffunction-sections")) {
                        function_sections = true;
                    } else if (mem.eql(u8, arg, "--eh-frame-hdr")) {
                        link_eh_frame_hdr = true;
                    } else if (mem.eql(u8, arg, "--emit-relocs")) {
                        link_emit_relocs = true;
                    } else if (mem.eql(u8, arg, "-fallow-shlib-undefined")) {
                        linker_allow_shlib_undefined = true;
                    } else if (mem.eql(u8, arg, "-fno-allow-shlib-undefined")) {
                        linker_allow_shlib_undefined = false;
                    } else if (mem.eql(u8, arg, "-Bsymbolic")) {
                        linker_bind_global_refs_locally = true;
                    } else if (mem.eql(u8, arg, "--verbose-link")) {
                        verbose_link = true;
                    } else if (mem.eql(u8, arg, "--verbose-cc")) {
                        verbose_cc = true;
                    } else if (mem.eql(u8, arg, "--verbose-tokenize")) {
                        verbose_tokenize = true;
                    } else if (mem.eql(u8, arg, "--verbose-ast")) {
                        verbose_ast = true;
                    } else if (mem.eql(u8, arg, "--verbose-ir")) {
                        verbose_ir = true;
                    } else if (mem.eql(u8, arg, "--verbose-llvm-ir")) {
                        verbose_llvm_ir = true;
                    } else if (mem.eql(u8, arg, "--verbose-cimport")) {
                        verbose_cimport = true;
                    } else if (mem.eql(u8, arg, "--verbose-llvm-cpu-features")) {
                        verbose_llvm_cpu_features = true;
                    } else if (mem.startsWith(u8, arg, "-T")) {
                        linker_script = arg[2..];
                    } else if (mem.startsWith(u8, arg, "-L")) {
                        try lib_dirs.append(arg[2..]);
                    } else if (mem.startsWith(u8, arg, "-F")) {
                        try framework_dirs.append(arg[2..]);
                    } else if (mem.startsWith(u8, arg, "-l")) {
                        // We don't know whether this library is part of libc or libc++ until we resolve the target.
                        // So we simply append to the list for now.
                        try system_libs.append(arg[2..]);
                    } else if (mem.startsWith(u8, arg, "-D") or
                        mem.startsWith(u8, arg, "-I"))
                    {
                        try clang_argv.append(arg);
                    } else {
                        fatal("unrecognized parameter: '{s}'", .{arg});
                    }
                } else switch (Compilation.classifyFileExt(arg)) {
                    .object, .static_library, .shared_library => {
                        try link_objects.append(arg);
                    },
                    .assembly, .c, .cpp, .h, .ll, .bc => {
                        try c_source_files.append(.{
                            .src_path = arg,
                            .extra_flags = try arena.dupe([]const u8, extra_cflags.items),
                        });
                    },
                    .zig => {
                        if (root_src_file) |other| {
                            fatal("found another zig file '{s}' after root source file '{s}'", .{ arg, other });
                        } else {
                            root_src_file = arg;
                        }
                    },
                    .unknown => {
                        fatal("unrecognized file extension of parameter '{s}'", .{arg});
                    },
                }
            }
            if (optimize_mode_string) |s| {
                optimize_mode = std.meta.stringToEnum(std.builtin.Mode, s) orelse
                    fatal("unrecognized optimization mode: '{s}'", .{s});
            }
        },
        .cc, .cpp => {
            emit_h = .no;
            soname = .no;
            strip = true;
            ensure_libc_on_non_freestanding = true;
            ensure_libcpp_on_non_freestanding = arg_mode == .cpp;
            want_native_include_dirs = true;
            // Clang's driver enables this switch unconditionally.
            // Disabling the emission of .eh_frame_hdr can unexpectedly break
            // some functionality that depend on it, such as C++ exceptions and
            // DWARF-based stack traces.
            link_eh_frame_hdr = true;

            const COutMode = enum {
                link,
                object,
                assembly,
                preprocessor,
            };
            var c_out_mode: COutMode = .link;
            var out_path: ?[]const u8 = null;
            var is_shared_lib = false;
            var linker_args = std.ArrayList([]const u8).init(arena);
            var it = ClangArgIterator.init(arena, all_args);
            while (it.has_next) {
                it.next() catch |err| {
                    fatal("unable to parse command line parameters: {s}", .{@errorName(err)});
                };
                switch (it.zig_equivalent) {
                    .target => target_arch_os_abi = it.only_arg, // example: -target riscv64-linux-unknown
                    .o => out_path = it.only_arg, // -o
                    .c => c_out_mode = .object, // -c
                    .asm_only => c_out_mode = .assembly, // -S
                    .preprocess_only => c_out_mode = .preprocessor, // -E
                    .other => {
                        try clang_argv.appendSlice(it.other_args);
                    },
                    .positional => {
                        const file_ext = Compilation.classifyFileExt(mem.spanZ(it.only_arg));
                        switch (file_ext) {
                            .assembly, .c, .cpp, .ll, .bc, .h => try c_source_files.append(.{ .src_path = it.only_arg }),
                            .unknown, .shared_library, .object, .static_library => {
                                try link_objects.append(it.only_arg);
                            },
                            .zig => {
                                if (root_src_file) |other| {
                                    fatal("found another zig file '{s}' after root source file '{s}'", .{ it.only_arg, other });
                                } else {
                                    root_src_file = it.only_arg;
                                }
                            },
                        }
                    },
                    .l => {
                        // -l
                        // We don't know whether this library is part of libc or libc++ until we resolve the target.
                        // So we simply append to the list for now.
                        try system_libs.append(it.only_arg);
                    },
                    .ignore => {},
                    .driver_punt => {
                        // Never mind what we're doing, just pass the args directly. For example --help.
                        return punt_to_clang(arena, all_args);
                    },
                    .pic => want_pic = true,
                    .no_pic => want_pic = false,
                    .pie => want_pie = true,
                    .no_pie => want_pie = false,
                    .lto => want_lto = true,
                    .no_lto => want_lto = false,
                    .red_zone => want_red_zone = true,
                    .no_red_zone => want_red_zone = false,
                    .nostdlib => ensure_libc_on_non_freestanding = false,
                    .nostdlib_cpp => ensure_libcpp_on_non_freestanding = false,
                    .shared => {
                        link_mode = .Dynamic;
                        is_shared_lib = true;
                    },
                    .rdynamic => rdynamic = true,
                    .wl => {
                        var split_it = mem.split(it.only_arg, ",");
                        while (split_it.next()) |linker_arg| {
                            try linker_args.append(linker_arg);
                        }
                    },
                    .optimize => {
                        // Alright, what release mode do they want?
                        const level = if (it.only_arg.len >= 1 and it.only_arg[0] == 'O') it.only_arg[1..] else it.only_arg;
                        if (mem.eql(u8, level, "s") or
                            mem.eql(u8, level, "z"))
                        {
                            optimize_mode = .ReleaseSmall;
                        } else if (mem.eql(u8, level, "1") or
                            mem.eql(u8, level, "2") or
                            mem.eql(u8, level, "3") or
                            mem.eql(u8, level, "4") or
                            mem.eql(u8, level, "fast"))
                        {
                            optimize_mode = .ReleaseFast;
                        } else if (mem.eql(u8, level, "g") or
                            mem.eql(u8, level, "0"))
                        {
                            optimize_mode = .Debug;
                        } else {
                            try clang_argv.appendSlice(it.other_args);
                        }
                    },
                    .debug => {
                        strip = false;
                        if (mem.eql(u8, it.only_arg, "g")) {
                            // We handled with strip = false above.
                        } else if (mem.eql(u8, it.only_arg, "g1") or
                            mem.eql(u8, it.only_arg, "gline-tables-only"))
                        {
                            // We handled with strip = false above. but we also want reduced debug info.
                            try clang_argv.append("-gline-tables-only");
                        } else {
                            try clang_argv.appendSlice(it.other_args);
                        }
                    },
                    .sanitize => {
                        if (mem.eql(u8, it.only_arg, "undefined")) {
                            want_sanitize_c = true;
                        } else if (mem.eql(u8, it.only_arg, "thread")) {
                            want_tsan = true;
                        } else {
                            try clang_argv.appendSlice(it.other_args);
                        }
                    },
                    .linker_script => linker_script = it.only_arg,
                    .verbose => {
                        verbose_link = true;
                        // Have Clang print more infos, some tools such as CMake
                        // parse this to discover any implicit include and
                        // library dir to look-up into.
                        try clang_argv.append("-v");
                    },
                    .dry_run => {
                        verbose_link = true;
                        try clang_argv.append("-###");
                        // XXX: Don't execute anything!
                    },
                    .for_linker => try linker_args.append(it.only_arg),
                    .linker_input_z => {
                        try linker_args.append("-z");
                        try linker_args.append(it.only_arg);
                    },
                    .lib_dir => try lib_dirs.append(it.only_arg),
                    .mcpu => target_mcpu = it.only_arg,
                    .dep_file => {
                        disable_c_depfile = true;
                        try clang_argv.appendSlice(it.other_args);
                    },
                    .dep_file_mm => { // -MM
                        // "Like -MMD, but also implies -E and writes to stdout by default"
                        c_out_mode = .preprocessor;
                        disable_c_depfile = true;
                        try clang_argv.appendSlice(it.other_args);
                    },
                    .framework_dir => try framework_dirs.append(it.only_arg),
                    .framework => try frameworks.append(it.only_arg),
                    .nostdlibinc => want_native_include_dirs = false,
                    .strip => strip = true,
                }
            }
            // Parse linker args.
            var i: usize = 0;
            while (i < linker_args.items.len) : (i += 1) {
                const arg = linker_args.items[i];
                if (mem.eql(u8, arg, "-soname")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    const name = linker_args.items[i];
                    soname = .{ .yes = name };
                    // Use it as --name.
                    // Example: libsoundio.so.2
                    var prefix: usize = 0;
                    if (mem.startsWith(u8, name, "lib")) {
                        prefix = 3;
                    }
                    var end: usize = name.len;
                    if (mem.endsWith(u8, name, ".so")) {
                        end -= 3;
                    } else {
                        var found_digit = false;
                        while (end > 0 and std.ascii.isDigit(name[end - 1])) {
                            found_digit = true;
                            end -= 1;
                        }
                        if (found_digit and end > 0 and name[end - 1] == '.') {
                            end -= 1;
                        } else {
                            end = name.len;
                        }
                        if (mem.endsWith(u8, name[prefix..end], ".so")) {
                            end -= 3;
                        }
                    }
                    provided_name = name[prefix..end];
                } else if (mem.eql(u8, arg, "-rpath")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    try rpath_list.append(linker_args.items[i]);
                } else if (mem.eql(u8, arg, "-I") or
                    mem.eql(u8, arg, "--dynamic-linker") or
                    mem.eql(u8, arg, "-dynamic-linker"))
                {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    target_dynamic_linker = linker_args.items[i];
                } else if (mem.eql(u8, arg, "-E") or
                    mem.eql(u8, arg, "--export-dynamic") or
                    mem.eql(u8, arg, "-export-dynamic"))
                {
                    rdynamic = true;
                } else if (mem.eql(u8, arg, "--version-script")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    version_script = linker_args.items[i];
                } else if (mem.startsWith(u8, arg, "-O")) {
                    try lld_argv.append(arg);
                } else if (mem.eql(u8, arg, "--gc-sections")) {
                    linker_gc_sections = true;
                } else if (mem.eql(u8, arg, "--no-gc-sections")) {
                    linker_gc_sections = false;
                } else if (mem.eql(u8, arg, "--allow-shlib-undefined") or
                    mem.eql(u8, arg, "-allow-shlib-undefined"))
                {
                    linker_allow_shlib_undefined = true;
                } else if (mem.eql(u8, arg, "--no-allow-shlib-undefined") or
                    mem.eql(u8, arg, "-no-allow-shlib-undefined"))
                {
                    linker_allow_shlib_undefined = false;
                } else if (mem.eql(u8, arg, "-Bsymbolic")) {
                    linker_bind_global_refs_locally = true;
                } else if (mem.eql(u8, arg, "-z")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    const z_arg = linker_args.items[i];
                    if (mem.eql(u8, z_arg, "nodelete")) {
                        linker_z_nodelete = true;
                    } else if (mem.eql(u8, z_arg, "defs")) {
                        linker_z_defs = true;
                    } else {
                        warn("unsupported linker arg: -z {s}", .{z_arg});
                    }
                } else if (mem.eql(u8, arg, "--major-image-version")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    version.major = std.fmt.parseUnsigned(u32, linker_args.items[i], 10) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                    have_version = true;
                } else if (mem.eql(u8, arg, "--minor-image-version")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    version.minor = std.fmt.parseUnsigned(u32, linker_args.items[i], 10) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                    have_version = true;
                } else if (mem.eql(u8, arg, "--stack")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    stack_size_override = std.fmt.parseUnsigned(u64, linker_args.items[i], 0) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                } else if (mem.eql(u8, arg, "--image-base")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    image_base_override = std.fmt.parseUnsigned(u64, linker_args.items[i], 0) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                } else if (mem.eql(u8, arg, "-T")) {
                    i += 1;
                    if (i >= linker_args.items.len) {
                        fatal("expected linker arg after '{s}'", .{arg});
                    }
                    linker_script = linker_args.items[i];
                } else if (mem.eql(u8, arg, "--eh-frame-hdr")) {
                    link_eh_frame_hdr = true;
                } else if (mem.eql(u8, arg, "--no-eh-frame-hdr")) {
                    link_eh_frame_hdr = false;
                } else if (mem.eql(u8, arg, "--tsaware")) {
                    linker_tsaware = true;
                } else if (mem.eql(u8, arg, "--nxcompat")) {
                    linker_nxcompat = true;
                } else if (mem.eql(u8, arg, "--dynamicbase")) {
                    linker_dynamicbase = true;
                } else if (mem.eql(u8, arg, "--high-entropy-va")) {
                    // This option does not do anything.
                } else if (mem.eql(u8, arg, "--export-all-symbols")) {
                    rdynamic = true;
                } else if (mem.eql(u8, arg, "--start-group") or
                    mem.eql(u8, arg, "--end-group"))
                {
                    // We don't need to care about these because these args are
                    // for resolving circular dependencies but our linker takes
                    // care of this without explicit args.
                } else if (mem.startsWith(u8, arg, "--major-os-version") or
                    mem.startsWith(u8, arg, "--minor-os-version"))
                {
                    // This option does not do anything.
                } else if (mem.startsWith(u8, arg, "--major-subsystem-version=")) {
                    major_subsystem_version = std.fmt.parseUnsigned(
                        u32,
                        arg["--major-subsystem-version=".len..],
                        10,
                    ) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                } else if (mem.startsWith(u8, arg, "--minor-subsystem-version=")) {
                    minor_subsystem_version = std.fmt.parseUnsigned(
                        u32,
                        arg["--minor-subsystem-version=".len..],
                        10,
                    ) catch |err| {
                        fatal("unable to parse '{s}': {s}", .{ arg, @errorName(err) });
                    };
                } else if (mem.startsWith(u8, arg, "--major-os-version=") or
                    mem.startsWith(u8, arg, "--minor-os-version="))
                {
                    // These args do nothing.
                } else {
                    warn("unsupported linker arg: {s}", .{arg});
                }
            }

            if (want_sanitize_c) |wsc| {
                if (wsc and optimize_mode == .ReleaseFast) {
                    optimize_mode = .ReleaseSafe;
                }
            }

            switch (c_out_mode) {
                .link => {
                    output_mode = if (is_shared_lib) .Lib else .Exe;
                    emit_bin = if (out_path) |p| .{ .yes = p } else EmitBin.yes_a_out;
                    enable_cache = true;
                },
                .object => {
                    output_mode = .Obj;
                    if (out_path) |p| {
                        emit_bin = .{ .yes = p };
                    } else {
                        emit_bin = .yes_default_path;
                    }
                },
                .assembly => {
                    output_mode = .Obj;
                    emit_bin = .no;
                    if (out_path) |p| {
                        emit_asm = .{ .yes = p };
                    } else {
                        emit_asm = .yes_default_path;
                    }
                },
                .preprocessor => {
                    output_mode = .Obj;
                    // An error message is generated when there is more than 1 C source file.
                    if (c_source_files.items.len != 1) {
                        // For example `zig cc` and no args should print the "no input files" message.
                        return punt_to_clang(arena, all_args);
                    }
                    if (out_path) |p| {
                        emit_bin = .{ .yes = p };
                        clang_preprocessor_mode = .yes;
                    } else {
                        clang_preprocessor_mode = .stdout;
                    }
                },
            }
            if (c_source_files.items.len == 0 and link_objects.items.len == 0) {
                // For example `zig cc` and no args should print the "no input files" message.
                return punt_to_clang(arena, all_args);
            }
        },
    }

    if (arg_mode == .translate_c and c_source_files.items.len != 1) {
        fatal("translate-c expects exactly 1 source file (found {d})", .{c_source_files.items.len});
    }

    if (root_src_file == null and arg_mode == .zig_test) {
        fatal("`zig test` expects a zig source file argument", .{});
    }

    const root_name = if (provided_name) |n| n else blk: {
        if (arg_mode == .zig_test) {
            break :blk "test";
        } else if (root_src_file) |file| {
            const basename = fs.path.basename(file);
            break :blk basename[0 .. basename.len - fs.path.extension(basename).len];
        } else if (c_source_files.items.len >= 1) {
            const basename = fs.path.basename(c_source_files.items[0].src_path);
            break :blk basename[0 .. basename.len - fs.path.extension(basename).len];
        } else if (link_objects.items.len >= 1) {
            const basename = fs.path.basename(link_objects.items[0]);
            break :blk basename[0 .. basename.len - fs.path.extension(basename).len];
        } else if (emit_bin == .yes) {
            const basename = fs.path.basename(emit_bin.yes);
            break :blk basename[0 .. basename.len - fs.path.extension(basename).len];
        } else if (show_builtin) {
            break :blk "builtin";
        } else if (arg_mode == .run) {
            fatal("`zig run` expects at least one positional argument", .{});
            // TODO once the attempt to unwrap error: LinkingWithoutZigSourceUnimplemented
            // is solved, remove the above fatal() and uncomment the `break` below.
            //break :blk "run";
        } else {
            fatal("expected a positional argument, -femit-bin=[path], --show-builtin, or --name [name]", .{});
        }
    };

    var diags: std.zig.CrossTarget.ParseOptions.Diagnostics = .{};
    const cross_target = std.zig.CrossTarget.parse(.{
        .arch_os_abi = target_arch_os_abi,
        .cpu_features = target_mcpu,
        .dynamic_linker = target_dynamic_linker,
        .diagnostics = &diags,
    }) catch |err| switch (err) {
        error.UnknownCpuModel => {
            help: {
                var help_text = std.ArrayList(u8).init(arena);
                for (diags.arch.?.allCpuModels()) |cpu| {
                    help_text.writer().print(" {s}\n", .{cpu.name}) catch break :help;
                }
                std.log.info("Available CPUs for architecture '{s}':\n{s}", .{
                    @tagName(diags.arch.?), help_text.items,
                });
            }
            fatal("Unknown CPU: '{s}'", .{diags.cpu_name.?});
        },
        error.UnknownCpuFeature => {
            help: {
                var help_text = std.ArrayList(u8).init(arena);
                for (diags.arch.?.allFeaturesList()) |feature| {
                    help_text.writer().print(" {s}: {s}\n", .{ feature.name, feature.description }) catch break :help;
                }
                std.log.info("Available CPU features for architecture '{s}':\n{s}", .{
                    @tagName(diags.arch.?), help_text.items,
                });
            }
            fatal("Unknown CPU feature: '{s}'", .{diags.unknown_feature_name});
        },
        else => |e| return e,
    };

    const target_info = try detectNativeTargetInfo(gpa, cross_target);

    if (target_info.target.os.tag != .freestanding) {
        if (ensure_libc_on_non_freestanding)
            link_libc = true;
        if (ensure_libcpp_on_non_freestanding)
            link_libcpp = true;
    }

    // Now that we have target info, we can find out if any of the system libraries
    // are part of libc or libc++. We remove them from the list and communicate their
    // existence via flags instead.
    {
        var i: usize = 0;
        while (i < system_libs.items.len) {
            const lib_name = system_libs.items[i];
            if (target_util.is_libc_lib_name(target_info.target, lib_name)) {
                link_libc = true;
                _ = system_libs.orderedRemove(i);
                continue;
            }
            if (target_util.is_libcpp_lib_name(target_info.target, lib_name)) {
                link_libcpp = true;
                _ = system_libs.orderedRemove(i);
                continue;
            }
            if (std.fs.path.isAbsolute(lib_name)) {
                fatal("cannot use absolute path as a system library: {s}", .{lib_name});
            }
            i += 1;
        }
    }

    if (comptime std.Target.current.isDarwin()) {
        // If we want to link against frameworks, we need system headers.
        if (framework_dirs.items.len > 0 or frameworks.items.len > 0)
            want_native_include_dirs = true;
    }

    if (cross_target.isNativeOs() and (system_libs.items.len != 0 or want_native_include_dirs)) {
        const paths = std.zig.system.NativePaths.detect(arena, target_info) catch |err| {
            fatal("unable to detect native system paths: {s}", .{@errorName(err)});
        };
        for (paths.warnings.items) |warning| {
            warn("{s}", .{warning});
        }

        const has_sysroot = if (comptime std.Target.current.isDarwin()) outer: {
            const min = target_info.target.os.getVersionRange().semver.min;
            const at_least_catalina = min.major >= 11 or (min.major >= 10 and min.minor >= 15);
            if (at_least_catalina) {
                const sdk_path = try std.zig.system.getSDKPath(arena);
                try clang_argv.ensureCapacity(clang_argv.items.len + 2);
                clang_argv.appendAssumeCapacity("-isysroot");
                clang_argv.appendAssumeCapacity(sdk_path);
                break :outer true;
            }
            break :outer false;
        } else false;

        try clang_argv.ensureCapacity(clang_argv.items.len + paths.include_dirs.items.len * 2);
        const isystem_flag = if (has_sysroot) "-iwithsysroot" else "-isystem";
        for (paths.include_dirs.items) |include_dir| {
            clang_argv.appendAssumeCapacity(isystem_flag);
            clang_argv.appendAssumeCapacity(include_dir);
        }

        try clang_argv.ensureCapacity(clang_argv.items.len + paths.framework_dirs.items.len * 2);
        try framework_dirs.ensureCapacity(framework_dirs.items.len + paths.framework_dirs.items.len);
        const iframework_flag = if (has_sysroot) "-iframeworkwithsysroot" else "-iframework";
        for (paths.framework_dirs.items) |framework_dir| {
            clang_argv.appendAssumeCapacity(iframework_flag);
            clang_argv.appendAssumeCapacity(framework_dir);
            framework_dirs.appendAssumeCapacity(framework_dir);
        }

        for (paths.lib_dirs.items) |lib_dir| {
            try lib_dirs.append(lib_dir);
        }
        for (paths.rpaths.items) |rpath| {
            try rpath_list.append(rpath);
        }
    }

    const object_format: std.Target.ObjectFormat = blk: {
        const ofmt = target_ofmt orelse break :blk target_info.target.getObjectFormat();
        if (mem.eql(u8, ofmt, "elf")) {
            break :blk .elf;
        } else if (mem.eql(u8, ofmt, "c")) {
            break :blk .c;
        } else if (mem.eql(u8, ofmt, "coff")) {
            break :blk .coff;
        } else if (mem.eql(u8, ofmt, "pe")) {
            break :blk .pe;
        } else if (mem.eql(u8, ofmt, "macho")) {
            break :blk .macho;
        } else if (mem.eql(u8, ofmt, "wasm")) {
            break :blk .wasm;
        } else if (mem.eql(u8, ofmt, "hex")) {
            break :blk .hex;
        } else if (mem.eql(u8, ofmt, "raw")) {
            break :blk .raw;
        } else if (mem.eql(u8, ofmt, "spirv")) {
            break :blk .spirv;
        } else {
            fatal("unsupported object format: {s}", .{ofmt});
        }
    };

    if (output_mode == .Obj and (object_format == .coff or object_format == .macho)) {
        const total_obj_count = c_source_files.items.len +
            @boolToInt(root_src_file != null) +
            link_objects.items.len;
        if (total_obj_count > 1) {
            fatal("{s} does not support linking multiple objects into one", .{@tagName(object_format)});
        }
    }

    var cleanup_emit_bin_dir: ?fs.Dir = null;
    defer if (cleanup_emit_bin_dir) |*dir| dir.close();

    const have_enable_cache = enable_cache orelse false;
    const optional_version = if (have_version) version else null;

    const resolved_soname: ?[]const u8 = switch (soname) {
        .yes => |explicit| explicit,
        .no => null,
        .yes_default_value => switch (object_format) {
            .elf => if (have_version)
                try std.fmt.allocPrint(arena, "lib{s}.so.{d}", .{ root_name, version.major })
            else
                try std.fmt.allocPrint(arena, "lib{s}.so", .{root_name}),
            else => null,
        },
    };

    const a_out_basename = switch (object_format) {
        .pe, .coff => "a.exe",
        else => "a.out",
    };

    const emit_bin_loc: ?Compilation.EmitLoc = switch (emit_bin) {
        .no => null,
        .yes_default_path => Compilation.EmitLoc{
            .directory = blk: {
                switch (arg_mode) {
                    .run, .zig_test => break :blk null,
                    else => {
                        if (have_enable_cache) {
                            break :blk null;
                        } else {
                            break :blk .{ .path = null, .handle = fs.cwd() };
                        }
                    },
                }
            },
            .basename = try std.zig.binNameAlloc(arena, .{
                .root_name = root_name,
                .target = target_info.target,
                .output_mode = output_mode,
                .link_mode = link_mode,
                .object_format = object_format,
                .version = optional_version,
            }),
        },
        .yes => |full_path| b: {
            const basename = fs.path.basename(full_path);
            if (have_enable_cache) {
                break :b Compilation.EmitLoc{
                    .basename = basename,
                    .directory = null,
                };
            }
            if (fs.path.dirname(full_path)) |dirname| {
                const handle = fs.cwd().openDir(dirname, .{}) catch |err| {
                    fatal("unable to open output directory '{s}': {s}", .{ dirname, @errorName(err) });
                };
                cleanup_emit_bin_dir = handle;
                break :b Compilation.EmitLoc{
                    .basename = basename,
                    .directory = .{
                        .path = dirname,
                        .handle = handle,
                    },
                };
            } else {
                break :b Compilation.EmitLoc{
                    .basename = basename,
                    .directory = .{ .path = null, .handle = fs.cwd() },
                };
            }
        },
        .yes_a_out => Compilation.EmitLoc{
            .directory = null,
            .basename = a_out_basename,
        },
    };

    const default_h_basename = try std.fmt.allocPrint(arena, "{s}.h", .{root_name});
    var emit_h_resolved = try emit_h.resolve(default_h_basename);
    defer emit_h_resolved.deinit();

    const default_asm_basename = try std.fmt.allocPrint(arena, "{s}.s", .{root_name});
    var emit_asm_resolved = try emit_asm.resolve(default_asm_basename);
    defer emit_asm_resolved.deinit();

    const default_llvm_ir_basename = try std.fmt.allocPrint(arena, "{s}.ll", .{root_name});
    var emit_llvm_ir_resolved = try emit_llvm_ir.resolve(default_llvm_ir_basename);
    defer emit_llvm_ir_resolved.deinit();

    const default_analysis_basename = try std.fmt.allocPrint(arena, "{s}-analysis.json", .{root_name});
    var emit_analysis_resolved = try emit_analysis.resolve(default_analysis_basename);
    defer emit_analysis_resolved.deinit();

    var emit_docs_resolved = try emit_docs.resolve("docs");
    defer emit_docs_resolved.deinit();

    const root_pkg: ?*Package = if (root_src_file) |src_path| blk: {
        if (main_pkg_path) |p| {
            const rel_src_path = try fs.path.relative(gpa, p, src_path);
            defer gpa.free(rel_src_path);
            break :blk try Package.create(gpa, p, rel_src_path);
        } else {
            break :blk try Package.create(gpa, fs.path.dirname(src_path), fs.path.basename(src_path));
        }
    } else null;
    defer if (root_pkg) |p| p.destroy(gpa);

    // Transfer packages added with --pkg-begin/--pkg-end to the root package
    if (root_pkg) |pkg| {
        pkg.table = pkg_tree_root.table;
        pkg_tree_root.table = .{};
        pkg.namespace_hash = pkg_tree_root.namespace_hash;
    }

    const self_exe_path = try fs.selfExePathAlloc(arena);
    var zig_lib_directory: Compilation.Directory = if (override_lib_dir) |lib_dir| .{
        .path = lib_dir,
        .handle = try fs.cwd().openDir(lib_dir, .{}),
    } else introspect.findZigLibDirFromSelfExe(arena, self_exe_path) catch |err| {
        fatal("unable to find zig installation directory: {s}", .{@errorName(err)});
    };
    defer zig_lib_directory.handle.close();

    var thread_pool: ThreadPool = undefined;
    try thread_pool.init(gpa);
    defer thread_pool.deinit();

    var libc_installation: ?LibCInstallation = null;
    defer if (libc_installation) |*l| l.deinit(gpa);

    if (libc_paths_file) |paths_file| {
        libc_installation = LibCInstallation.parse(gpa, paths_file) catch |err| {
            fatal("unable to parse libc paths file: {s}", .{@errorName(err)});
        };
    }

    var global_cache_directory: Compilation.Directory = l: {
        const p = override_global_cache_dir orelse try introspect.resolveGlobalCacheDir(arena);
        break :l .{
            .handle = try fs.cwd().makeOpenPath(p, .{}),
            .path = p,
        };
    };
    defer global_cache_directory.handle.close();

    var cleanup_local_cache_dir: ?fs.Dir = null;
    defer if (cleanup_local_cache_dir) |*dir| dir.close();

    var local_cache_directory: Compilation.Directory = l: {
        if (override_local_cache_dir) |local_cache_dir_path| {
            const dir = try fs.cwd().makeOpenPath(local_cache_dir_path, .{});
            cleanup_local_cache_dir = dir;
            break :l .{
                .handle = dir,
                .path = local_cache_dir_path,
            };
        }
        if (arg_mode == .run) {
            break :l global_cache_directory;
        }
        if (root_pkg) |pkg| {
            const cache_dir_path = try pkg.root_src_directory.join(arena, &[_][]const u8{"zig-cache"});
            const dir = try pkg.root_src_directory.handle.makeOpenPath("zig-cache", .{});
            cleanup_local_cache_dir = dir;
            break :l .{
                .handle = dir,
                .path = cache_dir_path,
            };
        }
        // Otherwise we really don't have a reasonable place to put the local cache directory,
        // so we utilize the global one.
        break :l global_cache_directory;
    };

    if (build_options.have_llvm and emit_asm != .no) {
        // LLVM has no way to set this non-globally.
        const argv = [_][*:0]const u8{ "zig (LLVM option parsing)", "--x86-asm-syntax=intel" };
        @import("codegen/llvm/bindings.zig").ParseCommandLineOptions(argv.len, &argv);
    }

    const clang_passthrough_mode = switch (arg_mode) {
        .cc, .cpp, .translate_c => true,
        else => false,
    };

    gimmeMoreOfThoseSweetSweetFileDescriptors();

    const comp = Compilation.create(gpa, .{
        .zig_lib_directory = zig_lib_directory,
        .local_cache_directory = local_cache_directory,
        .global_cache_directory = global_cache_directory,
        .root_name = root_name,
        .target = target_info.target,
        .is_native_os = cross_target.isNativeOs(),
        .is_native_abi = cross_target.isNativeAbi(),
        .dynamic_linker = target_info.dynamic_linker.get(),
        .output_mode = output_mode,
        .root_pkg = root_pkg,
        .emit_bin = emit_bin_loc,
        .emit_h = emit_h_resolved.data,
        .emit_asm = emit_asm_resolved.data,
        .emit_llvm_ir = emit_llvm_ir_resolved.data,
        .emit_docs = emit_docs_resolved.data,
        .emit_analysis = emit_analysis_resolved.data,
        .link_mode = link_mode,
        .dll_export_fns = dll_export_fns,
        .object_format = object_format,
        .optimize_mode = optimize_mode,
        .keep_source_files_loaded = false,
        .clang_argv = clang_argv.items,
        .lld_argv = lld_argv.items,
        .lib_dirs = lib_dirs.items,
        .rpath_list = rpath_list.items,
        .c_source_files = c_source_files.items,
        .link_objects = link_objects.items,
        .framework_dirs = framework_dirs.items,
        .frameworks = frameworks.items,
        .system_libs = system_libs.items,
        .link_libc = link_libc,
        .link_libcpp = link_libcpp,
        .want_pic = want_pic,
        .want_pie = want_pie,
        .want_lto = want_lto,
        .want_sanitize_c = want_sanitize_c,
        .want_stack_check = want_stack_check,
        .want_red_zone = want_red_zone,
        .want_valgrind = want_valgrind,
        .want_tsan = want_tsan,
        .want_compiler_rt = want_compiler_rt,
        .use_llvm = use_llvm,
        .use_lld = use_lld,
        .use_clang = use_clang,
        .rdynamic = rdynamic,
        .linker_script = linker_script,
        .version_script = version_script,
        .disable_c_depfile = disable_c_depfile,
        .soname = resolved_soname,
        .linker_gc_sections = linker_gc_sections,
        .linker_allow_shlib_undefined = linker_allow_shlib_undefined,
        .linker_bind_global_refs_locally = linker_bind_global_refs_locally,
        .linker_z_nodelete = linker_z_nodelete,
        .linker_z_defs = linker_z_defs,
        .linker_tsaware = linker_tsaware,
        .linker_nxcompat = linker_nxcompat,
        .linker_dynamicbase = linker_dynamicbase,
        .major_subsystem_version = major_subsystem_version,
        .minor_subsystem_version = minor_subsystem_version,
        .link_eh_frame_hdr = link_eh_frame_hdr,
        .link_emit_relocs = link_emit_relocs,
        .stack_size_override = stack_size_override,
        .image_base_override = image_base_override,
        .strip = strip,
        .single_threaded = single_threaded,
        .function_sections = function_sections,
        .self_exe_path = self_exe_path,
        .thread_pool = &thread_pool,
        .clang_passthrough_mode = clang_passthrough_mode,
        .clang_preprocessor_mode = clang_preprocessor_mode,
        .version = optional_version,
        .libc_installation = if (libc_installation) |*lci| lci else null,
        .verbose_cc = verbose_cc,
        .verbose_link = verbose_link,
        .verbose_tokenize = verbose_tokenize,
        .verbose_ast = verbose_ast,
        .verbose_ir = verbose_ir,
        .verbose_llvm_ir = verbose_llvm_ir,
        .verbose_cimport = verbose_cimport,
        .verbose_llvm_cpu_features = verbose_llvm_cpu_features,
        .machine_code_model = machine_code_model,
        .color = color,
        .time_report = time_report,
        .stack_report = stack_report,
        .is_test = arg_mode == .zig_test,
        .each_lib_rpath = each_lib_rpath,
        .test_evented_io = test_evented_io,
        .test_filter = test_filter,
        .test_name_prefix = test_name_prefix,
        .disable_lld_caching = !have_enable_cache,
        .subsystem = subsystem,
    }) catch |err| {
        fatal("unable to create compilation: {s}", .{@errorName(err)});
    };
    var comp_destroyed = false;
    defer if (!comp_destroyed) comp.destroy();

    if (show_builtin) {
        return std.io.getStdOut().writeAll(try comp.generateBuiltinZigSource(arena));
    }
    if (arg_mode == .translate_c) {
        return cmdTranslateC(comp, arena, have_enable_cache);
    }

    const hook: AfterUpdateHook = blk: {
        if (!have_enable_cache)
            break :blk .none;

        switch (emit_bin) {
            .no => break :blk .none,
            .yes_default_path => break :blk .{
                .print = comp.bin_file.options.emit.?.directory.path orelse ".",
            },
            .yes => |full_path| break :blk .{ .update = full_path },
            .yes_a_out => break :blk .{ .update = a_out_basename },
        }
    };

    updateModule(gpa, comp, hook) catch |err| switch (err) {
        error.SemanticAnalyzeFail => if (!watch) process.exit(1),
        else => |e| return e,
    };
    try comp.makeBinFileExecutable();

    if (build_options.is_stage1 and comp.stage1_lock != null and watch) {
        warn("--watch is not recommended with the stage1 backend; it leaks memory and is not capable of incremental compilation", .{});
    }

    const run_or_test = switch (arg_mode) {
        .run, .zig_test => true,
        else => false,
    };
    if (run_or_test) run: {
        const exe_loc = emit_bin_loc orelse break :run;
        const exe_directory = exe_loc.directory orelse comp.bin_file.options.emit.?.directory;
        const exe_path = try fs.path.join(arena, &[_][]const u8{
            exe_directory.path orelse ".", exe_loc.basename,
        });

        var argv = std.ArrayList([]const u8).init(gpa);
        defer argv.deinit();

        if (test_exec_args.items.len == 0) {
            if (!std.Target.current.canExecBinariesOf(target_info.target)) {
                switch (arg_mode) {
                    .zig_test => {
                        warn("created {s} but skipping execution because it is non-native", .{exe_path});
                        if (!watch) return cleanExit();
                        break :run;
                    },
                    .run => fatal("unable to execute {s}: non-native", .{exe_path}),
                    else => unreachable,
                }
            }
            // when testing pass the zig_exe_path to argv
            if (arg_mode == .zig_test)
                try argv.appendSlice(&[_][]const u8{
                    exe_path, self_exe_path,
                })
                // when running just pass the current exe
            else
                try argv.appendSlice(&[_][]const u8{
                    exe_path,
                });
        } else {
            for (test_exec_args.items) |arg| {
                if (arg) |a| {
                    try argv.append(a);
                } else {
                    try argv.appendSlice(&[_][]const u8{
                        exe_path, self_exe_path,
                    });
                }
            }
        }
        if (runtime_args_start) |i| {
            try argv.appendSlice(all_args[i..]);
        }
        // We do not execve for tests because if the test fails we want to print
        // the error message and invocation below.
        if (std.process.can_execv and arg_mode == .run and !watch) {
            // execv releases the locks; no need to destroy the Compilation here.
            const err = std.process.execv(gpa, argv.items);
            const cmd = try argvCmd(arena, argv.items);
            fatal("the following command failed to execve with '{s}':\n{s}", .{ @errorName(err), cmd });
        } else {
            const child = try std.ChildProcess.init(argv.items, gpa);
            defer child.deinit();

            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;

            if (!watch) {
                // Here we release all the locks associated with the Compilation so
                // that whatever this child process wants to do won't deadlock.
                comp.destroy();
                comp_destroyed = true;
            }

            const term = try child.spawnAndWait();
            switch (arg_mode) {
                .run => {
                    switch (term) {
                        .Exited => |code| {
                            if (code == 0) {
                                if (!watch) return cleanExit();
                            } else {
                                // TODO https://github.com/ziglang/zig/issues/6342
                                process.exit(1);
                            }
                        },
                        else => process.exit(1),
                    }
                },
                .zig_test => {
                    switch (term) {
                        .Exited => |code| {
                            if (code == 0) {
                                if (!watch) return cleanExit();
                            } else {
                                const cmd = try argvCmd(arena, argv.items);
                                fatal("the following test command failed with exit code {d}:\n{s}", .{ code, cmd });
                            }
                        },
                        else => {
                            const cmd = try argvCmd(arena, argv.items);
                            fatal("the following test command crashed:\n{s}", .{cmd});
                        },
                    }
                },
                else => unreachable,
            }
        }
    }

    const stdin = std.io.getStdIn().reader();
    const stderr = std.io.getStdErr().writer();
    var repl_buf: [1024]u8 = undefined;

    while (watch) {
        try stderr.print("(zig) ", .{});
        try comp.makeBinFileExecutable();
        if (stdin.readUntilDelimiterOrEof(&repl_buf, '\n') catch |err| {
            try stderr.print("\nUnable to parse command: {s}\n", .{@errorName(err)});
            continue;
        }) |line| {
            const actual_line = mem.trimRight(u8, line, "\r\n ");

            if (mem.eql(u8, actual_line, "update")) {
                if (output_mode == .Exe) {
                    try comp.makeBinFileWritable();
                }
                updateModule(gpa, comp, hook) catch |err| switch (err) {
                    error.SemanticAnalyzeFail => continue,
                    else => |e| return e,
                };
            } else if (mem.eql(u8, actual_line, "exit")) {
                break;
            } else if (mem.eql(u8, actual_line, "help")) {
                try stderr.writeAll(repl_help);
            } else {
                try stderr.print("unknown command: {s}\n", .{actual_line});
            }
        } else {
            break;
        }
    }
}

const AfterUpdateHook = union(enum) {
    none,
    print: []const u8,
    update: []const u8,
};

fn updateModule(gpa: *Allocator, comp: *Compilation, hook: AfterUpdateHook) !void {
    try comp.update();

    var errors = try comp.getAllErrorsAlloc();
    defer errors.deinit(comp.gpa);

    if (errors.list.len != 0) {
        const ttyconf: std.debug.TTY.Config = switch (comp.color) {
            .auto, .on => std.debug.detectTTYConfig(),
            .off => .no_color,
        };
        for (errors.list) |full_err_msg| {
            full_err_msg.renderToStdErr(ttyconf);
        }
        const log_text = comp.getCompileLogOutput();
        if (log_text.len != 0) {
            std.debug.print("\nCompile Log Output:\n{s}", .{log_text});
        }
        return error.SemanticAnalyzeFail;
    } else switch (hook) {
        .none => {},
        .print => |bin_path| try io.getStdOut().writer().print("{s}\n", .{bin_path}),
        .update => |full_path| {
            const bin_sub_path = comp.bin_file.options.emit.?.sub_path;
            const cwd = fs.cwd();
            const cache_dir = comp.bin_file.options.emit.?.directory.handle;
            _ = try cache_dir.updateFile(bin_sub_path, cwd, full_path, .{});

            // If a .pdb file is part of the expected output, we must also copy
            // it into place here.
            const coff_or_pe = switch (comp.bin_file.options.object_format) {
                .coff, .pe => true,
                else => false,
            };
            const have_pdb = coff_or_pe and !comp.bin_file.options.strip;
            if (have_pdb) {
                // Replace `.out` or `.exe` with `.pdb` on both the source and destination
                const src_bin_ext = fs.path.extension(bin_sub_path);
                const dst_bin_ext = fs.path.extension(full_path);

                const src_pdb_path = try std.fmt.allocPrint(gpa, "{s}.pdb", .{
                    bin_sub_path[0 .. bin_sub_path.len - src_bin_ext.len],
                });
                defer gpa.free(src_pdb_path);

                const dst_pdb_path = try std.fmt.allocPrint(gpa, "{s}.pdb", .{
                    full_path[0 .. full_path.len - dst_bin_ext.len],
                });
                defer gpa.free(dst_pdb_path);

                _ = try cache_dir.updateFile(src_pdb_path, cwd, dst_pdb_path, .{});
            }
        },
    }
}

fn freePkgTree(gpa: *Allocator, pkg: *Package, free_parent: bool) void {
    {
        var it = pkg.table.iterator();
        while (it.next()) |kv| {
            freePkgTree(gpa, kv.value, true);
        }
    }
    if (free_parent) {
        pkg.destroy(gpa);
    }
}

fn cmdTranslateC(comp: *Compilation, arena: *Allocator, enable_cache: bool) !void {
    if (!build_options.have_llvm)
        fatal("cannot translate-c: compiler built without LLVM extensions", .{});

    assert(comp.c_source_files.len == 1);
    const c_source_file = comp.c_source_files[0];

    const translated_zig_basename = try std.fmt.allocPrint(arena, "{s}.zig", .{comp.bin_file.options.root_name});

    var man: Cache.Manifest = comp.obtainCObjectCacheManifest();
    defer if (enable_cache) man.deinit();

    man.hash.add(@as(u16, 0xb945)); // Random number to distinguish translate-c from compiling C objects
    _ = man.addFile(c_source_file.src_path, null) catch |err| {
        fatal("unable to process '{s}': {s}", .{ c_source_file.src_path, @errorName(err) });
    };

    const digest = if (try man.hit()) man.final() else digest: {
        var argv = std.ArrayList([]const u8).init(arena);

        var zig_cache_tmp_dir = try comp.local_cache_directory.handle.makeOpenPath("tmp", .{});
        defer zig_cache_tmp_dir.close();

        const ext = Compilation.classifyFileExt(c_source_file.src_path);
        const out_dep_path: ?[]const u8 = blk: {
            if (comp.disable_c_depfile or !ext.clangSupportsDepFile())
                break :blk null;

            const c_src_basename = fs.path.basename(c_source_file.src_path);
            const dep_basename = try std.fmt.allocPrint(arena, "{s}.d", .{c_src_basename});
            const out_dep_path = try comp.tmpFilePath(arena, dep_basename);
            break :blk out_dep_path;
        };

        try comp.addTranslateCCArgs(arena, &argv, ext, out_dep_path);
        try argv.append(c_source_file.src_path);

        if (comp.verbose_cc) {
            std.debug.print("clang ", .{});
            Compilation.dump_argv(argv.items);
        }

        // Convert to null terminated args.
        const new_argv_with_sentinel = try arena.alloc(?[*:0]const u8, argv.items.len + 1);
        new_argv_with_sentinel[argv.items.len] = null;
        const new_argv = new_argv_with_sentinel[0..argv.items.len :null];
        for (argv.items) |arg, i| {
            new_argv[i] = try arena.dupeZ(u8, arg);
        }

        const c_headers_dir_path = try comp.zig_lib_directory.join(arena, &[_][]const u8{"include"});
        const c_headers_dir_path_z = try arena.dupeZ(u8, c_headers_dir_path);
        var clang_errors: []translate_c.ClangErrMsg = &[0]translate_c.ClangErrMsg{};
        var tree = translate_c.translate(
            comp.gpa,
            new_argv.ptr,
            new_argv.ptr + new_argv.len,
            &clang_errors,
            c_headers_dir_path_z,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ASTUnitFailure => fatal("clang API returned errors but due to a clang bug, it is not exposing the errors for zig to see. For more details: https://github.com/ziglang/zig/issues/4455", .{}),
            error.SemanticAnalyzeFail => {
                for (clang_errors) |clang_err| {
                    std.debug.print("{s}:{d}:{d}: {s}\n", .{
                        if (clang_err.filename_ptr) |p| p[0..clang_err.filename_len] else "(no file)",
                        clang_err.line + 1,
                        clang_err.column + 1,
                        clang_err.msg_ptr[0..clang_err.msg_len],
                    });
                }
                process.exit(1);
            },
        };
        defer tree.deinit(comp.gpa);

        if (out_dep_path) |dep_file_path| {
            const dep_basename = std.fs.path.basename(dep_file_path);
            // Add the files depended on to the cache system.
            try man.addDepFilePost(zig_cache_tmp_dir, dep_basename);
            // Just to save disk space, we delete the file because it is never needed again.
            zig_cache_tmp_dir.deleteFile(dep_basename) catch |err| {
                warn("failed to delete '{s}': {s}", .{ dep_file_path, @errorName(err) });
            };
        }

        const digest = man.final();
        const o_sub_path = try fs.path.join(arena, &[_][]const u8{ "o", &digest });

        var o_dir = try comp.local_cache_directory.handle.makeOpenPath(o_sub_path, .{});
        defer o_dir.close();

        var zig_file = try o_dir.createFile(translated_zig_basename, .{});
        defer zig_file.close();

        const formatted = try tree.render(comp.gpa);
        defer comp.gpa.free(formatted);

        try zig_file.writeAll(formatted);

        man.writeManifest() catch |err| warn("failed to write cache manifest: {s}", .{
            @errorName(err),
        });

        break :digest digest;
    };

    if (enable_cache) {
        const full_zig_path = try comp.local_cache_directory.join(arena, &[_][]const u8{
            "o", &digest, translated_zig_basename,
        });
        try io.getStdOut().writer().print("{s}\n", .{full_zig_path});
        return cleanExit();
    } else {
        const out_zig_path = try fs.path.join(arena, &[_][]const u8{ "o", &digest, translated_zig_basename });
        const zig_file = try comp.local_cache_directory.handle.openFile(out_zig_path, .{});
        defer zig_file.close();
        try io.getStdOut().writeFileAll(zig_file, .{});
        return cleanExit();
    }
}

pub const usage_libc =
    \\Usage: zig libc
    \\
    \\    Detect the native libc installation and print the resulting
    \\    paths to stdout. You can save this into a file and then edit
    \\    the paths to create a cross compilation libc kit. Then you
    \\    can pass `--libc [file]` for Zig to use it.
    \\
    \\Usage: zig libc [paths_file]
    \\
    \\    Parse a libc installation text file and validate it.
    \\
;

pub fn cmdLibC(gpa: *Allocator, args: []const []const u8) !void {
    var input_file: ?[]const u8 = null;
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    const stdout = io.getStdOut().writer();
                    try stdout.writeAll(usage_libc);
                    return cleanExit();
                } else {
                    fatal("unrecognized parameter: '{s}'", .{arg});
                }
            } else if (input_file != null) {
                fatal("unexpected extra parameter: '{s}'", .{arg});
            } else {
                input_file = arg;
            }
        }
    }
    if (input_file) |libc_file| {
        var libc = LibCInstallation.parse(gpa, libc_file) catch |err| {
            fatal("unable to parse libc file: {s}", .{@errorName(err)});
        };
        defer libc.deinit(gpa);
    } else {
        var libc = LibCInstallation.findNative(.{
            .allocator = gpa,
            .verbose = true,
        }) catch |err| {
            fatal("unable to detect native libc: {s}", .{@errorName(err)});
        };
        defer libc.deinit(gpa);

        var bw = io.bufferedWriter(io.getStdOut().writer());
        try libc.render(bw.writer());
        try bw.flush();
    }
}

pub const usage_init =
    \\Usage: zig init-exe
    \\       zig init-lib
    \\
    \\   Initializes a `zig build` project in the current working
    \\   directory.
    \\
    \\Options:
    \\   -h, --help             Print this help and exit
    \\
    \\
;

pub fn cmdInit(
    gpa: *Allocator,
    arena: *Allocator,
    args: []const []const u8,
    output_mode: std.builtin.OutputMode,
) !void {
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    try io.getStdOut().writeAll(usage_init);
                    return cleanExit();
                } else {
                    fatal("unrecognized parameter: '{s}'", .{arg});
                }
            } else {
                fatal("unexpected extra parameter: '{s}'", .{arg});
            }
        }
    }
    const self_exe_path = try fs.selfExePathAlloc(arena);
    var zig_lib_directory = introspect.findZigLibDirFromSelfExe(arena, self_exe_path) catch |err| {
        fatal("unable to find zig installation directory: {s}\n", .{@errorName(err)});
    };
    defer zig_lib_directory.handle.close();

    const s = fs.path.sep_str;
    const template_sub_path = switch (output_mode) {
        .Obj => unreachable,
        .Lib => "std" ++ s ++ "special" ++ s ++ "init-lib",
        .Exe => "std" ++ s ++ "special" ++ s ++ "init-exe",
    };
    var template_dir = try zig_lib_directory.handle.openDir(template_sub_path, .{});
    defer template_dir.close();

    const cwd_path = try process.getCwdAlloc(arena);
    const cwd_basename = fs.path.basename(cwd_path);

    const max_bytes = 10 * 1024 * 1024;
    const build_zig_contents = template_dir.readFileAlloc(arena, "build.zig", max_bytes) catch |err| {
        fatal("unable to read template file 'build.zig': {s}", .{@errorName(err)});
    };
    var modified_build_zig_contents = std.ArrayList(u8).init(arena);
    try modified_build_zig_contents.ensureCapacity(build_zig_contents.len);
    for (build_zig_contents) |c| {
        if (c == '$') {
            try modified_build_zig_contents.appendSlice(cwd_basename);
        } else {
            try modified_build_zig_contents.append(c);
        }
    }
    const main_zig_contents = template_dir.readFileAlloc(arena, "src" ++ s ++ "main.zig", max_bytes) catch |err| {
        fatal("unable to read template file 'main.zig': {s}", .{@errorName(err)});
    };
    if (fs.cwd().access("build.zig", .{})) |_| {
        fatal("existing build.zig file would be overwritten", .{});
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => fatal("unable to test existence of build.zig: {s}\n", .{@errorName(err)}),
    }
    var src_dir = try fs.cwd().makeOpenPath("src", .{});
    defer src_dir.close();

    try src_dir.writeFile("main.zig", main_zig_contents);
    try fs.cwd().writeFile("build.zig", modified_build_zig_contents.items);

    std.log.info("Created build.zig", .{});
    std.log.info("Created src" ++ s ++ "main.zig", .{});

    switch (output_mode) {
        .Lib => std.log.info("Next, try `zig build --help` or `zig build test`", .{}),
        .Exe => std.log.info("Next, try `zig build --help` or `zig build run`", .{}),
        .Obj => unreachable,
    }
}

pub const usage_build =
    \\Usage: zig build [steps] [options]
    \\
    \\   Build a project from build.zig.
    \\
    \\Options:
    \\   -h, --help             Print this help and exit
    \\
    \\
;

pub fn cmdBuild(gpa: *Allocator, arena: *Allocator, args: []const []const u8) !void {
    // We want to release all the locks before executing the child process, so we make a nice
    // big block here to ensure the cleanup gets run when we extract out our argv.
    const child_argv = argv: {
        const self_exe_path = try fs.selfExePathAlloc(arena);

        var build_file: ?[]const u8 = null;
        var override_lib_dir: ?[]const u8 = null;
        var override_global_cache_dir: ?[]const u8 = null;
        var override_local_cache_dir: ?[]const u8 = null;
        var child_argv = std.ArrayList([]const u8).init(arena);

        const argv_index_exe = child_argv.items.len;
        _ = try child_argv.addOne();

        try child_argv.append(self_exe_path);

        const argv_index_build_file = child_argv.items.len;
        _ = try child_argv.addOne();

        const argv_index_cache_dir = child_argv.items.len;
        _ = try child_argv.addOne();

        const argv_index_global_cache_dir = child_argv.items.len;
        _ = try child_argv.addOne();

        {
            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                const arg = args[i];
                if (mem.startsWith(u8, arg, "-")) {
                    if (mem.eql(u8, arg, "--build-file")) {
                        if (i + 1 >= args.len) fatal("expected argument after '{s}'", .{arg});
                        i += 1;
                        build_file = args[i];
                        continue;
                    } else if (mem.eql(u8, arg, "--override-lib-dir")) {
                        if (i + 1 >= args.len) fatal("expected argument after '{s}'", .{arg});
                        i += 1;
                        override_lib_dir = args[i];
                        try child_argv.appendSlice(&[_][]const u8{ arg, args[i] });
                        continue;
                    } else if (mem.eql(u8, arg, "--cache-dir")) {
                        if (i + 1 >= args.len) fatal("expected argument after '{s}'", .{arg});
                        i += 1;
                        override_local_cache_dir = args[i];
                        continue;
                    } else if (mem.eql(u8, arg, "--global-cache-dir")) {
                        if (i + 1 >= args.len) fatal("expected argument after '{s}'", .{arg});
                        i += 1;
                        override_global_cache_dir = args[i];
                        continue;
                    }
                }
                try child_argv.append(arg);
            }
        }

        var zig_lib_directory: Compilation.Directory = if (override_lib_dir) |lib_dir| .{
            .path = lib_dir,
            .handle = try fs.cwd().openDir(lib_dir, .{}),
        } else introspect.findZigLibDirFromSelfExe(arena, self_exe_path) catch |err| {
            fatal("unable to find zig installation directory: {s}", .{@errorName(err)});
        };
        defer zig_lib_directory.handle.close();

        const std_special = "std" ++ fs.path.sep_str ++ "special";
        const special_dir_path = try zig_lib_directory.join(arena, &[_][]const u8{std_special});

        var root_pkg: Package = .{
            .root_src_directory = .{
                .path = special_dir_path,
                .handle = try zig_lib_directory.handle.openDir(std_special, .{}),
            },
            .root_src_path = "build_runner.zig",
            .namespace_hash = Package.root_namespace_hash,
        };
        defer root_pkg.root_src_directory.handle.close();

        var cleanup_build_dir: ?fs.Dir = null;
        defer if (cleanup_build_dir) |*dir| dir.close();

        const cwd_path = try process.getCwdAlloc(arena);
        const build_zig_basename = if (build_file) |bf| fs.path.basename(bf) else "build.zig";
        const build_directory: Compilation.Directory = blk: {
            if (build_file) |bf| {
                if (fs.path.dirname(bf)) |dirname| {
                    const dir = try fs.cwd().openDir(dirname, .{});
                    cleanup_build_dir = dir;
                    break :blk .{ .path = dirname, .handle = dir };
                }

                break :blk .{ .path = null, .handle = fs.cwd() };
            }
            // Search up parent directories until we find build.zig.
            var dirname: []const u8 = cwd_path;
            while (true) {
                const joined_path = try fs.path.join(arena, &[_][]const u8{ dirname, build_zig_basename });
                if (fs.cwd().access(joined_path, .{})) |_| {
                    const dir = try fs.cwd().openDir(dirname, .{});
                    break :blk .{ .path = dirname, .handle = dir };
                } else |err| switch (err) {
                    error.FileNotFound => {
                        dirname = fs.path.dirname(dirname) orelse {
                            std.log.info("{s}", .{
                                \\Initialize a 'build.zig' template file with `zig init-lib` or `zig init-exe`,
                                \\or see `zig --help` for more options.
                            });
                            fatal("No 'build.zig' file found, in the current directory or any parent directories.", .{});
                        };
                        continue;
                    },
                    else => |e| return e,
                }
            }
        };
        child_argv.items[argv_index_build_file] = build_directory.path orelse cwd_path;

        var build_pkg: Package = .{
            .root_src_directory = build_directory,
            .root_src_path = build_zig_basename,
            .namespace_hash = undefined,
        };
        try root_pkg.addAndAdopt(arena, "@build", &build_pkg);

        var global_cache_directory: Compilation.Directory = l: {
            const p = override_global_cache_dir orelse try introspect.resolveGlobalCacheDir(arena);
            break :l .{
                .handle = try fs.cwd().makeOpenPath(p, .{}),
                .path = p,
            };
        };
        defer global_cache_directory.handle.close();

        child_argv.items[argv_index_global_cache_dir] = global_cache_directory.path orelse cwd_path;

        var local_cache_directory: Compilation.Directory = l: {
            if (override_local_cache_dir) |local_cache_dir_path| {
                break :l .{
                    .handle = try fs.cwd().makeOpenPath(local_cache_dir_path, .{}),
                    .path = local_cache_dir_path,
                };
            }
            const cache_dir_path = try build_directory.join(arena, &[_][]const u8{"zig-cache"});
            break :l .{
                .handle = try build_directory.handle.makeOpenPath("zig-cache", .{}),
                .path = cache_dir_path,
            };
        };
        defer local_cache_directory.handle.close();

        child_argv.items[argv_index_cache_dir] = local_cache_directory.path orelse cwd_path;

        gimmeMoreOfThoseSweetSweetFileDescriptors();

        const cross_target: std.zig.CrossTarget = .{};
        const target_info = try detectNativeTargetInfo(gpa, cross_target);

        const exe_basename = try std.zig.binNameAlloc(arena, .{
            .root_name = "build",
            .target = target_info.target,
            .output_mode = .Exe,
        });
        const emit_bin: Compilation.EmitLoc = .{
            .directory = null, // Use the local zig-cache.
            .basename = exe_basename,
        };
        var thread_pool: ThreadPool = undefined;
        try thread_pool.init(gpa);
        defer thread_pool.deinit();
        const comp = Compilation.create(gpa, .{
            .zig_lib_directory = zig_lib_directory,
            .local_cache_directory = local_cache_directory,
            .global_cache_directory = global_cache_directory,
            .root_name = "build",
            .target = target_info.target,
            .is_native_os = cross_target.isNativeOs(),
            .is_native_abi = cross_target.isNativeAbi(),
            .dynamic_linker = target_info.dynamic_linker.get(),
            .output_mode = .Exe,
            .root_pkg = &root_pkg,
            .emit_bin = emit_bin,
            .emit_h = null,
            .optimize_mode = .Debug,
            .self_exe_path = self_exe_path,
            .thread_pool = &thread_pool,
        }) catch |err| {
            fatal("unable to create compilation: {s}", .{@errorName(err)});
        };
        defer comp.destroy();

        updateModule(gpa, comp, .none) catch |err| switch (err) {
            error.SemanticAnalyzeFail => process.exit(1),
            else => |e| return e,
        };
        try comp.makeBinFileExecutable();

        child_argv.items[argv_index_exe] = try comp.bin_file.options.emit.?.directory.join(
            arena,
            &[_][]const u8{exe_basename},
        );

        break :argv child_argv.items;
    };
    const child = try std.ChildProcess.init(child_argv, gpa);
    defer child.deinit();

    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| {
            if (code == 0) return cleanExit();
            const cmd = try argvCmd(arena, child_argv);
            fatal("the following build command failed with exit code {d}:\n{s}", .{ code, cmd });
        },
        else => {
            const cmd = try argvCmd(arena, child_argv);
            fatal("the following build command crashed:\n{s}", .{cmd});
        },
    }
}

fn argvCmd(allocator: *Allocator, argv: []const []const u8) ![]u8 {
    var cmd = std.ArrayList(u8).init(allocator);
    defer cmd.deinit();
    for (argv[0 .. argv.len - 1]) |arg| {
        try cmd.appendSlice(arg);
        try cmd.append(' ');
    }
    try cmd.appendSlice(argv[argv.len - 1]);
    return cmd.toOwnedSlice();
}

fn readSourceFileToEndAlloc(allocator: *mem.Allocator, input: *const fs.File, size_hint: ?usize) ![]const u8 {
    const source_code = input.readToEndAllocOptions(
        allocator,
        max_src_size,
        size_hint,
        @alignOf(u16),
        null,
    ) catch |err| switch (err) {
        error.ConnectionResetByPeer => unreachable,
        error.ConnectionTimedOut => unreachable,
        error.NotOpenForReading => unreachable,
        else => |e| return e,
    };
    errdefer allocator.free(source_code);

    // Detect unsupported file types with their Byte Order Mark
    const unsupported_boms = [_][]const u8{
        "\xff\xfe\x00\x00", // UTF-32 little endian
        "\xfe\xff\x00\x00", // UTF-32 big endian
        "\xfe\xff", // UTF-16 big endian
    };
    for (unsupported_boms) |bom| {
        if (mem.startsWith(u8, source_code, bom)) {
            return error.UnsupportedEncoding;
        }
    }

    // If the file starts with a UTF-16 little endian BOM, translate it to UTF-8
    if (mem.startsWith(u8, source_code, "\xff\xfe")) {
        const source_code_utf16_le = mem.bytesAsSlice(u16, source_code);
        const source_code_utf8 = std.unicode.utf16leToUtf8Alloc(allocator, source_code_utf16_le) catch |err| switch (err) {
            error.DanglingSurrogateHalf => error.UnsupportedEncoding,
            error.ExpectedSecondSurrogateHalf => error.UnsupportedEncoding,
            error.UnexpectedSecondSurrogateHalf => error.UnsupportedEncoding,
            else => |e| return e,
        };

        allocator.free(source_code);
        return source_code_utf8;
    }

    return source_code;
}

pub const usage_fmt =
    \\Usage: zig fmt [file]...
    \\
    \\   Formats the input files and modifies them in-place.
    \\   Arguments can be files or directories, which are searched
    \\   recursively.
    \\
    \\Options:
    \\   -h, --help             Print this help and exit
    \\   --color [auto|off|on]  Enable or disable colored error messages
    \\   --stdin                Format code from stdin; output to stdout
    \\   --check                List non-conforming files and exit with an error
    \\                          if the list is non-empty
    \\
    \\
;

const Fmt = struct {
    seen: SeenMap,
    any_error: bool,
    color: Color,
    gpa: *Allocator,
    out_buffer: std.ArrayList(u8),

    const SeenMap = std.AutoHashMap(fs.File.INode, void);
};

pub fn cmdFmt(gpa: *Allocator, args: []const []const u8) !void {
    const stderr_file = io.getStdErr();
    var color: Color = .auto;
    var stdin_flag: bool = false;
    var check_flag: bool = false;
    var input_files = ArrayList([]const u8).init(gpa);
    defer input_files.deinit();

    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    const stdout = io.getStdOut().writer();
                    try stdout.writeAll(usage_fmt);
                    return cleanExit();
                } else if (mem.eql(u8, arg, "--color")) {
                    if (i + 1 >= args.len) {
                        fatal("expected [auto|on|off] after --color", .{});
                    }
                    i += 1;
                    const next_arg = args[i];
                    color = std.meta.stringToEnum(Color, next_arg) orelse {
                        fatal("expected [auto|on|off] after --color, found '{s}'", .{next_arg});
                    };
                } else if (mem.eql(u8, arg, "--stdin")) {
                    stdin_flag = true;
                } else if (mem.eql(u8, arg, "--check")) {
                    check_flag = true;
                } else {
                    fatal("unrecognized parameter: '{s}'", .{arg});
                }
            } else {
                try input_files.append(arg);
            }
        }
    }

    if (stdin_flag) {
        if (input_files.items.len != 0) {
            fatal("cannot use --stdin with positional arguments", .{});
        }

        const stdin = io.getStdIn();
        const source_code = readSourceFileToEndAlloc(gpa, &stdin, null) catch |err| {
            fatal("unable to read stdin: {s}", .{err});
        };
        defer gpa.free(source_code);

        var tree = std.zig.parse(gpa, source_code) catch |err| {
            fatal("error parsing stdin: {s}", .{err});
        };
        defer tree.deinit(gpa);

        for (tree.errors) |parse_error| {
            try printErrMsgToFile(gpa, parse_error, tree, "<stdin>", stderr_file, color);
        }
        if (tree.errors.len != 0) {
            process.exit(1);
        }
        const formatted = try tree.render(gpa);
        defer gpa.free(formatted);

        if (check_flag) {
            const code: u8 = @boolToInt(mem.eql(u8, formatted, source_code));
            process.exit(code);
        }

        return io.getStdOut().writeAll(formatted);
    }

    if (input_files.items.len == 0) {
        fatal("expected at least one source file argument", .{});
    }

    var fmt = Fmt{
        .gpa = gpa,
        .seen = Fmt.SeenMap.init(gpa),
        .any_error = false,
        .color = color,
        .out_buffer = std.ArrayList(u8).init(gpa),
    };
    defer fmt.seen.deinit();
    defer fmt.out_buffer.deinit();

    for (input_files.items) |file_path| {
        // Get the real path here to avoid Windows failing on relative file paths with . or .. in them.
        const real_path = fs.realpathAlloc(gpa, file_path) catch |err| {
            fatal("unable to open '{s}': {s}", .{ file_path, @errorName(err) });
        };
        defer gpa.free(real_path);

        try fmtPath(&fmt, file_path, check_flag, fs.cwd(), real_path);
    }
    if (fmt.any_error) {
        process.exit(1);
    }
}

const FmtError = error{
    SystemResources,
    OperationAborted,
    IoPending,
    BrokenPipe,
    Unexpected,
    WouldBlock,
    FileClosed,
    DestinationAddressRequired,
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    AccessDenied,
    OutOfMemory,
    RenameAcrossMountPoints,
    ReadOnlyFileSystem,
    LinkQuotaExceeded,
    FileBusy,
    EndOfStream,
    Unseekable,
    NotOpenForWriting,
    UnsupportedEncoding,
    ConnectionResetByPeer,
} || fs.File.OpenError;

fn fmtPath(fmt: *Fmt, file_path: []const u8, check_mode: bool, dir: fs.Dir, sub_path: []const u8) FmtError!void {
    fmtPathFile(fmt, file_path, check_mode, dir, sub_path) catch |err| switch (err) {
        error.IsDir, error.AccessDenied => return fmtPathDir(fmt, file_path, check_mode, dir, sub_path),
        else => {
            warn("unable to format '{s}': {s}", .{ file_path, @errorName(err) });
            fmt.any_error = true;
            return;
        },
    };
}

fn fmtPathDir(
    fmt: *Fmt,
    file_path: []const u8,
    check_mode: bool,
    parent_dir: fs.Dir,
    parent_sub_path: []const u8,
) FmtError!void {
    var dir = try parent_dir.openDir(parent_sub_path, .{ .iterate = true });
    defer dir.close();

    const stat = try dir.stat();
    if (try fmt.seen.fetchPut(stat.inode, {})) |_| return;

    var dir_it = dir.iterate();
    while (try dir_it.next()) |entry| {
        const is_dir = entry.kind == .Directory;

        if (is_dir and std.mem.eql(u8, entry.name, "zig-cache")) continue;

        if (is_dir or mem.endsWith(u8, entry.name, ".zig")) {
            const full_path = try fs.path.join(fmt.gpa, &[_][]const u8{ file_path, entry.name });
            defer fmt.gpa.free(full_path);

            if (is_dir) {
                try fmtPathDir(fmt, full_path, check_mode, dir, entry.name);
            } else {
                fmtPathFile(fmt, full_path, check_mode, dir, entry.name) catch |err| {
                    warn("unable to format '{s}': {s}", .{ full_path, @errorName(err) });
                    fmt.any_error = true;
                    return;
                };
            }
        }
    }
}

fn fmtPathFile(
    fmt: *Fmt,
    file_path: []const u8,
    check_mode: bool,
    dir: fs.Dir,
    sub_path: []const u8,
) FmtError!void {
    const source_file = try dir.openFile(sub_path, .{});
    var file_closed = false;
    errdefer if (!file_closed) source_file.close();

    const stat = try source_file.stat();

    if (stat.kind == .Directory)
        return error.IsDir;

    const source_code = try readSourceFileToEndAlloc(
        fmt.gpa,
        &source_file,
        std.math.cast(usize, stat.size) catch return error.FileTooBig,
    );
    defer fmt.gpa.free(source_code);

    source_file.close();
    file_closed = true;

    // Add to set after no longer possible to get error.IsDir.
    if (try fmt.seen.fetchPut(stat.inode, {})) |_| return;

    var tree = try std.zig.parse(fmt.gpa, source_code);
    defer tree.deinit(fmt.gpa);

    for (tree.errors) |parse_error| {
        try printErrMsgToFile(fmt.gpa, parse_error, tree, file_path, std.io.getStdErr(), fmt.color);
    }
    if (tree.errors.len != 0) {
        fmt.any_error = true;
        return;
    }

    // As a heuristic, we make enough capacity for the same as the input source.
    fmt.out_buffer.shrinkRetainingCapacity(0);
    try fmt.out_buffer.ensureCapacity(source_code.len);

    try tree.renderToArrayList(&fmt.out_buffer);
    if (mem.eql(u8, fmt.out_buffer.items, source_code))
        return;

    if (check_mode) {
        const stdout = io.getStdOut().writer();
        try stdout.print("{s}\n", .{file_path});
        fmt.any_error = true;
    } else {
        var af = try dir.atomicFile(sub_path, .{ .mode = stat.mode });
        defer af.deinit();

        try af.file.writeAll(fmt.out_buffer.items);
        try af.finish();
        const stdout = io.getStdOut().writer();
        try stdout.print("{s}\n", .{file_path});
    }
}

fn printErrMsgToFile(
    gpa: *mem.Allocator,
    parse_error: ast.Error,
    tree: ast.Tree,
    path: []const u8,
    file: fs.File,
    color: Color,
) !void {
    const color_on = switch (color) {
        .auto => file.isTty(),
        .on => true,
        .off => false,
    };
    const lok_token = parse_error.token;

    const token_starts = tree.tokens.items(.start);
    const token_tags = tree.tokens.items(.tag);
    const first_token_start = token_starts[lok_token];
    const start_loc = tree.tokenLocation(0, lok_token);

    var text_buf = std.ArrayList(u8).init(gpa);
    defer text_buf.deinit();
    const writer = text_buf.writer();
    try tree.renderError(parse_error, writer);
    const text = text_buf.items;

    const stream = file.writer();
    try stream.print("{s}:{d}:{d}: error: {s}\n", .{ path, start_loc.line + 1, start_loc.column + 1, text });

    if (!color_on) return;

    // Print \r and \t as one space each so that column counts line up
    for (tree.source[start_loc.line_start..start_loc.line_end]) |byte| {
        try stream.writeByte(switch (byte) {
            '\r', '\t' => ' ',
            else => byte,
        });
    }
    try stream.writeByte('\n');
    try stream.writeByteNTimes(' ', start_loc.column);
    if (token_tags[lok_token].lexeme()) |lexeme| {
        try stream.writeByteNTimes('~', lexeme.len);
        try stream.writeByte('\n');
    } else {
        try stream.writeAll("^\n");
    }
}

pub const info_zen =
    \\
    \\ * Communicate intent precisely.
    \\ * Edge cases matter.
    \\ * Favor reading code over writing code.
    \\ * Only one obvious way to do things.
    \\ * Runtime crashes are better than bugs.
    \\ * Compile errors are better than runtime crashes.
    \\ * Incremental improvements.
    \\ * Avoid local maximums.
    \\ * Reduce the amount one must remember.
    \\ * Focus on code rather than style.
    \\ * Resource allocation may fail; resource deallocation must succeed.
    \\ * Memory is a resource.
    \\ * Together we serve the users.
    \\
    \\
;

extern "c" fn ZigClang_main(argc: c_int, argv: [*:null]?[*:0]u8) c_int;

/// TODO https://github.com/ziglang/zig/issues/3257
fn punt_to_clang(arena: *Allocator, args: []const []const u8) error{OutOfMemory} {
    if (!build_options.have_llvm)
        fatal("`zig cc` and `zig c++` unavailable: compiler built without LLVM extensions", .{});
    // Convert the args to the format Clang expects.
    const argv = try arena.alloc(?[*:0]u8, args.len + 1);
    for (args) |arg, i| {
        argv[i] = try arena.dupeZ(u8, arg); // TODO If there was an argsAllocZ we could avoid this allocation.
    }
    argv[args.len] = null;
    const exit_code = ZigClang_main(@intCast(c_int, args.len), argv[0..args.len :null].ptr);
    process.exit(@bitCast(u8, @truncate(i8, exit_code)));
}

/// The first argument determines which backend is invoked. The options are:
/// * `ld.lld` - ELF
/// * `ld64.lld` - Mach-O
/// * `lld-link` - COFF
/// * `wasm-ld` - WebAssembly
/// TODO https://github.com/ziglang/zig/issues/3257
pub fn punt_to_lld(arena: *Allocator, args: []const []const u8) error{OutOfMemory} {
    if (!build_options.have_llvm)
        fatal("`zig {s}` unavailable: compiler built without LLVM extensions", .{args[0]});
    // Convert the args to the format LLD expects.
    // We subtract 1 to shave off the zig binary from args[0].
    const argv = try arena.allocSentinel(?[*:0]const u8, args.len - 1, null);
    for (args[1..]) |arg, i| {
        argv[i] = try arena.dupeZ(u8, arg); // TODO If there was an argsAllocZ we could avoid this allocation.
    }
    const exit_code = rc: {
        const llvm = @import("codegen/llvm/bindings.zig");
        const argc = @intCast(c_int, argv.len);
        if (mem.eql(u8, args[1], "ld.lld")) {
            break :rc llvm.LinkELF(argc, argv.ptr, true);
        } else if (mem.eql(u8, args[1], "ld64.lld")) {
            break :rc llvm.LinkMachO(argc, argv.ptr, true);
        } else if (mem.eql(u8, args[1], "lld-link")) {
            break :rc llvm.LinkCOFF(argc, argv.ptr, true);
        } else if (mem.eql(u8, args[1], "wasm-ld")) {
            break :rc llvm.LinkWasm(argc, argv.ptr, true);
        } else {
            unreachable;
        }
    };
    process.exit(@bitCast(u8, @truncate(i8, exit_code)));
}

const clang_args = @import("clang_options.zig").list;

pub const ClangArgIterator = struct {
    has_next: bool,
    zig_equivalent: ZigEquivalent,
    only_arg: []const u8,
    second_arg: []const u8,
    other_args: []const []const u8,
    argv: []const []const u8,
    next_index: usize,
    root_args: ?*Args,
    allocator: *Allocator,

    pub const ZigEquivalent = enum {
        target,
        o,
        c,
        other,
        positional,
        l,
        ignore,
        driver_punt,
        pic,
        no_pic,
        pie,
        no_pie,
        lto,
        no_lto,
        nostdlib,
        nostdlib_cpp,
        shared,
        rdynamic,
        wl,
        preprocess_only,
        asm_only,
        optimize,
        debug,
        sanitize,
        linker_script,
        dry_run,
        verbose,
        for_linker,
        linker_input_z,
        lib_dir,
        mcpu,
        dep_file,
        dep_file_mm,
        framework_dir,
        framework,
        nostdlibinc,
        red_zone,
        no_red_zone,
        strip,
    };

    const Args = struct {
        next_index: usize,
        argv: []const []const u8,
    };

    fn init(allocator: *Allocator, argv: []const []const u8) ClangArgIterator {
        return .{
            .next_index = 2, // `zig cc foo` this points to `foo`
            .has_next = argv.len > 2,
            .zig_equivalent = undefined,
            .only_arg = undefined,
            .second_arg = undefined,
            .other_args = undefined,
            .argv = argv,
            .root_args = null,
            .allocator = allocator,
        };
    }

    fn next(self: *ClangArgIterator) !void {
        assert(self.has_next);
        assert(self.next_index < self.argv.len);
        // In this state we know that the parameter we are looking at is a root parameter
        // rather than an argument to a parameter.
        // We adjust the len below when necessary.
        self.other_args = (self.argv.ptr + self.next_index)[0..1];
        var arg = mem.span(self.argv[self.next_index]);
        self.incrementArgIndex();

        if (mem.startsWith(u8, arg, "@")) {
            if (self.root_args != null) return error.NestedResponseFile;

            // This is a "compiler response file". We must parse the file and treat its
            // contents as command line parameters.
            const allocator = self.allocator;
            const max_bytes = 10 * 1024 * 1024; // 10 MiB of command line arguments is a reasonable limit
            const resp_file_path = arg[1..];
            const resp_contents = fs.cwd().readFileAlloc(allocator, resp_file_path, max_bytes) catch |err| {
                fatal("unable to read response file '{s}': {s}", .{ resp_file_path, @errorName(err) });
            };
            defer allocator.free(resp_contents);
            // TODO is there a specification for this file format? Let's find it and make this parsing more robust
            // at the very least I'm guessing this needs to handle quotes and `#` comments.
            var it = mem.tokenize(resp_contents, " \t\r\n");
            var resp_arg_list = std.ArrayList([]const u8).init(allocator);
            defer resp_arg_list.deinit();
            {
                errdefer {
                    for (resp_arg_list.items) |item| {
                        allocator.free(mem.span(item));
                    }
                }
                while (it.next()) |token| {
                    const dupe_token = try mem.dupeZ(allocator, u8, token);
                    errdefer allocator.free(dupe_token);
                    try resp_arg_list.append(dupe_token);
                }
                const args = try allocator.create(Args);
                errdefer allocator.destroy(args);
                args.* = .{
                    .next_index = self.next_index,
                    .argv = self.argv,
                };
                self.root_args = args;
            }
            const resp_arg_slice = resp_arg_list.toOwnedSlice();
            self.next_index = 0;
            self.argv = resp_arg_slice;

            if (resp_arg_slice.len == 0) {
                self.resolveRespFileArgs();
                return;
            }

            self.has_next = true;
            self.other_args = (self.argv.ptr + self.next_index)[0..1]; // We adjust len below when necessary.
            arg = mem.span(self.argv[self.next_index]);
            self.incrementArgIndex();
        }
        if (mem.eql(u8, arg, "-") or !mem.startsWith(u8, arg, "-")) {
            self.zig_equivalent = .positional;
            self.only_arg = arg;
            return;
        }

        find_clang_arg: for (clang_args) |clang_arg| switch (clang_arg.syntax) {
            .flag => {
                const prefix_len = clang_arg.matchEql(arg);
                if (prefix_len > 0) {
                    self.zig_equivalent = clang_arg.zig_equivalent;
                    self.only_arg = arg[prefix_len..];

                    break :find_clang_arg;
                }
            },
            .joined, .comma_joined => {
                // joined example: --target=foo
                // comma_joined example: -Wl,-soname,libsoundio.so.2
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    self.zig_equivalent = clang_arg.zig_equivalent;
                    self.only_arg = arg[prefix_len..]; // This will skip over the "--target=" part.

                    break :find_clang_arg;
                }
            },
            .joined_or_separate => {
                // Examples: `-lfoo`, `-l foo`
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len == arg.len) {
                    if (self.next_index >= self.argv.len) {
                        fatal("Expected parameter after '{s}'", .{arg});
                    }
                    self.only_arg = self.argv[self.next_index];
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                    self.zig_equivalent = clang_arg.zig_equivalent;

                    break :find_clang_arg;
                } else if (prefix_len != 0) {
                    self.zig_equivalent = clang_arg.zig_equivalent;
                    self.only_arg = arg[prefix_len..];

                    break :find_clang_arg;
                }
            },
            .joined_and_separate => {
                // Example: `-Xopenmp-target=riscv64-linux-unknown foo`
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    self.only_arg = arg[prefix_len..];
                    if (self.next_index >= self.argv.len) {
                        fatal("Expected parameter after '{s}'", .{arg});
                    }
                    self.second_arg = self.argv[self.next_index];
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                    self.zig_equivalent = clang_arg.zig_equivalent;
                    break :find_clang_arg;
                }
            },
            .separate => if (clang_arg.matchEql(arg) > 0) {
                if (self.next_index >= self.argv.len) {
                    fatal("Expected parameter after '{s}'", .{arg});
                }
                self.only_arg = self.argv[self.next_index];
                self.incrementArgIndex();
                self.other_args.len += 1;
                self.zig_equivalent = clang_arg.zig_equivalent;
                break :find_clang_arg;
            },
            .remaining_args_joined => {
                const prefix_len = clang_arg.matchStartsWith(arg);
                if (prefix_len != 0) {
                    @panic("TODO");
                }
            },
            .multi_arg => |num_args| if (clang_arg.matchEql(arg) > 0) {
                // Example `-sectcreate <arg1> <arg2> <arg3>`.
                var i: usize = 0;
                while (i < num_args) : (i += 1) {
                    self.incrementArgIndex();
                    self.other_args.len += 1;
                }
                self.zig_equivalent = clang_arg.zig_equivalent;
                break :find_clang_arg;
            },
        } else {
            fatal("Unknown Clang option: '{s}'", .{arg});
        }
    }

    fn incrementArgIndex(self: *ClangArgIterator) void {
        self.next_index += 1;
        self.resolveRespFileArgs();
    }

    fn resolveRespFileArgs(self: *ClangArgIterator) void {
        const allocator = self.allocator;
        if (self.next_index >= self.argv.len) {
            if (self.root_args) |root_args| {
                self.next_index = root_args.next_index;
                self.argv = root_args.argv;

                allocator.destroy(root_args);
                self.root_args = null;
            }
            if (self.next_index >= self.argv.len) {
                self.has_next = false;
            }
        }
    }
};

fn parseCodeModel(arg: []const u8) std.builtin.CodeModel {
    return std.meta.stringToEnum(std.builtin.CodeModel, arg) orelse
        fatal("unsupported machine code model: '{s}'", .{arg});
}

/// Raise the open file descriptor limit. Ask and ye shall receive.
/// For one example of why this is handy, consider the case of building musl libc.
/// We keep a lock open for each of the object files in the form of a file descriptor
/// until they are finally put into an archive file. This is to allow a zig-cache
/// garbage collector to run concurrently to zig processes, and to allow multiple
/// zig processes to run concurrently with each other, without clobbering each other.
fn gimmeMoreOfThoseSweetSweetFileDescriptors() void {
    if (!@hasDecl(std.os, "rlimit")) return;
    const posix = std.os;

    var lim = posix.getrlimit(.NOFILE) catch return; // Oh well; we tried.
    if (comptime std.Target.current.isDarwin()) {
        // On Darwin, `NOFILE` is bounded by a hardcoded value `OPEN_MAX`.
        // According to the man pages for setrlimit():
        //   setrlimit() now returns with errno set to EINVAL in places that historically succeeded.
        //   It no longer accepts "rlim_cur = RLIM_INFINITY" for RLIM_NOFILE.
        //   Use "rlim_cur = min(OPEN_MAX, rlim_max)".
        lim.max = std.math.min(std.os.darwin.OPEN_MAX, lim.max);
    }
    if (lim.cur == lim.max) return;

    // Do a binary search for the limit.
    var min: posix.rlim_t = lim.cur;
    var max: posix.rlim_t = 1 << 20;
    // But if there's a defined upper bound, don't search, just set it.
    if (lim.max != posix.RLIM_INFINITY) {
        min = lim.max;
        max = lim.max;
    }

    while (true) {
        lim.cur = min + @divTrunc(max - min, 2); // on freebsd rlim_t is signed
        if (posix.setrlimit(.NOFILE, lim)) |_| {
            min = lim.cur;
        } else |_| {
            max = lim.cur;
        }
        if (min + 1 >= max) break;
    }
}

test "fds" {
    gimmeMoreOfThoseSweetSweetFileDescriptors();
}

fn detectNativeCpuWithLLVM(
    arch: std.Target.Cpu.Arch,
    llvm_cpu_name_z: ?[*:0]const u8,
    llvm_cpu_features_opt: ?[*:0]const u8,
) !std.Target.Cpu {
    var result = std.Target.Cpu.baseline(arch);

    if (llvm_cpu_name_z) |cpu_name_z| {
        const llvm_cpu_name = mem.spanZ(cpu_name_z);

        for (arch.allCpuModels()) |model| {
            const this_llvm_name = model.llvm_name orelse continue;
            if (mem.eql(u8, this_llvm_name, llvm_cpu_name)) {
                // Here we use the non-dependencies-populated set,
                // so that subtracting features later in this function
                // affect the prepopulated set.
                result = std.Target.Cpu{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
                break;
            }
        }
    }

    const all_features = arch.allFeaturesList();

    if (llvm_cpu_features_opt) |llvm_cpu_features| {
        var it = mem.tokenize(mem.spanZ(llvm_cpu_features), ",");
        while (it.next()) |decorated_llvm_feat| {
            var op: enum {
                add,
                sub,
            } = undefined;
            var llvm_feat: []const u8 = undefined;
            if (mem.startsWith(u8, decorated_llvm_feat, "+")) {
                op = .add;
                llvm_feat = decorated_llvm_feat[1..];
            } else if (mem.startsWith(u8, decorated_llvm_feat, "-")) {
                op = .sub;
                llvm_feat = decorated_llvm_feat[1..];
            } else {
                return error.InvalidLlvmCpuFeaturesFormat;
            }
            for (all_features) |feature, index_usize| {
                const this_llvm_name = feature.llvm_name orelse continue;
                if (mem.eql(u8, llvm_feat, this_llvm_name)) {
                    const index = @intCast(std.Target.Cpu.Feature.Set.Index, index_usize);
                    switch (op) {
                        .add => result.features.addFeature(index),
                        .sub => result.features.removeFeature(index),
                    }
                    break;
                }
            }
        }
    }

    result.features.populateDependencies(all_features);
    return result;
}

fn detectNativeTargetInfo(gpa: *Allocator, cross_target: std.zig.CrossTarget) !std.zig.system.NativeTargetInfo {
    var info = try std.zig.system.NativeTargetInfo.detect(gpa, cross_target);
    if (info.cpu_detection_unimplemented) {
        const arch = std.Target.current.cpu.arch;

        // We want to just use detected_info.target but implementing
        // CPU model & feature detection is todo so here we rely on LLVM.
        // https://github.com/ziglang/zig/issues/4591
        if (!build_options.have_llvm)
            fatal("CPU features detection is not yet available for {s} without LLVM extensions", .{@tagName(arch)});

        const llvm = @import("codegen/llvm/bindings.zig");
        const llvm_cpu_name = llvm.GetHostCPUName();
        const llvm_cpu_features = llvm.GetNativeFeatures();
        info.target.cpu = try detectNativeCpuWithLLVM(arch, llvm_cpu_name, llvm_cpu_features);
        cross_target.updateCpuFeatures(&info.target.cpu.features);
        info.target.cpu.arch = cross_target.getCpuArch();
    }
    return info;
}

/// Indicate that we are now terminating with a successful exit code.
/// In debug builds, this is a no-op, so that the calling code's
/// cleanup mechanisms are tested and so that external tools that
/// check for resource leaks can be accurate. In release builds, this
/// calls exit(0), and does not return.
pub fn cleanExit() void {
    if (std.builtin.mode == .Debug) {
        return;
    } else {
        process.exit(0);
    }
}
