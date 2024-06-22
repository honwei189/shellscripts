#!/bin/bash

# setup_mail_security.sh
#
# Purpose:
# This script configures DKIM, SPF, and DMARC for a specified domain on a server running either Sendmail or Postfix,
# ensuring that emails sent from the domain are authenticated and meet modern email security standards.
# If a Cloudflare API token is provided, it will automatically add the necessary DNS records.
#
# Usage:
# ./setup_mail_security.sh -d <domain> -s <selector> [-t <cloudflare_api_token>]
# 
# Parameters:
# -d <domain>             : The base domain name (e.g., yourdomain.com)
# -s <selector>           : DKIM selector (e.g., default)
# -t <cloudflare_api_token> : (Optional) Cloudflare API token for automatically adding DNS records
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
# 1. Install Necessary Packages: Ensures that required packages (epel-release, opendkim, opendkim-tools, jq, curl) are installed.
# 2. Detect Mail Service: Checks if sendmail or postfix is installed. If neither is found, it installs sendmail.
# 3. Generate DKIM Keys: Generates DKIM keys if they do not already exist.
# 4. Configure OpenDKIM: Creates and populates the OpenDKIM configuration file and required tables.
# 5. Configure Mail Service: Configures sendmail or postfix to use OpenDKIM for signing emails.
# 6. Restart Services: Restarts OpenDKIM and the mail service to apply the configuration.
# 7. Add DNS Records: Extracts the DKIM public key and adds the necessary DKIM, SPF, and DMARC records to Cloudflare if an API token is provided,
#    or displays the records to be added manually.
# 8. Configure Firewall: Ensures necessary ports are open for mail services and OpenDKIM.

set -e

# Function to print usage
print_usage() {
    echo "Usage: $0 -d <domain> -s <selector> [-t <cloudflare_api_token>]"
    echo "  -d <domain>    : The base domain name (e.g., yourdomain.com)"
    echo "  -s <selector>  : DKIM selector (e.g., default)"
    echo "  -t <cloudflare_api_token> : (Optional) Cloudflare API token"
    exit 1
}

# Get parameters
while getopts ":d:s:t:" opt; do
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
        *)
            print_usage
            ;;
    esac
done

if [ -z "${BASE_DOMAIN}" ] || [ -z "${SELECTOR}" ]; then
    print_usage
fi

# Install necessary packages
echo "Installing necessary packages..."
yum install -y epel-release
yum install -y opendkim opendkim-tools jq curl

# Detect and install mail service if not present
MAIL_SERVICE=""
if command -v sendmail &> /dev/null; then
    MAIL_SERVICE="sendmail"
elif command -v postfix &> /dev/null; then
    MAIL_SERVICE="postfix"
else
    # Default to sendmail if no mail service is installed
    yum install -y sendmail sendmail-cf
    MAIL_SERVICE="sendmail"
fi

echo "Mail service detected: $MAIL_SERVICE"

# Configure firewall to open necessary ports
echo "Configuring firewall..."
sudo firewall-cmd --permanent --add-port=25/tcp
sudo firewall-cmd --permanent --add-port=587/tcp
sudo firewall-cmd --permanent --add-port=8891/tcp
sudo firewall-cmd --reload

# Generate DKIM keys if they do not exist
if [ ! -f /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.private ]; then
    echo "Generating DKIM keys..."
    mkdir -p /etc/opendkim/keys/${BASE_DOMAIN}
    opendkim-genkey -b 2048 -d ${BASE_DOMAIN} -D /etc/opendkim/keys/${BASE_DOMAIN} -s ${SELECTOR} -v
    chown -R opendkim:opendkim /etc/opendkim/keys/${BASE_DOMAIN}
    mv /etc/opendkim/keys/${BASE_DOMAIN}/${SELECTOR}.private /etc/opendkim/keys/${BASE_DOMAIN}/dkim_private.key
else
    echo "DKIM keys already exist. Skipping generation."
fi

# Configure OpenDKIM
echo "Configuring OpenDKIM..."
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
Socket                  inet:8891@localhost
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
    if ! grep -q 'INPUT_MAIL_FILTER(`opendkim' /etc/mail/sendmail.mc; then
        yum install -y sendmail sendmail-cf
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
INPUT_MAIL_FILTER(\`opendkim', \`S=inet:8891@localhost')dnl
EOL

        m4 /etc/mail/sendmail.mc > /etc/mail/sendmail.cf
    else
        echo "Sendmail already configured with OpenDKIM. Skipping configuration."
    fi
    systemctl restart sendmail
}

configure_postfix() {
    echo "Configuring Postfix..."
    if ! postconf -n | grep -q "inet:localhost:8891"; then
        postconf -e "milter_default_action = accept"
        postconf -e "milter_protocol = 6"
        postconf -e "smtpd_milters = inet:localhost:8891"
        postconf -e "non_smtpd_milters = inet:localhost:8891"
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

echo "All configurations are complete. The DKIM setup is shared across all subdomains of ${BASE_DOMAIN}."
