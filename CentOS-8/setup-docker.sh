#!/bin/sh
###
 # @description       : Docker installation script
 # @version           : "1.0.1" 
 # @creator           : Gordon Lim <honwei189@gmail.com>
 # @created           : 08/04/2020 12:05:59
 # @last modified     : 09/03/2022 19:01:36
 # @last modified by  : Gordon Lim <honwei189@gmail.com>
 ###
 
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

#For CentOS 8.1
#dnf clean all 
#dnf -y remove podman
##dnf -y install oci-systemd-hook libvarlink
##rpm -Uvh --nodeps $(repoquery --location podman)
#dnf install -y @container-tools

#dnf install docker-ce --nobest -y
dnf install docker-ce --allowerasing -y
#dnf install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.10-3.2.el7.x86_64.rpm -y
#dnf install docker-ce -y

systemctl enable --now docker
systemctl status docker

# Install docker-compose
curl -L https://github.com/docker/compose/releases/download/2.23.3/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

