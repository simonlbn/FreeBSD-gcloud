#!/bin/sh

set -e
set -x

# Script to create images for use in Google Cloud Compute

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

yes | chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg install sudo google-cloud-sdk google-daemon bsdinfo bsdstats
chroot . usr/bin/env ASSUME_ALWAYS_YES=yes usr/sbin/pkg clean -ya
chroot . usr/sbin/pw lock root

rm -rf var/db/pkg/repo*

cat << EOF > etc/resolv.conf
search google.internal
nameserver 169.254.169.254
nameserver 8.8.8.8
EOF

cat << EOF > etc/fstab
# Custom /etc/fstab for FreeBSD VM images
/dev/gpt/rootfs   /       ufs     rw      1       1
/dev/gpt/swapfs   none    swap    sw      0       0
EOF

cat << EOF > etc/rc.conf
console="comconsole"
dumpdev="AUTO"
ifconfig_vtnet0="SYNCDHCP mtu 1460"
ntpd_sync_on_start="YES"
ntpd_enable="YES"
sshd_enable="YES"
bsdstats_enable="YES"
google_accounts_manager_enable="YES"
EOF

cat << EOF > boot/loader.conf
console="comconsole"
hw.memtest.tests="0"
kern.timecounter.hardware=ACPI-safe
autoboot-delay="0"
loader_logo="none"
EOF

cat << EOF >> etc/hosts
169.254.169.254 metadata.google.internal metadata
EOF

cat << EOF > etc/ntp.conf
server metadata.google.internal iburst

restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery

restrict 127.0.0.1
restrict -6 ::1
restrict 127.127.1.0
EOF

cat << EOF >> etc/profile
if [ ! -f ~/.hushlogin ]; then
  bsdinfo
fi
EOF

cat << EOF >> etc/syslog.conf
*.err;kern.warning;auth.notice;mail.crit                /dev/console
EOF

cat << EOF >> etc/ssh/sshd_config
ChallengeResponseAuthentication no
X11Forwarding no
AcceptEnv LANG
Ciphers aes128-ctr,aes192-ctr,aes256-ctr,arcfour256,arcfour128,aes128-cbc,3des-cbc
AllowAgentForwarding no
ClientAliveInterval 420
EOF

cat << EOF >> etc/crontab
0	3	*	*	*	root	/usr/sbin/freebsd-update cron
EOF

cat << EOF >> etc/sysctl.conf
net.inet.icmp.drop_redirect=1
net.inet.ip.redirect=0
net.inet.tcp.blackhole=2
net.inet.udp.blackhole=1
kern.ipc.somaxconn=1024
EOF

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
