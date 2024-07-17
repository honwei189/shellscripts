#!/bin/bash

# setup-mail-security.sh
#
# Purpose:
# This script configures DKIM, SPF, and DMARC for a specified domain on a server running either Sendmail or Postfix,
# ensuring that emails sent from the domain are authenticated and meet modern email security standards.
# If a Cloudflare API token is provided, it will automatically add the necessary DNS records.
#
# Usage:
# ./setup-mail-security.sh [-d <domain>] [-s <selector>] [-t <cloudflare_api_token>] [-p <ports>] [-f <on|off>] [--wildcard] [--import <private_key_path> <public_key_path>|<archive_file>] [--export <output_directory>|<archive_file>] [--keys-only] [--export-only] [--help]
# 
# Parameters:
# -d <domain>             : The base domain name (e.g., yourdomain.com or sub.yourdomain.com) (not required if using --import with archive file)
# -s <selector>           : DKIM selector (e.g., default or mysub) (not required if using --import with archive file)
# -t <cloudflare_api_token> : (Optional) Cloudflare API token for automatically adding DNS records
# -p <ports>              : (Optional) Comma-separated list of ports to open (e.g., 25,587)
# -f <on|off>             : (Optional) Enable or disable firewall configuration (default: off)
# --wildcard              : (Optional) Configure DKIM for all subdomains
# --import <private_key_path> <public_key_path>|<archive_file> : (Optional) Use existing DKIM keys or configurations from specified paths or archive file
# --export <output_directory>|<archive_file> : (Optional) Export generated DKIM keys to the specified directory or archive file
# --keys-only             : (Optional) Only import/export DKIM private and public keys, not other configurations
# --export-only           : (Optional) Only export existing DKIM keys to the specified directory or archive file
# --help                  : Display this help message
#
# Examples:
# 1. Configure DKIM with Cloudflare API Token, enabling firewall configuration:
#    ./setup-mail-security.sh -d mysub.yourdomain.com -s mysub -t YOUR_CLOUDFLARE_API_TOKEN -f on --wildcard
#
# 2. Configure DKIM without Cloudflare API Token and disabling firewall configuration:
#    ./setup-mail-security.sh -d mysub.yourdomain.com -s mysub -f off --wildcard
#
# 3. Import existing DKIM keys:
#    ./setup-mail-security.sh --import /path/to/private.key /path/to/public.key
#
# 4. Export generated DKIM keys:
#    ./setup-mail-security.sh --export /path/to/output_directory
#
# 5. Import DKIM keys and configurations from an archive:
#    ./setup-mail-security.sh --import /path/to/archive.tar.gz
#
# 6. Export DKIM keys and configurations to an archive:
#    ./setup-mail-security.sh --export /path/to/output_archive.tar.gz
#
# 7. Only import DKIM private and public keys:
#    ./setup-mail-security.sh --import /path/to/private.key /path/to/public.key --keys-only
#
# 8. Only export DKIM private and public keys:
#    ./setup-mail-security.sh --export /path/to/output_directory --keys-only
#
# 9. Only export existing DKIM keys and configurations:
#    ./setup-mail-security.sh --export-only
#
# Steps:
# 1. Check and Install Necessary Packages: Ensures that required packages (epel-release, opendkim, opendkim-tools, jq, curl) are installed if not already present.
# 2. Detect Mail Service: Checks if sendmail or postfix is installed. If neither is found, it installs sendmail.
# 3. Generate or Regenerate DKIM Keys: Generates or regenerates DKIM keys or imports existing keys.
# 4. Export DKIM Keys: Exports the generated DKIM keys if requested.
# 5. Configure OpenDKIM: Creates and populates the OpenDKIM configuration file and required tables.
# 6. Configure Mail Service: Configures sendmail or postfix to use OpenDKIM for signing emails.
# 7. Restart Services: Restarts OpenDKIM and the mail service to apply the configuration.
# 8. Add DNS Records: Extracts the DKIM public key and adds the necessary DKIM, SPF, and DMARC records to Cloudflare if an API token is provided,
#    or displays the records to be added manually.
# 9. Configure Firewall: Ensures necessary ports are open for mail services and OpenDKIM.
# 10. Rollback Changes: In case of failure, revert the changes to the previous state.
# 11. Display Key Locations: Shows the paths to the generated or imported DKIM private and public key files.

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configurable variables
OPENDKIM_PORT=8891
DEFAULT_PORTS="25,587"
DEFAULT_FIREWALL="off"
DEFAULT_EXPORT_DIR="/tmp/dkim_keys"
DEFAULT_ARCHIVE_FILE="/tmp/dkim_keys.tar.gz"
WILDCARD=false
IMPORT=false
EXPORT=false
EXPORT_ONLY=false
KEYS_ONLY=false
MAIL_SERVICE=""

