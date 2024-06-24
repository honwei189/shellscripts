#!/bin/bash

# setup-mail-security.sh
#
# Purpose:
# This script configures DKIM, SPF, and DMARC for a specified domain on a server running either Sendmail or Postfix,
# ensuring that emails sent from the domain are authenticated and meet modern email security standards.
# If a Cloudflare API token is provided, it will automatically add the necessary DNS records.
#
# Usage:
# ./setup-mail-security.sh -d <domain> -s <selector> [-t <cloudflare_api_token>] [-p <ports>] [-f <on|off>]
# 
# Parameters:
# -d <domain>             : The base domain name (e.g., yourdomain.com or sub.yourdomain.com)
# -s <selector>           : DKIM selector (e.g., default or mysub)
# -t <cloudflare_api_token> : (Optional) Cloudflare API token for automatically adding DNS records
# -p <ports>              : (Optional) Comma-separated list of ports to open (e.g., 25,587)
# -f <on|off>             : (Optional) Enable or disable firewall configuration (default: off)
#
# Supported Mail Servers:
# This script supports the following mail servers:
# - Sendmail
# - Postfix
# If neither is found on the server, Sendmail will be installed by default.
# 
# Note:
# Other mail servers such as Exim and qmail are not supported by this script. 
# Additional modifications would be needed to support those mail servers.
#
# Steps:
# 1. Check and Install Necessary Packages: Ensures that required packages (epel-release, opendkim, opendkim-tools, jq, curl) are installed if not already present.
# 2. Detect Mail Service: Checks if sendmail or postfix is installed. If neither is found, it installs sendmail.
# 3. Generate or Regenerate DKIM Keys: Generates or regenerates DKIM keys.
# 4. Configure OpenDKIM: Creates and populates the OpenDKIM configuration file and required tables.
# 5. Configure Mail Service: Configures sendmail or postfix to use OpenDKIM for signing emails.
# 6. Restart Services: Restarts OpenDKIM and the mail service to apply the configuration.
# 7. Add DNS Records: Extracts the DKIM public key and adds the necessary DKIM, SPF, and DMARC records to Cloudflare if an API token is provided,
#    or displays the records to be added manually.
# 8. Configure Firewall: Ensures necessary ports are open for mail services and OpenDKIM.
# 9. Rollback Changes: In case of failure, revert the changes to the previous state.
# 10. Display Key Locations: Shows the paths to the generated DKIM private and public key files.

set -e

# Configurable variables
OPENDKIM_PORT=8891
DEFAULT_PORTS="25,587"
DEFAULT_FIREWALL="off"

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
    if [ -f "$file.bak" ]; then
        mv "$file.bak" "$file"
    fi
}

# Function to print usage
print_usage() {
    echo "Usage: $0 -d <domain> -s <selector> [-t <cloudflare_api_token>] [-p <ports>] [-f <on|off>]"
    echo "  -d <domain>    : The base domain name (e.g., yourdomain.com or sub.yourdomain.com)"
    echo "  -s <selector>  : DKIM selector (e.g., default or mysub)"
    echo "  -t <cloudflare_api_token> : (Optional) Cloudflare API token"
    echo "  -p <ports>     : (Optional) Comma-separated list of ports to open (e.g., 25,587)"
    echo "  -f <on|off>    : (Optional) Enable or disable firewall configuration (default: off)"
    exit 1
}

# Rollback function to restore configurations in case of failure
rollback() {
    echo "Rolling back changes..."
    restore_file /etc/opendkim.conf
    restore_file /etc/mail/sendmail.mc
    restore_file /etc/postfix/main.cf
    systemctl restart sendmail || true
    systemctl restart postfix || true
    systemctl restart opendkim || true
    echo "Rollback completed."
}

# Trap any error and initiate rollback
trap 'rollback' ERR

# Get parameters
while getopts ":d:s:t:p:f:" opt; do
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
        *)
            print_usage
            ;;
    esac
