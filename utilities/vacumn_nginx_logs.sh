#!/bin/bash

find /var/log/nginx/bak -name "*.7z"  -type f -amin +30 -exec rm -rf {} \;
