#!/bin/bash

###############################################################################
# @description       : Manage NGINX whitelist for IPs and dynamic hostnames.
#                      Allows managing dynamic hosts/IPs into the NGINX 
#                      whitelist configuration, ensuring secure access control.
#                      Applicable for RHEL-based OS v7 and above
#                      (CentOS, RedHat, Oracle Linux, AlmaLinux, RockyLinux)
#                      and Ubuntu-based OS v18.04 and above.
# @installation      : ln -s update-nginx-whitelist.sh /usr/bin/nginx-whitelist
#                      or;
#                      mv update-nginx-whitelist.sh /usr/bin/nginx-whitelist
#                      chmod +x /usr/bin/nginx-whitelist
#                      Configure NGINX to include whitelist:
#                      echo "include /etc/nginx/conf.d/server/check_white_ip.conf;" >> /etc/nginx/nginx.conf
#                      Create required directories/files automatically by running the script.
#                      crontab (automatically run hourly): 
#                      0 * * * * /usr/bin/nginx-whitelist update >/dev/null 2>&1
# @usage             : nginx-whitelist add IP/HOSTNAME
#                      nginx-whitelist del IP/HOSTNAME
#                      nginx-whitelist delete IP/HOSTNAME
#                      nginx-whitelist list
#                      nginx-whitelist refresh
#                      nginx-whitelist update
#                      nginx-whitelist help
# @version           : "2.1.0"
# @creator           : Gordon Lim <honwei189@gmail.com>
# @modified by       : Your Name <YourEmail@example.com>
# @created           : 14/04/2020
# @last modified     : 29/11/2024
###############################################################################

############################# CONSTANTS & VARIABLES ###########################
NGINX_PATH="/etc/nginx"
NGINX_WHITELIST="$NGINX_PATH/whitelist"
WHITELIST_CONF_MAP_FILE="$NGINX_PATH/conf.d/whitelist.conf"
NGINX_CHECK_FROM_WHITELIST="$NGINX_PATH/conf.d/server/check_white_ip.conf"
IMMEDIATE_REFRESH=false

############################## COLORS FOR OUTPUT ##############################
SETCOLOR_SUCCESS="echo -en \\033[1;32m" # Green
SETCOLOR_FAILURE="echo -en \\033[1;31m" # Red
SETCOLOR_WARNING="echo -en \\033[1;33m" # Yellow
SETCOLOR_NORMAL="echo -en \\033[0;39m"  # Default
SETCOLOR_HEADER="echo -en \\033[1;34m"  # blue
SETCOLOR_BOLD="echo -en \\033[1;37m"    # bold white

############################## HELPER FUNCTIONS ###############################
print_header() {
    $SETCOLOR_HEADER
    echo "###############################################################################"
    echo "# $1"
    echo "###############################################################################"
    $SETCOLOR_NORMAL
}

initialize_files() {
    # Check system type
    OS=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    if [[ "$OS" != "centos" && "$OS" != "rhel" && "$OS" != "ubuntu" ]]; then
        $SETCOLOR_FAILURE
        echo "This script is only compatible with RHEL-based or Ubuntu-based systems."
        $SETCOLOR_NORMAL
        exit 1
    fi

    # Make sure the necessary tools exist
    if ! command -v host >/dev/null 2>&1; then
        echo "Installing required package for 'host' command..."
        if [[ "$OS" == "ubuntu" ]]; then
            sudo apt update && sudo apt install -y dnsutils
        else
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y bind-utils
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y bind-utils
            else
                $SETCOLOR_FAILURE
                echo "Error: Neither 'dnf' nor 'yum' is available. Please install 'bind-utils' manually."
                $SETCOLOR_NORMAL
                exit 1
            fi
        fi
    fi

    # Make sure the whitelisted directories and files exist
    mkdir -p "$NGINX_WHITELIST"
    touch "$NGINX_WHITELIST/hosts"
    touch "$NGINX_WHITELIST/ip"

    # Make sure the NGINX configuration directory and files exist
    mkdir -p "$NGINX_PATH/conf.d"
    mkdir -p "$NGINX_PATH/conf.d/server"
    [[ ! -f "$WHITELIST_CONF_MAP_FILE" ]] && touch "$WHITELIST_CONF_MAP_FILE"
    if [[ ! -f "$NGINX_CHECK_FROM_WHITELIST" ]]; then
        cat <<EOF >"$NGINX_CHECK_FROM_WHITELIST"
        if (\$give_white_ip_access = 0) {
            return 404;
        }
EOF
        $SETCOLOR_SUCCESS
        echo "Created file: $NGINX_CHECK_FROM_WHITELIST"
        $SETCOLOR_NORMAL
    fi
}