# Function to extract base domain
extract_base_domain() {
    local domain=$1
    echo "$domain" | awk -F. '{if (NF>2) {print $(NF-1)"."$NF} else {print $0}}'
}

# Backup function to create backups of configuration files
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "$file.bak"
    fi
}

# Restore function to restore configuration files from backups
restore_file() {
    local file=$1
    if [ -f "$file.bak" ];then
        mv "$file.bak" "$file"
    fi
}

# Function to print usage
print_usage() {
    echo -e "${BOLD}${BLUE}Usage:${NC}"
    echo -e "  ${BOLD}$0${NC} [-d ${GREEN}<domain>${NC}] [-s ${GREEN}<selector>${NC}] [-t ${GREEN}<cloudflare_api_token>${NC}] [-p ${GREEN}<ports>${NC}] [-f ${GREEN}<on|off>${NC}] [--wildcard] [--import ${GREEN}<private_key_path> <public_key_path>${NC}|${GREEN}<archive_file>${NC}] [--export ${GREEN}<output_directory>${NC}|${GREEN}<archive_file>${NC}] [--keys-only] [--export-only] [--help]"
    echo -e "\n${BOLD}${BLUE}Parameters:${NC}"
    echo -e "  ${GREEN}-d <domain>${NC}             : The base domain name (e.g., yourdomain.com or sub.yourdomain.com) (not required if using --import with archive file)"
    echo -e "  ${GREEN}-s <selector>${NC}           : DKIM selector (e.g., default or mysub) (not required if using --import with archive file)"
    echo -e "  ${GREEN}-t <cloudflare_api_token>${NC} : (Optional) Cloudflare API token for automatically adding DNS records"
    echo -e "  ${GREEN}-p <ports>${NC}              : (Optional) Comma-separated list of ports to open (e.g., 25,587)"
    echo -e "  ${GREEN}-f <on|off>${NC}             : (Optional) Enable or disable firewall configuration (default: off)"
    echo -e "  ${GREEN}--wildcard${NC}              : (Optional) Configure DKIM for all subdomains"
    echo -e "  ${GREEN}--import <private_key_path> <public_key_path>${NC}|${GREEN}<archive_file>${NC} : (Optional) Use existing DKIM keys or configurations from specified paths or archive file"
    echo -e "  ${GREEN}--export <output_directory>${NC}|${GREEN}<archive_file>${NC} : (Optional) Export generated DKIM keys to the specified directory or archive file (default: $DEFAULT_EXPORT_DIR)"
    echo -e "  ${GREEN}--keys-only${NC}             : (Optional) Only import/export DKIM private and public keys, not other configurations"
    echo -e "  ${GREEN}--export-only${NC}           : (Optional) Only export existing DKIM keys to the specified directory or archive file"
    echo -e "  ${GREEN}--help${NC}                  : Display this help message"

    echo -e "\n${BOLD}${BLUE}Examples:${NC}"
    echo -e "  ${BOLD}${BLUE}1.${NC}${NC} Configure DKIM with Cloudflare API Token, enabling firewall configuration:"
    echo -e "     ${BOLD}$0 -d mysub.yourdomain.com -s mysub -t YOUR_CLOUDFLARE_API_TOKEN -f on --wildcard${NC}"
    echo -e "  ${BOLD}${BLUE}2.${NC}${NC} Configure DKIM without Cloudflare API Token and disabling firewall configuration:"
    echo -e "     ${BOLD}$0 -d mysub.yourdomain.com -s mysub -f off --wildcard${NC}"
    echo -e "  ${BOLD}${BLUE}3.${NC}${NC} Import existing DKIM keys:"
    echo -e "     ${BOLD}$0 --import /path/to/private.key /path/to/public.key${NC}"
    echo -e "  ${BOLD}${BLUE}4.${NC}${NC} Export generated DKIM keys:"
    echo -e "     ${BOLD}$0 --export /path/to/output_directory${NC}"
    echo -e "  ${BOLD}${BLUE}5.${NC}${NC} Import DKIM keys and configurations from an archive:"
    echo -e "     ${BOLD}$0 --import /path/to/archive.tar.gz${NC}"
    echo -e "  ${BOLD}${BLUE}6.${NC}${NC} Export DKIM keys and configurations to an archive:"
    echo -e "     ${BOLD}$0 --export /path/to/output_archive.tar.gz${NC}"
    echo -e "  ${BOLD}${BLUE}7.${NC}${NC} Only import DKIM private and public keys:"
    echo -e "     ${BOLD}$0 --import /path/to/private.key /path/to/public.key --keys-only${NC}"
    echo -e "  ${BOLD}${BLUE}8.${NC}${NC} Only export DKIM private and public keys:"
    echo -e "     ${BOLD}$0 --export /path/to/output_directory --keys-only${NC}"
    echo -e "  ${BOLD}${BLUE}9.${NC}${NC} Only export existing DKIM keys and configurations:"
    echo -e "     ${BOLD}$0 --export-only${NC}"
    exit 1
}

