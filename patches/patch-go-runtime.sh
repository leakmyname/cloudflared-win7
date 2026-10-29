#!/bin/bash
# Patch Go 1.21.13 runtime for Windows 7 compatibility.
#
# Go 1.21 uses bcryptprimitives.dll!ProcessPrng for random data,
# which is only available on Windows 10+. On Windows 7 the function
# pointer is nil, causing a crash at PC=0x0 in runtime.asmstdcall.
#
# This patch adds a fallback to advapi32.dll!SystemFunction036
# (aka RtlGenRandom), which is available on Windows 7.
#
# Usage:  bash patch-go-runtime.sh /path/to/go1.21.13
set -euo pipefail

GOROOT="${1:?usage: patch-go-runtime.sh /path/to/go-root}"
TARGET="$GOROOT/src/runtime/os_windows.go"

if [ ! -f "$TARGET" ]; then
    echo "error: $TARGET not found" >&2
    exit 1
fi

if grep -q '_RtlGenRandom' "$TARGET"; then
    echo "already patched"
    exit 0
fi

# 1. Add _RtlGenRandom variable declaration
sed -i '/^\t_ProcessPrng stdFunction$/a\
\t// Fallback for Windows 7 where ProcessPrng is unavailable.\
\t_RtlGenRandom stdFunction' "$TARGET"

# 2. Add fallback loading after ProcessPrng
python3 -c "
import re
with open('$TARGET', 'r') as f:
    c = f.read()
old = '\t_ProcessPrng = windowsFindfunc(bcryptPrimitives, []byte(\"ProcessPrng\x00\"))\n'
new = old + '''\tif _ProcessPrng == nil {
\t\t// Windows 7: ProcessPrng unavailable, fall back to RtlGenRandom (SystemFunction036) from advapi32.dll
\t\tadvapi32dll := [...]uint16{'a', 'd', 'v', 'a', 'p', 'i', '3', '2', '.', 'd', 'l', 'l', 0}
\t\tadvapi32 := windowsLoadSystemLib(advapi32dll[:])
\t\tif advapi32 == 0 {
\t\t\tthrow(\"advapi32.dll not found\")
\t\t}
\t\t_RtlGenRandom = windowsFindfunc(advapi32, []byte(\"SystemFunction036\x00\"))
\t\tif _RtlGenRandom == nil {
\t\t\tthrow(\"RtlGenRandom not found\")
\t\t}
\t}
'''
c = c.replace(old, new, 1)
with open('$TARGET', 'w') as f:
    f.write(c)
"

# 3. Patch getRandomData to use fallback
python3 -c "
with open('$TARGET', 'r') as f:
    c = f.read()
old = '''func getRandomData(r []byte) {
\tn := 0
\tif stdcall2(_ProcessPrng, uintptr(unsafe.Pointer(&r[0])), uintptr(len(r)))&0xff != 0 {
\t\tn = len(r)
\t}
\textendRandom(r, n)
}'''
new = '''func getRandomData(r []byte) {
\tn := 0
\tif _ProcessPrng != nil {
\t\tif stdcall2(_ProcessPrng, uintptr(unsafe.Pointer(&r[0])), uintptr(len(r)))&0xff != 0 {
\t\t\tn = len(r)
\t\t}
\t} else if _RtlGenRandom != nil {
\t\tif stdcall2(_RtlGenRandom, uintptr(unsafe.Pointer(&r[0])), uintptr(len(r)))&0xff != 0 {
\t\t\tn = len(r)
\t\t}
\t}
\textendRandom(r, n)
}'''
c = c.replace(old, new, 1)
with open('$TARGET', 'w') as f:
    f.write(c)
"

echo "patched $TARGET"
