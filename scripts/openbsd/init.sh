#!/bin/ksh

set -e
set -x

sudo tee /etc/pkg.conf <<EOF
installpath = ftp.openbsd.org
EOF

sudo pkg_add ansible rsync--
# ensure that only `ansible` is installed from our ports tree
sudo pkg_delete ansible
ftp -o - https://github.com/reallyenglish/ports/archive/RE_`uname -r | sed -e 's/[.]/_/'`.tar.gz | sudo tar -C /usr -zxf -
sudo mv /usr/ports-RE_`uname -r | sed -e 's/[.]/_/'` /usr/ports
( cd /usr/ports/sysutils/ansible && sudo make install clean && sudo rm -rf /usr/ports/* )
sudo ln -sf /usr/local/bin/python2.7 /usr/local/bin/python
sudo ln -sf /usr/local/bin/python2.7-2to3 /usr/local/bin/2to3
sudo ln -sf /usr/local/bin/python2.7-config /usr/local/bin/python-config
sudo ln -sf /usr/local/bin/pydoc2.7  /usr/local/bin/pydoc

sudo pkg_add curl

sudo tee /etc/rc.conf.local <<EOF
sndiod_flags=NO
sendmail_flags=NO
EOF

# replace buggy openbsd_pkg.py with the latest, and known-to-work, one.
# fixes https://github.com/reallyenglish/ansible-role-postfix/issues/13 and
# others
# XXX remove the workaround below when 5.9 has the latest ansible
if [ `uname -r` == `5.9` ]; then
    sudo ftp -o /usr/local/lib/python2.7/site-packages/ansible/modules/extras/packaging/os/openbsd_pkg.py https://raw.githubusercontent.com/ansible/ansible/b134352d8ca33745c4277e8cb85af3ad2dcae2da/lib/ansible/modules/packaging/os/openbsd_pkg.py
fi

sudo sed -i'.bak' -e 's/ \/opt ffs rw,nodev,nosuid 1 2/ \/opt ffs rw,nosuid 1 2/' /etc/fstab
sudo rm /etc/fstab.bak

sudo sed -i'.bak' -e 's/\(ttyC[^0].*getty.*\)on /\1off/' /etc/ttys
sudo rm /etc/ttys.bak
