#!/bin/sh

set -e
set -x

# Script to create images for use in Google Cloud Compute

# TODO: configure to use google NTP servers - metadata.google.internal (169.254.169.254)
# TODO: configure syslog to use serial?

###############################
# tweak these to taste

# release to use
VERSION=10.1-RELEASE
# see truncate(1) for acceptable sizes
VMSIZE=10g
# size passed to mkimg(1)
SWAPSIZE=1G

# which bucket to upload to
MYBUCKET=swills-test-bucket
TS=`env TZ=UTC date +%Y%m%d%H%M%S`
IMAGENAME=FreeBSD-${VERSION}-amd64-${TS}
BUCKETFILE=${IMAGENAME}.tar.gz

TMPFILE=FreeBSD-${VERSION}-amd64-gcloud-image-${TS}.raw

###############################

BASEDIR=$(dirname $0)
WRKDIR=${PWD}

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
bar -n ${WRKDIR}/${VERSION}/base.txz   | tar -xzf -
bar -n ${WRKDIR}/${VERSION}/kernel.txz | tar -xzf -

cp /etc/resolv.conf etc/resolv.conf

chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg install sudo google-cloud-sdk google-daemon
chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg clean -ya
rm -rf var/db/pkg/repo*

cat << EOF > etc/resolv.conf
search google.internal
nameserver 169.254.169.254
nameserver 8.8.8.8
EOF

cat etc/resolv.conf

cat << EOF > etc/fstab
# Custom /etc/fstab for FreeBSD VM images
/dev/gpt/rootfs   /       ufs     rw      1       1
/dev/gpt/swapfs   none    swap    sw      0       0
EOF

cat etc/fstab

cat << EOF > etc/rc.conf
console="comconsole"
dumpdev="AUTO"
ifconfig_vtnet0="SYNCDHCP mtu 1460"
ntpd_sync_on_start="YES"
ntpd_enable="YES"
sshd_enable="YES"
google_accounts_manager_enable="YES"
EOF

cat etc/rc.conf

cat << EOF > boot/loader.conf
console="comconsole"
hw.memtest.tests="0"
kern.timecounter.hardware=ACPI-safe
EOF

cat boot/loader.conf

cat << EOF >> etc/hosts
169.254.169.254 metadata.google.internal metadata
EOF

cat etc/hosts

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

gtar -Szcf ${BUCKETFILE} disk.raw
rm ${TMPFILE} disk.raw pmbr gptboot

gsutil cp FreeBSD-${VERSION}-amd64-${TS}.tar.gz gs://${MYBUCKET}
gcutil addimage ${IMAGENAME} gs://${MYBUCKET}/${BUCKETFILE}
