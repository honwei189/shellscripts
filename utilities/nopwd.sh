#!/bin/bash

if [ ! "$1" ] ; then
  echo $"Usage: $0 HOST_NAME_OR_IP"
  exit
fi

if [ ! -f /root/.ssh/id_rsa.pub ]; then
    ssh-keygen -f ~/.ssh/id_rsa -P ""
fi

cat /root/.ssh/id_rsa.pub | ssh $1 'mkdir -p .ssh && cat >> .ssh/authorized_keys'

