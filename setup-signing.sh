#!/bin/zsh
# One-time: create a stable self-signed codesigning certificate ("wac-dev-sign").
# Signing wac.app with a STABLE identity means macOS permission grants
# (Screen Recording, Microphone) survive rebuilds. Ad-hoc signatures change
# on every build, which made TCC re-ask each time.
set -e

CERT_NAME="wac-dev-sign"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Signing identity '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Generating self-signed codesigning certificate '$CERT_NAME'..."
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

# -legacy: macOS keychain can't read OpenSSL 3's default PKCS12 encryption
openssl pkcs12 -export -legacy -out "$TMP/cert.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -passout pass:wac-temp

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P wac-temp -T /usr/bin/codesign

echo "Trusting the certificate for code signing (macOS may ask for your password once)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Done. Verify with: security find-identity -v -p codesigning"
