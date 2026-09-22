#!/bin/bash
# Run only after explicitly approving creation/import of a local signing identity.
set -euo pipefail
identity="XFrame Local Development"
keychain_path="$(security default-keychain -d user | tr -d '\"' | sed 's/^[[:space:]]*//')"
if security find-certificate -c "$identity" "$keychain_path" >/dev/null 2>&1; then
    echo "The XFrame development certificate already exists. No changes made."
    exit 0
fi
umask 077
signing_temp="$(mktemp -d /private/tmp/xframe-signing.XXXXXX)"
trap 'rm -f "$signing_temp/key.pem" "$signing_temp/cert.pem" "$signing_temp/identity.p12"; rmdir "$signing_temp"' EXIT
openssl req -x509 -newkey rsa:3072 -noenc -days 3650 \
    -subj "/CN=$identity/" \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$signing_temp/key.pem" -out "$signing_temp/cert.pem" 2>/dev/null
export XFRAME_PKCS12_PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 -export -inkey "$signing_temp/key.pem" -in "$signing_temp/cert.pem" \
    -name "$identity" -out "$signing_temp/identity.p12" -passout env:XFRAME_PKCS12_PASSWORD \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
# Only codesign is pre-authorized; do not grant all applications key access.
security import "$signing_temp/identity.p12" -k "$keychain_path" -P "$XFRAME_PKCS12_PASSWORD" -T /usr/bin/codesign
unset XFRAME_PKCS12_PASSWORD
echo "Imported $identity into the user Keychain. System trust settings were not changed."