# Rollback function to restore configurations in case of failure
rollback() {
    echo -e "${RED}${BOLD}Rolling back changes...${NC}"
    restore_file /etc/opendkim.conf

    if [ "$MAIL_SERVICE" == "sendmail" ]; then
        restore_file /etc/mail/sendmail.mc
        systemctl restart sendmail || true
    fi

    if [ "$MAIL_SERVICE" == "postfix" ]; then
        restore_file /etc/postfix/main.cf
        systemctl restart postfix || true
    fi

    systemctl restart opendkim || true
    echo -e "${GREEN}${BOLD}Rollback completed.${NC}"
}

# Trap any error and initiate rollback
trap 'rollback' ERR

# Function to export DKIM keys
export_dkim_keys() {
    echo
    echo -e "${BLUE}${BOLD}Exporting DKIM keys...${NC}"
    # Create a temporary directory for packaging
    TEMP_DIR=$(mktemp -d)
    mkdir -p "${TEMP_DIR}"

    # Copy files to the temporary directory
    cp -r /etc/opendkim/keys/${BASE_DOMAIN} ${TEMP_DIR}
    if [ "$KEYS_ONLY" = false ];then
        cp /etc/opendkim/KeyTable ${TEMP_DIR}
        cp /etc/opendkim/SigningTable ${TEMP_DIR}
        cp /etc/opendkim/TrustedHosts ${TEMP_DIR}
    fi

    # Create a compressed archive
    ARCHIVE_PATH=$DEFAULT_ARCHIVE_FILE
    mkdir -p "$(dirname ${ARCHIVE_PATH})"
    tar -czf ${ARCHIVE_PATH} -C ${TEMP_DIR} .

    # Clean up the temporary directory
    rm -rf ${TEMP_DIR}
    echo -e "${GREEN}${BOLD}DKIM keys and configurations exported to ${ARCHIVE_PATH}${NC}"
}

# Get parameters
while getopts ":d:s:t:p:f:-:" opt; do
    case ${opt} in
        d)
            BASE_DOMAIN=${OPTARG}
            ;;
        s)
            SELECTOR=${OPTARG}
            ;;
        t)
            CF_API_TOKEN=${OPTARG}
            ;;
        p)
            PORTS=${OPTARG}
            ;;
        f)
            FIREWALL=${OPTARG}
            ;;
        -)
            case "${OPTARG}" in
                wildcard)
                    WILDCARD=true
                    ;;
                import)
                    IMPORT=true
                    PRIVATE_KEY_PATH="${!OPTIND}"; shift
                    PUBLIC_KEY_PATH="${!OPTIND}"; shift
                    ;;
                export)
                    EXPORT=true
                    OUTPUT_DIRECTORY="${!OPTIND}"; shift
                    ;;
                keys-only)
                    KEYS_ONLY=true
                    ;;
                export-only)
                    EXPORT_ONLY=true
                    ;;
                help)
                    print_usage
                    ;;
                *)
                    print_usage
                    ;;
            esac
            ;;
        *)
            print_usage
            ;;
    esac
