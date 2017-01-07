#!/bin/bash

set -e
set -x

sudo apt-get update

# install the latest ansible from ppa
sudo apt-get -y install software-properties-common
sudo apt-add-repository "deb http://ftp.debian.org/debian jessie-backports main"
sudo apt-get update
sudo apt-get -y -t jessie-backports install ansible
sudo apt-get -y install rsync