done

if [ -z "${BASE_DOMAIN}" ] || [ -z "${SELECTOR}" ]; then
    print_usage
fi

# Use specified ports or default ports if not provided
if [ -z "${PORTS}" ]; then
    PORTS=${DEFAULT_PORTS}
fi

# Use specified firewall setting or default setting if not provided
if [ -z "${FIREWALL}" ]; then
    FIREWALL=${DEFAULT_FIREWALL}
fi

# Function to check and install necessary packages
install_package() {
    local package=$1
    if ! rpm -q $package &> /dev/null; then
        echo "Installing package: $package"
        yum install -y $package
    else
        echo "Package $package already installed"
    fi
}

# Install necessary packages
echo "Checking and installing necessary packages..."
install_package epel-release
install_package opendkim
install_package opendkim-tools
install_package jq
install_package curl

# Detect and install mail service if not present
MAIL_SERVICE=""
if command -v sendmail &> /dev/null; then
    MAIL_SERVICE="sendmail"
elif command -v postfix &> /dev/null; then
    MAIL_SERVICE="postfix"
else
    # Default to sendmail if no mail service is installed
    install_package sendmail
    install_package sendmail-cf
    MAIL_SERVICE="sendmail"
fi

echo "Mail service detected: $MAIL_SERVICE"

# Function to check if a firewall port is already open
is_port_open() {
    local port=$1
    firewall-cmd --list-ports | grep -q "${port}/tcp"
}

# Configure firewall to open necessary ports if firewall option is on
if [ "$FIREWALL" = "on" ]; then
    echo "Configuring firewall..."
    IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
    for port in "${PORT_ARRAY[@]}"; do
        if ! is_port_open $port; then
            firewall-cmd --permanent --add-port=${port}/tcp
        fi
    done
    firewall-cmd --reload
else
    echo "Firewall configuration skipped."
fi

# Generate or regenerate DKIM keys
echo "Generating or regenerating DKIM keys..."
mkdir -p /etc/opendkim/keys/${BASE_DOMAIN}
opendkim-genkey -b 2048 -d ${BASE_DOMAIN} -D /etc/opendkim/keys/${BASE_DOMAIN} -s ${SELECTOR} -v
chown -R opendkim:opendkim /etc/opendkim/keys/${BASE_DOMAIN}
mv /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.private /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key

# Configure OpenDKIM
echo "Configuring OpenDKIM..."
backup_file /etc/opendkim.conf
cat > /etc/opendkim.conf <<EOL
AutoRestart             Yes
AutoRestartRate         10/1h
Umask                   002
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/trusted.hosts
InternalHosts           refile:/etc/opendkim/trusted.hosts
KeyTable                refile:/etc/opendkim/key.table
SigningTable            refile:/etc/opendkim/signing.table
Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
Socket                  inet:${OPENDKIM_PORT}@localhost
EOL

# Create required files if they do not exist
echo "Creating required files..."
if [ ! -f /etc/opendkim/key.table ]; then
    echo "${SELECTOR}._domainkey.${BASE_DOMAIN} ${BASE_DOMAIN}:${SELECTOR}:/etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key" > /etc/opendkim/key.table
fi

if [ ! -f /etc/opendkim/signing.table ]; then
    echo "*@${BASE_DOMAIN} ${SELECTOR}._domainkey.${BASE_DOMAIN}" > /etc/opendkim/signing.table
fi

if [ ! -f /etc/opendkim/trusted.hosts ]; then
    echo "127.0.0.1
localhost
${BASE_DOMAIN}" > /etc/opendkim/trusted.hosts
fi

