#!/bin/sh

#Generate SSL private certs

echodo()
{
    echo "${@}"
    (${@})
}

yearmon()
{
    date '+%Y%m%d'
}

fqdn()
{
    (nslookup ${1} 2>&1 || echo Name ${1}) \
        | tail -3 | grep Name | sed -e 's,.*e:[ \t]*,,'
}

C=
ST=
L=
O=Company
OU=Department
HOST=${1:-`hostname`}
DATE=`yearmon`
#CN=`fqdn $HOST`
CN=$HOST

#csr="${HOST}.csr"
#key="${HOST}.key"
#cert="${HOST}.cert"
path="/etc/ssl/web"
csr="ca.csr"
key="ca.key"
cert="ca.crt"


mkdir -p $path
cd $path
openssl dhparam -out ${path}/dhparam.pem 2048

openssl genrsa -out ${path}/ca.key 2048


# Create the certificate signing request
#openssl req -config /etc/pki/tls/openssl.cnf -new -passin pass:password -passout pass:password -out $csr <<EOF
openssl req -new -key ${path}/${key} -out ${path}/${csr} <<EOF
${C}
${ST}
${L}
${O}
${OU}
${CN}
$USER@${CN}
.
.
EOF
echo ""

[ -f ${path}/${csr} ] && echodo openssl req -text -noout -in ${path}/${csr}
echo ""

# Create the Key
#openssl rsa -in ${path}/privkey.pem -passin pass:password -passout pass:password -out ${path}/${key}

# Create the Certificate
openssl x509 -in ${path}/${csr} -out ${path}/${cert} -req -signkey ${path}/${key} -days 3650