refresh_nginx() {
    $SETCOLOR_HEADER
    echo "Reloading NGINX configuration..."
    $SETCOLOR_NORMAL
    sudo nginx -s reload
    sudo service nginx reload
    $SETCOLOR_SUCCESS
    echo "NGINX configuration refreshed."
    $SETCOLOR_NORMAL
}

prompt_for_refresh() {
    $SETCOLOR_WARNING
    echo "NGINX configuration needs to be refreshed to take effect."
    echo -n "Would you like to refresh NGINX now? (Y/N): "
    $SETCOLOR_NORMAL
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            refresh_nginx
            ;;
        [nN][oO]|[nN])
            $SETCOLOR_WARNING
            echo "Skipping NGINX refresh. Remember to refresh manually using:"
            $SETCOLOR_SUCCESS
            echo "sudo nginx -s reload"
            $SETCOLOR_NORMAL
            ;;
        *)
            $SETCOLOR_FAILURE
            echo "Invalid input. Please enter 'Y' or 'N'."
            $SETCOLOR_NORMAL
            prompt_for_refresh
            ;;
    esac
}

write_whitelist_conf() {
    local ip_list="$1"
    local host_list="$2"

    # Clear and generate new whitelist.conf
    >"$WHITELIST_CONF_MAP_FILE"
    cat <<EOF >"$WHITELIST_CONF_MAP_FILE"
# Process X-Forwarded-For or Tailscale IP addresses
map \$http_x_forwarded_for \$real_ip {
    ~^(\d+\.\d+\.\d+\.\d+) \$1;  # Use X-Forwarded-For if it contains a valid IP address
    default \$realip_remote_addr;  # Otherwise, use \$realip_remote_addr
}

# Check if http_x_forwarded_for is a valid IP
map \$http_x_forwarded_for \$real_ip_from_forwarded {
    "~^(\d+\.\d+\.\d+\.\d+)$" \$http_x_forwarded_for;  # Use \$http_x_forwarded_for if it is a valid IP
    default "";  # Otherwise, set to empty
}

# Finalize \$real_ip settings with the following priority:
map \$real_ip_from_forwarded \$real_ip {
    "" \$proxy_add_x_forwarded_for;  # Use \$proxy_add_x_forwarded_for if \$real_ip_from_forwarded is empty
    default \$real_ip_from_forwarded;  # Otherwise, use \$real_ip_from_forwarded
}

# Check whitelist based on \$real_ip
map \$real_ip \$give_white_ip_access {
    default 0;
EOF

    # Write IP entry
    for ip in $ip_list; do
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            echo "    $ip 1;" >>"$WHITELIST_CONF_MAP_FILE"
        else
            $SETCOLOR_WARNING
            echo "Skipping invalid IP: $ip"
            $SETCOLOR_NORMAL
        fi
    done

    # Parse and write hostname entries
    for host in $host_list; do
        resolved_ip=$(host "$host" 2>/dev/null | awk '/has address/ { print $4 }')
        if [[ $resolved_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "    $resolved_ip 1;" >>"$WHITELIST_CONF_MAP_FILE"
        else
            $SETCOLOR_WARNING
            echo "Skipping unresolved hostname: $host"
            $SETCOLOR_NORMAL
        fi
    done

    # Optionally fetch IPs from Cloudflare dynamically (uncomment if needed)
    # for ip in $(curl --silent https://www.cloudflare.com/ips-v4); do
    #     echo "      $ip 1;" >>"$WHITELIST_CONF_MAP_FILE"
    # done
    # for ip in $(curl --silent https://www.cloudflare.com/ips-v6); do
    #     echo "      $ip 1;" >>"$WHITELIST_CONF_MAP_FILE"
    # done

    echo "}" >>"$WHITELIST_CONF_MAP_FILE"
}

add_entry() {
    local entries=("$@")
    for entry in "${entries[@]}"; do
        local is_ip=0
        [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] && is_ip=1

        if [[ $is_ip -eq 1 ]]; then
            if ! grep -Fxq "$entry" "$NGINX_WHITELIST/ip"; then
                echo "$entry" >>"$NGINX_WHITELIST/ip"
                echo "Added IP: $entry"
            else
                echo "IP already exists: $entry"
            fi
        else
            if ! grep -Fxq "$entry" "$NGINX_WHITELIST/hosts"; then
                echo "$entry" >>"$NGINX_WHITELIST/hosts"
                echo "Added hostname: $entry"
            else
                echo "Hostname already exists: $entry"
            fi
        fi
    done

    # 調用寫入函數
    write_whitelist_conf "$(cat "$NGINX_WHITELIST/ip" | grep -Ev '^(;|#|//|$)')" \
                         "$(cat "$NGINX_WHITELIST/hosts" | grep -Ev '^(;|#|//|$)')"

    prompt_for_refresh
}

update_whitelist() {
    # call write function
    write_whitelist_conf "$(cat "$NGINX_WHITELIST/ip" | grep -Ev '^(;|#|//|$)')" \
                         "$(cat "$NGINX_WHITELIST/hosts" | grep -Ev '^(;|#|//|$)')"

    refresh_nginx
}

delete_entry() {
    local entries=("$@")
    for entry in "${entries[@]}"; do
        local is_ip=0
        [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && is_ip=1

        if [[ $is_ip -eq 1 ]]; then
            # Remove matching IPs, use exact match, make sure there are no extra white spaces in the line
            if grep -Fxq "$entry" "$NGINX_WHITELIST/ip"; then
                sed -i "/^$entry$/d" "$NGINX_WHITELIST/ip"
                $SETCOLOR_SUCCESS
                echo "IP $entry has been removed from the whitelist."
                $SETCOLOR_NORMAL
            else
                $SETCOLOR_WARNING
                echo "IP $entry not found in the whitelist."
                $SETCOLOR_NORMAL
            fi
        else
            # Remove matching hostnames
            if grep -Fxq "$entry" "$NGINX_WHITELIST/hosts"; then
                sed -i "/^$entry$/d" "$NGINX_WHITELIST/hosts"
                $SETCOLOR_SUCCESS
                echo "Hostname $entry has been removed from the whitelist."
                $SETCOLOR_NORMAL
            else
                $SETCOLOR_WARNING
                echo "Hostname $entry not found in the whitelist."
                $SETCOLOR_NORMAL
            fi
        fi
    done

    # Call the write function to update the configuration file
    write_whitelist_conf "$(grep -Ev '^(;|#|//|$)' "$NGINX_WHITELIST/ip")" \
                         "$(grep -Ev '^(;|#|//|$)' "$NGINX_WHITELIST/hosts")"

    prompt_for_refresh
}

list_entries() {
    print_header "NGINX Whitelist"
    $SETCOLOR_BOLD
    echo "IPs:"
    $SETCOLOR_SUCCESS
    cat "$NGINX_WHITELIST/ip"
    echo ""
    $SETCOLOR_BOLD
    echo "Hostnames:"
    $SETCOLOR_SUCCESS
    cat "$NGINX_WHITELIST/hosts"
    $SETCOLOR_NORMAL
}

print_usage() {
    print_header "NGINX Whitelist Management Script"
    echo "Usage:"
    $SETCOLOR_BOLD
    echo "  $0 <command> [options] [arguments]"
    $SETCOLOR_NORMAL
    echo ""
    $SETCOLOR_SUCCESS
    echo "Commands:"
    $SETCOLOR_NORMAL
    echo "  add       Add one or more IPs or hostnames to the whitelist."
    echo "  delete    Remove one or more IPs or hostnames from the whitelist."
    echo "  del       Alias for 'delete'."
    echo "  update    Update NGINX whitelist and reload the configuration."
    echo "  refresh   Alias for 'update'."
    echo "  list      Display all current whitelisted IPs and hostnames."
    echo "  help      Show this help message and exit."
    echo ""
    $SETCOLOR_SUCCESS
    echo "Options:"
    $SETCOLOR_NORMAL
    echo "  --refresh  Immediately refresh NGINX after adding/deleting entries."
    echo ""
    $SETCOLOR_SUCCESS
    echo "Examples:"
    $SETCOLOR_NORMAL
    echo "  $0 add 192.168.0.1 example.com --refresh"
    echo "  $0 delete 10.0.0.1 another-host.com"
    echo "  $0 list"
    echo "  $0 update"
}

############################### MAIN EXECUTION ################################
initialize_files

if [[ -z "$1" ]]; then
    print_usage
    exit 1
fi

case "$1" in
    add)
        shift
        [[ "$1" == "--refresh" ]] && IMMEDIATE_REFRESH=true && shift
        add_entry "$@"
        ;;
    delete|del)
        shift
        [[ "$1" == "--refresh" ]] && IMMEDIATE_REFRESH=true && shift
        delete_entry "$@"
        ;;
    update|refresh)
        update_whitelist
        ;;
    list)
        list_entries
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        $SETCOLOR_FAILURE
        echo "Error: Unknown command '$1'"
        $SETCOLOR_NORMAL
        echo ""
        print_usage
        exit 1
        ;;
esac

exit 0
