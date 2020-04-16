# bootstrap-zig

The purpose of this project is to start with minimum system dependencies and
end with a fully operational Zig compiler for any target.

## Version Information

This repository copies sources from upstream, with no patches.

 * LLVM 10
 * Clang 10
 * Zig 0.6.0

## Host System Dependencies

 * C++ compiler capable of building LLVM, Clang, and LLD from source
 * cmake 3.4.3 or later
 * make
 * POSIX system (sh, echo, cut, tr)

## Build Instructions

```
build -j1 <arch>-<os>-<abi> baseline
```

All parameters are required:

 * `-j1`: Replace with your jobs parameter to make.
 * `<arch>-<os>-<abi>`: Replace with one of the Supported Triples below, or use
   `native` for the `<arch>` value (e.g. `native-linux-gnu`) to use the native
    architecture.
 * `baseline`: Replace with a `-mcpu` parameter of Zig. `baseline` means
   it will target a generic CPU for the target. `native` means it will target
   the native CPU. See the Zig documentation for more details.

If it succeeds, the output will be in `out/zig-triple-mcpu/`.

### Supported Triples

If you try a "not tested" one and find a problem please file an issue,
and a pull request linking to the issue in the table.

If you try a "not tested" one and find that it works, please file a pull request
changing the status to "OK".

If you try an "OK" one and it does not work, please check if there is an existing
issue, and if not, file an issue.

Note: Generally, for Linux targets, we prefer the musl libc builds over the
glibc builds here, because musl builds end up producing a static binary, which
is more portable across Linux distributions.

| triple                     | support status |
|----------------------------|----------------|
| `aarch64_be-linux-gnu`     | not tested     |
| `aarch64_be-linux-musl`    | not tested     |
| `aarch64_be-windows-gnu`   | not tested     |
| `aarch64-linux-gnu`        | not tested     |
| `aarch64-linux-musl`       | OK             |
| `aarch64-windows-gnu`      | not tested     |
| `armeb-linux-gnueabi`      | not tested     |
| `armeb-linux-gnueabihf`    | not tested     |
| `armeb-linux-musleabi`     | not tested     |
| `armeb-linux-musleabihf`   | not tested     |
| `armeb-windows-gnu`        | not tested     |
| `arm-linux-gnueabi`        | not tested     |
| `arm-linux-gnueabihf`      | not tested     |
| `arm-linux-musleabi`       | OK             |
| `arm-linux-musleabihf`     | OK             |
| `arm-windows-gnu`          | not tested     |
| `i386-linux-gnu`           | not tested     |
| `i386-linux-musl`          | OK             |
| `i386-windows-gnu`         | OK             |
| `mips64el-linux-gnuabi64`  | not tested     |
| `mips64el-linux-gnuabin32` | not tested     |
| `mips64el-linux-musl`      | [#3](https://github.com/ziglang/bootstrap/issues/3) |
| `mips64-linux-gnuabi64`    | not tested     |
| `mips64-linux-gnuabin32`   | not tested     |
| `mips64-linux-musl`        | not tested     |
| `mipsel-linux-gnu`         | not tested     |
| `mipsel-linux-musl`        | [#12](https://github.com/ziglang/bootstrap/issues/12) |
| `mips-linux-gnu`           | not tested     |
| `mips-linux-musl`          | not tested     |
| `powerpc64le-linux-gnu`    | [#24](https://github.com/ziglang/zig-bootstrap/issues/24) |
| `powerpc64le-linux-musl`   | [#5](https://github.com/ziglang/bootstrap/issues/5) |
| `powerpc64-linux-gnu`      | not tested     |
| `powerpc64-linux-musl`     | not tested     |
| `powerpc-linux-gnu`        | not tested     |
| `powerpc-linux-musl`       | not tested     |
| `riscv64-linux-gnu`        | not tested     |
| `riscv64-linux-musl`       | [#4](https://github.com/ziglang/bootstrap/issues/4) |
| `s390x-linux-gnu`          | not tested     |
| `s390x-linux-musl`         | not tested     |
| `sparc-linux-gnu`          | not tested     |
| `sparcv9-linux-gnu`        | [ziglang/zig#4931](https://github.com/ziglang/zig/issues/4931) |
| `x86_64-linux-gnu`         | OK             |
| `x86_64-linux-gnux32`      | [#20](https://github.com/ziglang/bootstrap/issues/20) |
| `x86_64-linux-musl`        | OK             |
| `x86_64-windows-gnu`       | OK             |

#### Other Notable Targets Known to Work

 * `arm-linux-musleabi` with mcpu value of `generic+v6kz`. This produces a
   build of Zig that runs on the RPi 1 and RPi Zero.
   - If you want to produce a build for this CPU exactly, use `arm1176jzf_s`.
