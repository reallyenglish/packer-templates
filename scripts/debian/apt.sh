#!/bin/bash

set -e
set -x

# Disable periodic activities of apt, which causes `apt` tasks to fail by
# holding a lock
sudo tee -a /etc/apt/apt.conf.d/10disable-periodic <<EOF
APT::Periodic::Enable "0";
EOF

sudo apt-get update

# install the latest ansible from ppa
sudo apt-get -y install software-properties-common
sudo apt-add-repository "deb http://ftp.debian.org/debian jessie-backports main"
sudo apt-get update
sudo apt-get -y -t jessie-backports install ansible
sudo apt-get -y install rsync