done

# 提取顶级域名
BASE_DOMAIN=$(extract_base_domain ${BASE_DOMAIN})
SERVER_HOSTNAME=$(hostname)

# If export-only mode, call export_dkim_keys and exit
if [ "$EXPORT_ONLY" = true ]; then
    export_dkim_keys
    exit 0
fi

if [ "$IMPORT" = false ] && ([ -z "${BASE_DOMAIN}" ] || [ -z "${SELECTOR}" ]); then
    print_usage
fi

# Use specified ports or default ports if not provided
if [ -z "${PORTS}" ];then
    PORTS=${DEFAULT_PORTS}
fi

# Use specified firewall setting or default setting if not provided
if [ -z "${FIREWALL}" ];then
    FIREWALL=${DEFAULT_FIREWALL}
fi

# Use specified output directory or default directory if not provided
if [ "$EXPORT" = true ] && [ -z "${OUTPUT_DIRECTORY}" ];then
    OUTPUT_DIRECTORY=${DEFAULT_EXPORT_DIR}
    mkdir -p $(dirname ${OUTPUT_DIRECTORY})
fi

# Function to check and install necessary packages
install_package() {
    local package=$1
    if ! rpm -q $package &> /dev/null; then
        echo -e "${BLUE}${BOLD}Installing package: ${package}${NC}"
        yum install -y $package
        return 0
    # else
    #     echo -e "${GREEN}${BOLD}Package ${package} already installed${NC}"
    #     return 1
    fi
}

# Function to enable and start services
enable_and_start_service() {
    local service=$1
    if ! systemctl is-active --quiet $service; then
        systemctl enable $service
        systemctl start $service
    else
        echo -e "${GREEN}${BOLD}Service ${service} is already running.${NC}"
    fi
}

install_and_configure_services() {
    echo -e "${BLUE}${BOLD}Checking and installing necessary packages...${NC}"
    install_package epel-release

    install_package opendkim && enable_and_start_service opendkim
    install_package opendkim-tools
    install_package jq
    install_package curl

    install_package opendkim && enable_and_start_service opendkim || {
        echo -e "${RED}${BOLD}Failed to install or start opendkim service.${NC}"
        exit 1
    }

    install_package sendmail && enable_and_start_service sendmail || {
        echo -e "${RED}${BOLD}Failed to install or start sendmail service.${NC}"
        exit 1
    }

    install_package sendmail-cf

    echo -e "${GREEN}${BOLD}Necessary packages installed and services started successfully.${NC}"
}

# Install necessary packages
install_and_configure_services

# Detect and install mail service if not present
if command -v sendmail &> /dev/null; then
    MAIL_SERVICE="sendmail"
elif command -v postfix &> /dev/null; then
    MAIL_SERVICE="postfix"
else
    # Default to sendmail if no mail service is installed
    MAIL_SERVICE="sendmail"
fi

echo -e "${BLUE}${BOLD}Mail service detected: ${MAIL_SERVICE}${NC}"

# Function to check if a firewall port is already open
is_port_open() {
    local port=$1
    firewall-cmd --list-ports | grep -q "${port}/tcp"
}

# Configure firewall to open necessary ports if firewall option is on
if [ "$FIREWALL" = "on" ];then
    echo -e "${BLUE}${BOLD}Configuring firewall...${NC}"
    IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
    for port in "${PORT_ARRAY[@]}"; do
        if ! is_port_open $port; then
            firewall-cmd --permanent --add-port=${port}/tcp
        fi
    done
    if ! firewall-cmd --list-sources --zone=trusted | grep -q "$TRUSTED_NETWORK"; then
        firewall-cmd --zone=trusted --add-source=$TRUSTED_NETWORK --permanent
    fi
    firewall-cmd --reload
else
    echo -e "${BLUE}${BOLD}Firewall configuration skipped.${NC}"
fi

