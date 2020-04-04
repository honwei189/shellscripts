#!/bin/bash

#find . -name "*.log" -print0 | xargs -0 rm -rf {} \;
#find . -name "*.log" -type f -exec dd if=/dev/null of={} \;
find /var/log/nginx/ -name "*.log"  -type f -exec /bin/sh -c "> '{}'" ';'
rm -rf /var/log/nginx/*.log-*
