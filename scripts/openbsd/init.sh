#!/bin/ksh

set -e
set -x

sudo tee /etc/pkg.conf <<EOF
installpath = ftp.openbsd.org
EOF

sudo pkg_add ansible rsync--
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
sudo ftp -o /usr/local/lib/python2.7/site-packages/ansible/modules/extras/packaging/os/openbsd_pkg.py  https://github.com/ansible/ansible/blob/b134352d8ca33745c4277e8cb85af3ad2dcae2da/lib/ansible/modules/packaging/os/openbsd_pkg.py

sed -e 's/\(ttyC[^0].*getty.*\)on /\1off/' /etc/ttys | sudo tee /etc/ttys > /dev/null
