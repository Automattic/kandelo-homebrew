#!/usr/bin/env bash
set -euo pipefail

: "${KANDELO_STRICT_REAL_CC:?set KANDELO_STRICT_REAL_CC to the Kandelo C compiler}"

case "${0##*/}" in
    *++|*cxx*) real_compiler=${KANDELO_STRICT_REAL_CXX:-$KANDELO_STRICT_REAL_CC} ;;
    *) real_compiler=$KANDELO_STRICT_REAL_CC ;;
esac

"$real_compiler" "$@"

output=a.out
inspect=yes
next_is_output=no
for arg in "$@"; do
    if [ "$next_is_output" = yes ]; then
        output=$arg
        next_is_output=no
        continue
    fi

    case "$arg" in
        -c|-E|-S|-shared)
            inspect=no
            ;;
        -o)
            next_is_output=yes
            ;;
        -o?*)
            output=${arg#-o}
            ;;
    esac
done

[ "$inspect" = yes ] || exit 0
[ -f "$output" ] || exit 0
wasm-objdump -h "$output" >/dev/null 2>&1 || exit 0

unexpected_imports=$(
    wasm-objdump -x "$output" |
        awk '/<- env[.]/ { sub(/^.*<- env[.]/, ""); print $1 }' |
        grep -Ev '^(__channel_base|memory|__wasm_dlclose|__wasm_dlerror|__wasm_dlopen|__wasm_dlsym)$' || true
)

if [ -n "$unexpected_imports" ]; then
    echo "strict-wasm-link-cc: unresolved non-ABI imports in $output:" >&2
    echo "$unexpected_imports" >&2
    rm -f "$output"
    exit 1
fi
