#!/usr/bin/bash
# Minimal `cc` driver shim that forwards to /usr/bin/wild.
#
# rustc's default linker invocation is `cc <objs> -Wl,<linker-flag> ...`.
# wild is a raw linker, not a cc driver, so the `-Wl,...` passthroughs
# explode if rustc invokes wild directly. This shim sits at /usr/bin/cc,
# strips the `-Wl,` prefix and splits on commas (so `-Wl,--as-needed`
# becomes `--as-needed`, and `-Wl,-z,now` becomes `-z now`), and execs
# wild with the rewritten args.
#
# NOT a real cc. Anything that needs to compile C will fail; the only
# job here is to act as a linker-driver wrapper around wild so rustc's
# link step works without shipping gcc.

set -e

# gcc-driver-only flags that wild does not understand. They tell the
# driver how to *find* libs / startup files; wild gets the linker line
# directly, so the flags are meaningless and must be dropped.
drop_re='^(-nodefaultlibs|-nostartfiles|-nostdlib|-pthread|-fpic|-fPIC|-fPIE|-fpie)$'

# Detect the multiarch triple so we can pre-seed wild's search path
# with /usr/lib/<triple> and the gcc-14 dir. Real cc drivers know
# these implicitly; wild does not. Bash sets $HOSTTYPE without
# needing /usr/bin/uname (which is not in this rock).
case "$HOSTTYPE" in
    x86_64)
        TRIPLE=x86_64-linux-gnu
        INTERP=/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
        ;;
    aarch64)
        TRIPLE=aarch64-linux-gnu
        INTERP=/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
        ;;
    *) echo "cc_wild_shim: unsupported HOSTTYPE '$HOSTTYPE'" >&2; exit 1 ;;
esac

# Sniff the args to pick the right linking mode:
#   -shared : building a .so; no main / no INTERP / no Scrt1.o.
#   -pie    : PIE executable; use S-variants of the crt files.
#   else    : plain dynamic executable.
# Static (-static-pie / -static) is not handled yet.
is_shared=0
is_pie=0
for a in "$@"; do
    case "$a" in
        -shared) is_shared=1 ;;
        -pie)    is_pie=1 ;;
    esac
done

libdir="/usr/lib/${TRIPLE}"
gccdir="/usr/lib/gcc/${TRIPLE}/14"
if (( is_shared )); then
    # crtbeginS / crtendS provide PIC-safe ctor/dtor stubs that .so
    # objects need; the entry-point crt (Scrt1/crt1) is skipped.
    crt_pre=("$gccdir/crtbeginS.o")
    crt_post=("$gccdir/crtendS.o")
elif (( is_pie )); then
    crt_pre=("$libdir/Scrt1.o" "$libdir/crti.o" "$gccdir/crtbeginS.o")
    crt_post=("$gccdir/crtendS.o" "$libdir/crtn.o")
else
    crt_pre=("$libdir/crt1.o" "$libdir/crti.o" "$gccdir/crtbegin.o")
    crt_post=("$gccdir/crtend.o" "$libdir/crtn.o")
fi

# Wild args, in this order:
#   -L paths   (search dirs cc would add implicitly)
#   crt_pre    (entry / init prolog / ctor begin)
#   <user args, gcc-driver flags translated>
#   crt_post   (ctor end / init epilog)
mid=()
for a in "$@"; do
    if [[ $a =~ $drop_re ]]; then
        continue
    fi
    if [[ $a == -Wl,* ]]; then
        rest=${a#-Wl,}
        IFS=',' read -ra parts <<< "$rest"
        mid+=("${parts[@]}")
    else
        mid+=("$a")
    fi
done

out=(
    "-L" "$libdir"
    "-L" "$gccdir"
    "${crt_pre[@]}"
    "${mid[@]}"
    "${crt_post[@]}"
)
# Shared objects don't get a PT_INTERP; executables do.
if (( ! is_shared )); then
    out=("-dynamic-linker" "$INTERP" "${out[@]}")
fi

# DEBUG: log args + copy linked output to /cargo/wild-debug/ for
# post-mortem inspection from the host.
dbg_dir=/cargo/wild-debug
mkdir -p "$dbg_dir" 2>/dev/null || true
{
    echo "=== $(date) ==="
    echo "raw args: $*"
    echo "wild args: ${out[*]}"
} >> "$dbg_dir/log.txt" 2>/dev/null || true

# Find the -o <output> path so we can copy the result.
output=
prev=
for a in "${out[@]}"; do
    if [[ $prev == -o ]]; then output=$a; break; fi
    prev=$a
done

/usr/bin/wild "${out[@]}"
rc=$?

if [[ $rc -eq 0 && -n $output && -f $output ]]; then
    cp "$output" "$dbg_dir/last-output.bin" 2>/dev/null || true
fi
exit "$rc"
