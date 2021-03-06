#!/bin/bash
#
# Copyright (C) 2018 Red Hat, Inc.
#
# SPDX-License-Identifier: LGPL-2.0+
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place - Suite 330,
# Boston, MA 02111-1307, USA.

set -xeuo pipefail

dn=$(dirname $0)
. ${dn}/libinsttest.sh

echo "1..1"

cd /var/srv
mkdir repo
ostree --repo=repo init --mode=archive
echo -e '[archive]\nzlib-level=1\n' >> repo/config
host_nonremoteref=$(echo ${host_refspec} | sed 's,[^:]*:,,')
ostree --repo=repo pull-local /ostree/repo ${host_commit}
ostree --repo=repo refs ${host_commit} --create=${host_nonremoteref}

run_tmp_webserver $(pwd)/repo

origin=$(cat ${test_tmpdir}/httpd-address)

cleanup() {
    cd ${oldpwd}
    umount mnt || true
    test -n "${blkdev}" && losetup -d ${blkdev} || true
    rm -rf mnt testblk.img
}
oldpwd=`pwd`
trap cleanup EXIT

mkdir mnt
truncate -s 2G testblk.img
if ! blkdev=$(losetup --find --show $(pwd)/testblk.img); then
    echo "ok # SKIP not run when cannot setup loop device"
    exit 0
fi

mkfs.xfs -m reflink=1 ${blkdev}

mount ${blkdev} mnt

test_tmpdir=$(pwd)/mnt
cd ${test_tmpdir}

touch a
if cp --reflink a b; then
    mkdir repo
    ostree --repo=repo init
    ostree config --repo=repo set core.payload-link-threshold 0
    ostree --repo=repo remote add origin --set=gpg-verify=false ${origin}
    ostree --repo=repo pull --disable-static-deltas origin ${host_nonremoteref}
    if test `find repo -name '*.payload-link' | wc -l` = 0; then
        fatal ".payload-link files not found"
    fi

    find repo -name '*.payload-link' | while read i;
    do
        payload_checksum=$(basename $(dirname $i))$(basename $i .payload-link)
        payload_checksum_calculated=$(sha256sum $(readlink -f $i) | cut -d ' ' -f 1)
        if test $payload_checksum != $payload_checksum_calculated; then
            fatal ".payload-link has the wrong checksum"
        fi
    done
    echo "ok pull creates .payload-link"
else
    echo "ok # SKIP no reflink support in the file system"
fi
