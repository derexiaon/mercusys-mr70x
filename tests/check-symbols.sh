#!/bin/bash
# Check that every undefined dynamic symbol of every ELF in the rootfs is
# defined by some other ELF there. Guards CONFIG_USE_MKLIBS, which strips
# library functions nobody seemed to use (plugins such as ucode modules,
# pppd and rpcd plugins resolve symbols from the process that loads them).
# Usage: tests/check-symbols.sh <rootfs dir> <nm>
set -euo pipefail

R="$(realpath "${1:?rootfs dir}")"
NM="${2:?path to the target nm}"
cd "$R"

mapfile -t elfs < <(find bin sbin usr lib -type f -exec sh -c 'head -c4 "$1" | grep -q ELF && echo "$1"' _ {} \;)

defined="$(mktemp)"
trap 'rm -f "$defined"' EXIT

for f in "${elfs[@]}"; do
	"$NM" -D --defined-only "$f" 2>/dev/null | awk '{print $NF}' | sed 's/@.*//'
done | sort -u > "$defined"

missing=0
for f in "${elfs[@]}"; do
	while read -r s; do
		if ! grep -qx "$s" "$defined"; then
			echo "missing: $f: $s"
			missing=$((missing + 1))
		fi
	done < <("$NM" -D --undefined-only "$f" 2>/dev/null | awk '$1 == "U" {print $2}' | sed 's/@.*//')
done

echo "checked ${#elfs[@]} ELF files, $(wc -l < "$defined") exported symbols, missing: $missing"
[ "$missing" -eq 0 ]