# Generate or import DKIM keys
echo -e "${BLUE}${BOLD}Configuring DKIM keys...${NC}"
if [ "$IMPORT" = true ];then
    echo -e "${BLUE}${BOLD}Importing existing DKIM keys...${NC}"
    mkdir -p /etc/opendkim/keys/${BASE_DOMAIN}
    if [[ "$PRIVATE_KEY_PATH" =~ \.tar\.gz$ ]];then
        tar -xzf ${PRIVATE_KEY_PATH} -C /etc/opendkim
    else
        cp ${PRIVATE_KEY_PATH} /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key
        cp ${PUBLIC_KEY_PATH} /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt
    fi
    chown -R opendkim:opendkim /etc/opendkim/keys/${BASE_DOMAIN}
else
    echo -e "${BLUE}${BOLD}Generating new DKIM keys...${NC}"
    mkdir -p /etc/opendkim/keys/${BASE_DOMAIN}
    opendkim-genkey -b 2048 -d ${BASE_DOMAIN} -D /etc/opendkim/keys/${BASE_DOMAIN} -s ${SELECTOR} -v
    chown -R opendkim:opendkim /etc/opendkim/keys/${BASE_DOMAIN}
    mv /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.private /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key
fi

# Export DKIM keys if requested
if [ "$EXPORT" = true ];then
    export_dkim_keys
fi

