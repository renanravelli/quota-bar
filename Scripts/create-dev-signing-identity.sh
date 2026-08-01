#!/bin/bash
set -euo pipefail

# Certificado autoassinado estável para desenvolvimento.
#
# A ACL de um item de Keychain é amarrada ao Designated Requirement do processo
# que gravou. Assinatura ad-hoc muda o hash a cada recompilação, invalidando a
# ACL a cada build. Uma identidade constante entre builds elimina o problema.
#
# Dois passos exigem autorização interativa e NÃO podem ser automatizados:
# marcar a confiança de assinatura de código e liberar a chave para o codesign.
# Os dois pedem a senha de login e são executados por este script; nenhum deles
# é contornado.
#
# Uso:
#   Scripts/create-dev-signing-identity.sh
#
# Depois, para que a build local use a identidade:
#   export QUOTABAR_CODE_SIGN_IDENTITY="QuotaBar Development"
#   xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -configuration Debug build

IDENTITY_NAME="${QUOTABAR_CODE_SIGN_IDENTITY:-QuotaBar Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
VALIDITY_DAYS=3650

if security find-identity -v -p codesigning | grep -qF "$IDENTITY_NAME"; then
  echo "Identidade '$IDENTITY_NAME' já existe e é válida para assinatura de código."
  exit 0
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -days "$VALIDITY_DAYS" -nodes \
  -keyout "$workdir/key.pem" \
  -out "$workdir/cert.pem" \
  -subj "/CN=$IDENTITY_NAME/O=QuotaBar/C=BR" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Os algoritmos são fixados porque o OpenSSL 3 passou a exportar PKCS#12 com
# AES-256-CBC e MAC SHA-256, que o Security framework não verifica — o erro que
# ele reporta é "MAC verification failed (wrong password?)", com a senha certa.
openssl pkcs12 -export \
  -inkey "$workdir/key.pem" \
  -in "$workdir/cert.pem" \
  -name "$IDENTITY_NAME" \
  -out "$workdir/identity.p12" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout pass:quotabar

security import "$workdir/identity.p12" -k "$KEYCHAIN" -P quotabar \
  -T /usr/bin/codesign -T /usr/bin/security

echo "Autorize a confiança de assinatura de código quando o sistema pedir a senha de login."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$workdir/cert.pem"

echo "Autorize o acesso do codesign à chave privada quando o sistema pedir a senha de login."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null

security find-identity -v -p codesigning | grep -F "$IDENTITY_NAME"
