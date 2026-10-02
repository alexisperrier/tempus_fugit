#!/bin/bash
# One-time: create a self-signed "TimeTrack Dev" code-signing identity in the
# login keychain. Signing every build with the same identity keeps macOS
# Accessibility / Automation grants across rebuilds (ad-hoc signatures change
# on every build, which silently invalidates the grant).
set -euo pipefail

NAME="${SIGN_IDENTITY:-TimeTrack Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "\"${NAME}\""; then
    echo "==> '${NAME}' already exists"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

echo "==> Creating certificate '${NAME}'"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" -config "${TMP}/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -name "${NAME}" -out "${TMP}/identity.p12" -passout pass:timetrack

echo "==> Importing into login keychain (codesign allowed to use the key)"
security import "${TMP}/identity.p12" -k "${KEYCHAIN}" -P timetrack -T /usr/bin/codesign

security find-identity -p codesigning "${KEYCHAIN}" | grep "\"${NAME}\""
echo "==> Done. Run 'make menu-restart', then grant Accessibility once more."