# Import DKIM keys and configurations if requested
import_dkim_keys() {
    echo -e "${BLUE}${BOLD}Importing DKIM keys and configurations from archive...${NC}"
    mkdir -p /tmp/dkim_import
    tar -xzf ${PRIVATE_KEY_PATH} -C /tmp/dkim_import
    BASE_DOMAIN=$(basename $(find /tmp/dkim_import -type f -name 'dkim_private.key' | head -n 1 | xargs dirname))
    SELECTOR=$(basename $(find /tmp/dkim_import -type f -name '*.txt' | head -n 1 | sed 's/\.txt$//'))
    mkdir -p /etc/opendkim/keys/${BASE_DOMAIN}
    cp -r /tmp/dkim_import/* /etc/opendkim/
    chown -R opendkim:opendkim /etc/opendkim
    echo -e "${GREEN}${BOLD}DKIM keys and configurations imported for domain ${BASE_DOMAIN} with selector ${SELECTOR}${NC}"
}

# Backup and overwrite OpenDKIM configuration files
backup_and_overwrite_opendkim_config() {
    echo -e "${BLUE}${BOLD}Backing up and overwriting OpenDKIM configuration files...${NC}"
    backup_file /etc/opendkim/KeyTable
    backup_file /etc/opendkim/SigningTable
    backup_file /etc/opendkim/TrustedHosts
    backup_file /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key
    backup_file /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt
}

if [ "$IMPORT" = true ] && [[ "$PRIVATE_KEY_PATH" =~ \.tar\.gz$ ]];then
    backup_and_overwrite_opendkim_config
    import_dkim_keys
fi

# Configure OpenDKIM
if [ "$KEYS_ONLY" = false ];then
    echo -e "${BLUE}${BOLD}Configuring OpenDKIM...${NC}"
    backup_file /etc/opendkim.conf
    cat > /etc/opendkim.conf <<EOL
AutoRestart             Yes
AutoRestartRate         10/1h
Umask                   002
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
Socket                  inet:${OPENDKIM_PORT}@localhost
EOL

    # Create required files
    echo -e "${BLUE}${BOLD}Creating required files...${NC}"

    if [ ! -f /etc/opendkim/KeyTable ]; then
        touch /etc/opendkim/KeyTable
    else
        backup_file /etc/opendkim/KeyTable
        rm -rf /etc/opendkim/KeyTable
    fi

    if [ ! -f /etc/opendkim/SigningTable ]; then
        touch /etc/opendkim/SigningTable
    else
        backup_file /etc/opendkim/SigningTable
        rm -rf /etc/opendkim/SigningTable
    fi

    if [ ! -f /etc/opendkim/TrustedHosts ];then
        touch /etc/opendkim/TrustedHosts
    else
        backup_file /etc/opendkim/TrustedHosts
        rm -rf /etc/opendkim/TrustedHosts
    fi

    if [ ! -f /etc/opendkim/KeyTable ];then
        echo "${SELECTOR}._domainkey.${BASE_DOMAIN} ${BASE_DOMAIN}:${SELECTOR}:/etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key" > /etc/opendkim/KeyTable
    fi

    if [ ! -f /etc/opendkim/SigningTable ];then
        if [ "$WILDCARD" = true ]; then
            echo "*@*.${BASE_DOMAIN} ${SELECTOR}._domainkey.${BASE_DOMAIN}" > /etc/opendkim/SigningTable
            echo "*@${BASE_DOMAIN} ${SELECTOR}._domainkey.${BASE_DOMAIN}" >> /etc/opendkim/SigningTable
        else
            echo "*@${BASE_DOMAIN} ${SELECTOR}._domainkey.${BASE_DOMAIN}" > /etc/opendkim/SigningTable
        fi
    fi

    if [ ! -f /etc/opendkim/TrustedHosts ];then
        echo "127.0.0.1
localhost
${BASE_DOMAIN}
*.${BASE_DOMAIN}" > /etc/opendkim/TrustedHosts
        echo "$(curl -s ifconfig.me)" >> /etc/opendkim/TrustedHosts
    fi
fi

# Configure mail service
configure_sendmail() {
    echo -e "${BLUE}${BOLD}Configuring Sendmail...${NC}"
    backup_file /etc/mail/sendmail.mc
    if ! grep -q "INPUT_MAIL_FILTER(\`opendkim', \`S=inet:${OPENDKIM_PORT}@localhost')" /etc/mail/sendmail.mc;then
        cat > /etc/mail/sendmail.mc <<EOL
divert(-1)dnl
include(\`/usr/share/sendmail-cf/m4/cf.m4')dnl
VERSIONID(\`setup for Red Hat Linux')dnl
OSTYPE(\`linux')dnl
define(\`confDEF_USER_ID',\`8:12')dnl
define(\`confTO_CONNECT', \`1m')dnl
define(\`confTRY_NULL_MX_LIST', \`true')dnl
define(\`confDONT_PROBE_INTERFACES', \`true')dnl
define(\`PROCMAIL_MAILER_PATH',\`/usr/bin/procmail')dnl
define(\`ALIAS_FILE', \`/etc/aliases')dnl
define(\`STATUS_FILE', \`/var/log/mail/statistics')dnl
define(\`UUCP_MAILER_MAX', \`2000000')dnl
define(\`confUSERDB_SPEC', \`/etc/mail/userdb.db')dnl
define(\`confPRIVACY_FLAGS', \`authwarnings,novrfy,noexpn,restrictqrun')dnl
define(\`confAUTH_OPTIONS', \`A')dnl
TRUST_AUTH_MECH(\`EXTERNAL DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
define(\`confAUTH_MECHANISMS', \`EXTERNAL GSSAPI DIGEST-MD5 CRAM-MD5 LOGIN PLAIN')dnl
FEATURE(\`no_default_msa')dnl
FEATURE(\`smrsh',\`/usr/sbin/smrsh')dnl
FEATURE(\`mailertable',\`hash -o /etc/mail/mailertable.db')dnl
FEATURE(\`virtusertable',\`hash -o /etc/mail/virtusertable.db')dnl
FEATURE(\`genericstable',\`hash -o /etc/mail/genericstable.db')dnl
FEATURE(\`relay_based_on_MX')dnl
FEATURE(\`access_db',\`hash -T<TMPF> /etc/mail/access')dnl
FEATURE(\`blocklist_recipients')dnl
EXPOSED_USER(\`root')dnl
DAEMON_OPTIONS(\`Port=smtp,Addr=127.0.0.1, Name=MTA')dnl
FEATURE(\`accept_unresolvable_domains')dnl
LOCAL_DOMAIN(\`localhost.localdomain')dnl
MAILER(local)dnl
MAILER(smtp)dnl
INPUT_MAIL_FILTER(\`opendkim', \`S=inet:${OPENDKIM_PORT}@localhost')dnl
EOL

        m4 /etc/mail/sendmail.mc > /etc/mail/sendmail.cf
    else
        echo -e "${GREEN}${BOLD}Sendmail already configured with OpenDKIM. Skipping configuration.${NC}"
    fi
    systemctl restart sendmail
}

configure_postfix() {
    echo -e "${BLUE}${BOLD}Configuring Postfix...${NC}"
    backup_file /etc/postfix/main.cf
    if ! postconf -n | grep -q "inet:localhost:${OPENDKIM_PORT}";then
        postconf -e "milter_default_action = accept"
        postconf -e "milter_protocol = 6"
        postconf -e "smtpd_milters = inet:localhost:${OPENDKIM_PORT}"
        postconf -e "non_smtpd_milters = inet:localhost:${OPENDKIM_PORT}"
    else
        echo -e "${GREEN}${BOLD}Postfix already configured with OpenDKIM. Skipping configuration.${NC}"
    fi
    systemctl restart postfix
}

extract_dkim_key() {
  local file_path="$1"
  local key=""

  # Read the file line by line
  while IFS= read -r line
  do
    # Check if the line contains a part of the key and remove unnecessary characters
    if [[ $line =~ p= || $line =~ ^[[:space:]] ]]; then
      key+=$(echo $line | sed 's/.*p=//;s/"//g;s/)//g')
    fi
  done < "$file_path"

  # Remove extra spaces
  key=$(echo $key | tr -d '[:space:]')

  # Remove content starting from the semicolon
  key=${key%%;*}

  # Return the key content
  echo "$key"
}

# Apply mail service configuration
if [ "$MAIL_SERVICE" = "sendmail" ];then
    configure_sendmail || { echo -e "${RED}${BOLD}Failed to configure sendmail. Check the logs for more details.${NC}"; exit 1; }
elif [ "$MAIL_SERVICE" = "postfix" ];then
    configure_postfix || { echo -e "${RED}${BOLD}Failed to configure postfix. Check the logs for more details.${NC}"; exit 1; }
fi

# Restart OpenDKIM
echo -e "${BLUE}${BOLD}Restarting OpenDKIM...${NC}"
systemctl restart opendkim

if ! systemctl is-active --quiet opendkim; then
    echo -e "${RED}${BOLD}Failed to start opendkim service. Please check the system logs.${NC}"
    exit 1
fi

# Extract DKIM public key for DNS record
if [ "$IMPORT" = true ]; then
    if [[ "$PRIVATE_KEY_PATH" =~ \.tar\.gz$ ]]; then
        # DKIM_PUBLIC_KEY=$(grep -o 'p=.*' /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt | sed 's/.*p=//' | tr -d '"\n' | tr -d ' ')
        DKIM_PUBLIC_KEY=$(extract_dkim_key "/etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt")
    else
        # DKIM_PUBLIC_KEY=$(grep -o 'p=.*' ${PUBLIC_KEY_PATH} | sed 's/.*p=//' | tr -d '"\n' | tr -d ' ')
        DKIM_PUBLIC_KEY=$(extract_dkim_key $PUBLIC_KEY_PATH)
    fi
else
    # DKIM_PUBLIC_KEY=$(grep -o 'p=.*' /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt | sed 's/.*p=//' | tr -d '"\n' | tr -d ' ')
    DKIM_PUBLIC_KEY=$(extract_dkim_key "/etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt")
fi

# Function to add DNS record to Cloudflare
add_dns_record() {
    local record_name=$1
    local record_type=$2
    local record_content=$3
    local domain=$4

    local zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${domain}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    local existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=${record_type}&name=${record_name}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ "$existing_record" != "null" ];then
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${existing_record}" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${record_content}\",\"ttl\":3600,\"proxied\":false}"
    else
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${record_content}\",\"ttl\":3600,\"proxied\":false}"
    fi
}

# Add DNS records to Cloudflare if API token is provided
echo
if [ -n "${CF_API_TOKEN}" ];then
    echo -e "${BLUE}${BOLD}Adding DKIM record to Cloudflare...${NC}"
    add_dns_record "${SELECTOR}._domainkey.${BASE_DOMAIN}" "TXT" "v=DKIM1; k=rsa; p=${DKIM_PUBLIC_KEY}" "${BASE_DOMAIN}"

    echo
    echo
    echo -e "${BLUE}${BOLD}Adding SPF record to Cloudflare...${NC}"
    add_dns_record "${BASE_DOMAIN}" "TXT" "v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all" "${BASE_DOMAIN}"

    echo
    echo
    echo -e "${BLUE}${BOLD}Adding DMARC record to Cloudflare...${NC}"
    add_dns_record "_dmarc.${BASE_DOMAIN}" "TXT" "v=DMARC1; p=none; rua=mailto:dmarc-reports@${BASE_DOMAIN}" "${BASE_DOMAIN}"

    # Add DMARC and MX records for the server hostname to Cloudflare
    echo
    echo -e "${BLUE}${BOLD}Adding DMARC record for server hostname to Cloudflare...${NC}"
    add_dns_record "_dmarc.${SERVER_HOSTNAME}" "TXT" "v=DMARC1; p=none; rua=mailto:dmarc-reports@${SERVER_HOSTNAME}" "${BASE_DOMAIN}"

    echo
    echo
    echo -e "${BLUE}${BOLD}Adding MX record for server hostname to Cloudflare...${NC}"
    add_dns_record "${SERVER_HOSTNAME}" "MX" "10 mail.${BASE_DOMAIN}" "${BASE_DOMAIN}"

    # Add SPF records for the server hostname to Cloudflare
    echo
    echo -e "${BLUE}${BOLD}Adding SPF record for server hostname to Cloudflare...${NC}"
    add_dns_record "${SERVER_HOSTNAME}" "TXT" "v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all" "${BASE_DOMAIN}"

    echo
    echo
    echo -e "${GREEN}${BOLD}DKIM setup is complete. DNS records have been added to Cloudflare.${NC}"
else
    echo
    echo -e "${GREEN}${BOLD}DKIM setup is complete. Please add the following DNS records to your domain manually:${NC}"
    echo
    echo -e "${BOLD}DKIM record:${NC}"
    echo "${SELECTOR}._domainkey.${BASE_DOMAIN} IN TXT \"v=DKIM1; k=rsa; p=${DKIM_PUBLIC_KEY}\""
    echo
    echo -e "${BOLD}Suggested SPF record:${NC}"
    echo "${BASE_DOMAIN} IN TXT \"v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all\""
    echo
    echo -e "${BOLD}Suggested DMARC record:${NC}"
    echo "_dmarc.${BASE_DOMAIN} IN TXT \"v=DMARC1; p=none; rua=mailto:dmarc-reports@${BASE_DOMAIN}\""
    echo
    echo -e "${BOLD}DMARC record for server hostname (${SERVER_HOSTNAME}):${NC}"
    echo "_dmarc.${SERVER_HOSTNAME} IN TXT \"v=DMARC1; p=none; rua=mailto:dmarc-reports@${SERVER_HOSTNAME}\""
    echo
    echo -e "${BOLD}Suggested DMARC record for all websites hosted on this server:${NC}"
    echo "_dmarc.<your-domain> IN TXT \"v=DMARC1; p=none; rua=mailto:dmarc-reports@<your-domain>\""
    echo
    echo -e "${BOLD}MX record for server hostname (${SERVER_HOSTNAME}):${NC}"
    echo "${SERVER_HOSTNAME} IN MX 10 mail.${BASE_DOMAIN}"
    echo
    echo -e "${BOLD}Suggested MX record for all websites hosted on this server:${NC}"
    echo "<your-domain> IN MX 10 mail.${BASE_DOMAIN}"
    echo
    echo -e "${BOLD}SPF record for server hostname (${SERVER_HOSTNAME}):${NC}"
    echo "${SERVER_HOSTNAME} IN TXT \"v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all\""
    echo
    echo -e "${BOLD}Suggested SPF record for all websites hosted on this server:${NC}"
    echo "<your-domain> IN TXT \"v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all\""
fi

# Display the locations of the DKIM keys
echo
echo
echo "------------------------------------------------------------------------------------------------"
echo -e "${BOLD}DKIM private key location\t:${NC} /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key"
echo -e "${BOLD}DKIM public key location\t:${NC} /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt"
echo "------------------------------------------------------------------------------------------------"
echo
echo -e "${GREEN}${BOLD}All configurations are complete. The DKIM setup is shared across all subdomains of ${BASE_DOMAIN}.${NC}"

if [ "$EXPORT" = true ];then
    echo
    echo
    echo "------------------------------------------------------------------------------------------------"
    if [ "$KEYS_ONLY" = false ];then
        echo -e "${GREEN}${BOLD}Exported archive file\t\t: ${ARCHIVE_PATH}${NC}"
    fi
    echo "------------------------------------------------------------------------------------------------"
fi