# Configure mail service
configure_sendmail() {
    echo "Configuring Sendmail..."
    backup_file /etc/mail/sendmail.mc
    if ! grep -q "INPUT_MAIL_FILTER(\`opendkim', \`S=inet:${OPENDKIM_PORT}@localhost')" /etc/mail/sendmail.mc; then
        install_package sendmail sendmail-cf
        cat > /etc/mail/sendmail.mc <<EOL
divert(-1)dnl
include(\`/usr/share/sendmail-cf/m4/cf.m4')dnl
VERSIONID(\`setup for Red Hat Linux')dnl
OSTYPE(\`linux')dnl
define(\`confDEF_USER_ID',\`8:12')dnl
define(\`confAUTO_REBUILD')dnl
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
FEATURE(\`blacklist_recipients')dnl
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
        echo "Sendmail already configured with OpenDKIM. Skipping configuration."
    fi
    systemctl restart sendmail
}

configure_postfix() {
    echo "Configuring Postfix..."
    backup_file /etc/postfix/main.cf
    if ! postconf -n | grep -q "inet:localhost:${OPENDKIM_PORT}"; then
        postconf -e "milter_default_action = accept"
        postconf -e "milter_protocol = 6"
        postconf -e "smtpd_milters = inet:localhost:${OPENDKIM_PORT}"
        postconf -e "non_smtpd_milters = inet:localhost:${OPENDKIM_PORT}"
    else
        echo "Postfix already configured with OpenDKIM. Skipping configuration."
    fi
    systemctl restart postfix
}

# Apply mail service configuration
if [ "$MAIL_SERVICE" = "sendmail" ]; then
    configure_sendmail || { echo "Failed to configure sendmail. Check the logs for more details."; exit 1; }
elif [ "$MAIL_SERVICE" = "postfix" ]; then
    configure_postfix || { echo "Failed to configure postfix. Check the logs for more details."; exit 1; }
fi

# Restart OpenDKIM
echo "Restarting OpenDKIM..."
systemctl restart opendkim

# Extract DKIM public key for DNS record
DKIM_PUBLIC_KEY=$(grep -o 'p=.*' /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt | cut -d'"' -f2)

# Function to add DNS record to Cloudflare
add_dns_record() {
    local record_name=$1
    local record_type=$2
    local record_content=$3

    local zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${BASE_DOMAIN}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    local existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=${record_type}&name=${record_name}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ "$existing_record" != "null" ]; then
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
if [ -n "${CF_API_TOKEN}" ]; then
    echo "Adding DKIM record to Cloudflare..."
    add_dns_record "${SELECTOR}._domainkey.${BASE_DOMAIN}" "TXT" "v=DKIM1; k=rsa; p=${DKIM_PUBLIC_KEY}"

    echo "Adding SPF record to Cloudflare..."
    add_dns_record "${BASE_DOMAIN}" "TXT" "v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all"

    echo "Adding DMARC record to Cloudflare..."
    add_dns_record "_dmarc.${BASE_DOMAIN}" "TXT" "v=DMARC1; p=none; rua=mailto:dmarc-reports@${BASE_DOMAIN}"

    echo "DKIM setup is complete. DNS records have been added to Cloudflare."
else
    echo "DKIM setup is complete. Please add the following DNS records to your domain manually:"
    echo
    echo "DKIM record:"
    echo "${SELECTOR}._domainkey.${BASE_DOMAIN} IN TXT \"v=DKIM1; k=rsa; p=${DKIM_PUBLIC_KEY}\""
    echo
    echo "Suggested SPF record:"
    echo "${BASE_DOMAIN} IN TXT \"v=spf1 a mx ip4:$(curl -s ifconfig.me) ~all\""
    echo
    echo "Suggested DMARC record:"
    echo "_dmarc.${BASE_DOMAIN} IN TXT \"v=DMARC1; p=none; rua=mailto:dmarc-reports@${BASE_DOMAIN}\""
fi

# Display the locations of the DKIM keys
echo "DKIM private key location: /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key"
echo "DKIM public key location: /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.txt"

echo "All configurations are complete. The DKIM setup is shared across all subdomains of ${BASE_DOMAIN}."
