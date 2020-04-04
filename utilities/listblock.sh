#!/bin/bash
. /etc/init.d/functions

# ln -s /prog/list_block.sh /usr/bin/listblock
# chmod +x /usr/bin/listblock

#firewall-cmd --zone=public --list-all
firewall-cmd --zone=public --list-rich-rules
