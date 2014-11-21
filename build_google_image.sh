#!/bin/sh

set -e
set -x

BASEDIR=$(dirname $0)
WRKDIR=${PWD}

TS=`env TZ=UTC date +%Y%m%d%H%M%S`

# release to use
VERSION=10.1-RELEASE

# see truncate(1) for acceptable sizes
VMSIZE=10g
SWAPSIZE=1G

TMPFILE=FreeBSD-${VERSION}-amd64-gcloud-image-${TS}.raw

###############################

# fetch base and kernel for this version
mkdir -p ${VERSION}
cd ${VERSION}
if [ ! -f base.txz ]; then
  fetch http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/${VERSION}/base.txz
fi
if [ ! -f kernel.txz ]; then
  fetch http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/${VERSION}/kernel.txz
fi

cd ${WRKDIR}

truncate -s ${VMSIZE} ${TMPFILE}
MD_UNIT=$(mdconfig -f ${TMPFILE})

newfs -j ${MD_UNIT}

mkdir -p /mnt/g/new

mount /dev/${MD_UNIT} /mnt/g/new

cd /mnt/g/new
tar -xzvf ${WRKDIR}/${VERSION}/base.txz
tar -xzvf ${WRKDIR}/${VERSION}/kernel.txz

cp /etc/resolv.conf etc/resolv.conf

chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg install sudo google-cloud-sdk google-daemon
chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg clean -ya
rm -rf var/db/pkg/repo*

cat << EOF > etc/resolv.conf
search google.internal
nameserver 169.254.169.254
nameserver 8.8.8.8
EOF

cat << EOF > etc/fstab
# Custom /etc/fstab for FreeBSD VM images
/dev/gpt/rootfs   /       ufs     rw      1       1
/dev/gpt/swapfs  none    swap    sw      0       0
EOF

cat << EOF > etc/rc.conf
console="comconsole"
dumpdev="AUTO"
ifconfig_vtnet0="SYNCDHCP mtu 1460"
ntpd_sync_on_start="YES"
ntpd_enable="YES"
sshd_enable="YES"
google_accounts_manager_enable="YES"
EOF

cat << EOF > boot/loader.conf
console="comconsole"
hw.memtest.tests="0"
kern.timecounter.hardware=ACPI-safe
EOF

cat << EOF >> etc/hosts
169.254.169.254 metadata.google.internal metadata
EOF

# TODO: configure to use google NTP servers - metadata.google.internal (169.254.169.254)
# TODO: configure syslog to use serial?

sync
sync

cp boot/pmbr ${WRKDIR}
cp boot/gptboot ${WRKDIR}

cd ${WRKDIR}

umount /mnt/g/new

mdconfig -d -u ${MD_UNIT}

sync
sleep 5
sync

mkimg -s gpt -b pmbr \
        -p freebsd-boot/bootfs:=gptboot \
        -p freebsd-swap/swapfs::${SWAPSIZE} \
        -p freebsd-ufs/rootfs:=${TMPFILE} \
        -o disk.raw
sync

# gtar -Szcf FreeBSD-${VERSION}-amd64-${TS}.tar.gz disk.raw
# gsutil cp FreeBSD-10.1-RELEASE-amd64-20141118052210.1.tar.gz gs://swills-test-bucket
# gcutil addimage freebsd-101 gs://swills-test-bucket/FreeBSD-10.1-RELEASE-amd64-20141118052210.1.tar.gz
