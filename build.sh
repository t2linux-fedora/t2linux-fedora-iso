#!/usr/bin/bash
set -e

kickstarts=( "fedora-atomic-silverblue" )

mkdir -p /repo/builddir/iso
builddir=$(mktemp -d -p "/repo/builddir"); export builddir
function cleanup {
  rm -rf "$builddir"
}
trap cleanup EXIT

for ks in "${kickstarts[@]}"; do
    ks_builddir="$builddir/$ks"; mkdir -p $ks_builddir; cd "$ks_builddir"
    sudo ksflatten --config "/repo/$ks.ks" --output "$ks-flat.ks" --version F41
    livemedia-creator \
        --make-iso \
        --iso-only \
        --no-virt \
        --resultdir results \
        --releasever 41 \
        --ks "$ks-flat.ks" \
        --project t2linux-Fedora-Live \
        --volid t2linux-Fedora-Live-41 \
        --iso-name "t2linux-$ks-41.iso"
    find results/*.iso -size +2G -exec sh -c "split -b 1999M -x {} {}. && rm {}" \;
    mv results/* /repo/builddir/iso/
done
cleanup
