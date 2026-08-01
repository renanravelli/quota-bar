#!/bin/bash
set -euo pipefail

APP_PATH="${1:-${BUILT_PRODUCTS_DIR:-}/${WRAPPER_NAME:-}}"
CONFIG="${2:-${CONFIGURATION:-Release}}"
MODE_ARGUMENT="${3:-}"
EXPECTED_ARCHS="arm64"

TEST_HOST_INJECTED_KEYS='com.apple.security.temporary-exception.files.absolute-path.read-only
com.apple.security.temporary-exception.mach-lookup.global-name'

case "$MODE_ARGUMENT" in
  release|debug|test-host)
    MODE="$MODE_ARGUMENT"
    ;;
  "")
    if [ "$CONFIG" = "Debug" ]; then MODE="debug"; else MODE="release"; fi
    ;;
  *)
    echo "error: modo '$MODE_ARGUMENT' desconhecido; use 'release', 'debug' ou 'test-host'"
    exit 1
    ;;
esac

expected_entitlements() {
  case "$MODE" in
    release)
      cat <<'PLIST'
<plist version="1.0">
<dict/>
</plist>
PLIST
      ;;
    debug)
      cat <<'PLIST'
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
</dict>
</plist>
PLIST
      ;;
    test-host)
      cat <<'PLIST'
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
  <key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>
  <array>
    <string>/</string>
  </array>
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
  <array>
    <string>com.apple.testmanagerd</string>
    <string>com.apple.dt.testmanagerd.runner</string>
    <string>com.apple.coresymbolicationd</string>
  </array>
</dict>
</plist>
PLIST
      ;;
  esac
}

if [ ! -d "$APP_PATH" ]; then
  echo "error: nenhum produto assinado em '$APP_PATH'"
  exit 1
fi

if ! codesign -dv "$APP_PATH" 2>/dev/null; then
  echo "error: '$APP_PATH' não está assinado; o portão não pode ser aplicado"
  exit 1
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
binary="$APP_PATH/Contents/MacOS/$executable_name"

if [ ! -f "$binary" ]; then
  echo "error: executável não encontrado em '$binary'"
  exit 1
fi

present_archs="$(lipo -archs "$binary" | tr ' ' '\n' | sed '/^$/d' | sort -u | paste -sd' ' -)"

if [ "$present_archs" != "$EXPECTED_ARCHS" ]; then
  echo "error: o binário assinado tem arquitetura '$present_archs', e o esperado é exatamente '$EXPECTED_ARCHS' (ADR-006)"
  echo "error: fatia adicional é suporte que ninguém consegue testar neste projeto"
  exit 1
fi

if [ "$MODE" = "release" ]; then
  fixture_symbols="$(nm -U "$binary" 2>/dev/null | grep -c 'QuotaBarCoreFixtures' || true)"
  if [ "${fixture_symbols:-0}" -ne 0 ]; then
    echo "error: o binário '$CONFIG' contém $fixture_symbols símbolo(s) de QuotaBarCoreFixtures"
    echo "error: artefato de desenvolvimento não pode ser distribuído (ADR-006)"
    exit 1
  fi
fi

brand_pattern='anthropic|claude'
art_extensions='png|jpg|jpeg|gif|svg|pdf|icns|heic|tiff|webp'

APPROVED_ASSETS='QuotaBarSymbolNormalStandard
QuotaBarSymbolNormalContingency
QuotaBarSymbolAttentionStandard
QuotaBarSymbolAttentionContingency
QuotaBarSymbolCriticalStandard
QuotaBarSymbolCriticalContingency
QuotaBarSymbolExhaustedStandard
QuotaBarSymbolExhaustedContingency
MascotNormal
MascotAttention
MascotCritical
MascotExhausted
MascotNoValue'

repository_art="$(
  find "${SRCROOT:-.}" \
    \( -name build -o -name .git -o -name .build -o -name DerivedData -o -name '*.xcodeproj' \) -prune \
    -o -type f -print 2>/dev/null \
    | grep -iE "\.($art_extensions)$" || true
)"

# O padrão vale sobre o nome do arquivo, não sobre o caminho: o repositório pode
# viver sob um diretório cujo nome contenha a marca sem que a arte a cite.
brand_named_art="$(printf '%s\n' "$repository_art" | while IFS= read -r path; do
  [ -n "$path" ] || continue
  basename "$path" | grep -qiE "$brand_pattern" && printf '%s\n' "$path"
done || true)"
if [ -n "$brand_named_art" ]; then
  echo "error: arquivo de arte com nome de marca de terceiro no repositório (ADR-007):"
  printf 'error:   %s\n' $brand_named_art
  exit 1
fi

if [ "$MODE" = "release" ]; then
  bundled_art="$(find "$APP_PATH" -type f 2>/dev/null | grep -iE "\.($art_extensions)$" || true)"
  if [ -n "$bundled_art" ]; then
    echo "error: o bundle '$CONFIG' contém arte fora do conjunto aprovado (REQ-20):"
    printf 'error:   %s\n' $bundled_art
    exit 1
  fi

  catalog="$APP_PATH/Contents/Resources/Assets.car"
  if [ -f "$catalog" ]; then
    catalog_names="$(xcrun --sdk macosx assetutil --info "$catalog" 2>/dev/null \
      | grep -oE '"Name" : "[^"]*"' | sed -e 's/"Name" : "//' -e 's/"$//' | sort -u || true)"
    unapproved="$(printf '%s\n' "$catalog_names" \
      | grep -vE '^$' \
      | grep -vE '^ZZZZPackedAsset-' \
      | grep -v -x -F -f <(printf '%s\n' "$APPROVED_ASSETS") || true)"
    if [ -n "$unapproved" ]; then
      echo "error: o catálogo de recursos de '$CONFIG' contém entradas fora do conjunto aprovado (REQ-20):"
      printf 'error:   %s\n' $unapproved
      echo "error: catálogo de recursos não sofre dead-stripping; tudo que entra é distribuído"
      exit 1
    fi
  fi
fi

signed_entitlements="$(codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null || true)"
if [ -z "$signed_entitlements" ]; then
  signed_entitlements='<plist version="1.0"><dict/></plist>'
fi

if ! signed_plist="$(printf '%s\n' "$signed_entitlements" | plutil -convert xml1 -o - - 2>/dev/null)"; then
  echo "error: os direitos de '$APP_PATH' não são um plist legível; o portão não pode ser aplicado"
  exit 1
fi

if ! expected_plist="$(expected_entitlements | plutil -convert xml1 -o - - 2>/dev/null)"; then
  echo "error: o conjunto esperado do modo '$MODE' não é um plist válido; corrija o portão"
  exit 1
fi

if [ "$MODE" = "debug" ]; then
  injected_by_test=""
  while IFS= read -r key; do
    if printf '%s\n' "$signed_plist" | grep -qF "<key>$key</key>"; then
      injected_by_test="${injected_by_test}${key}"$'\n'
    fi
  done <<< "$TEST_HOST_INJECTED_KEYS"

  if [ -n "$injected_by_test" ]; then
    echo "error: este produto veio de uma build de teste, e traz direitos que o Xcode injeta no host de teste:"
    printf 'error:   %s\n' $injected_by_test
    echo "error: reconstrua com a ação de build, ou confira em modo 'test-host' (ADR-006)"
    exit 1
  fi
fi

if [ "$signed_plist" != "$expected_plist" ]; then
  echo "error: o conjunto de direitos do produto não é o esperado no modo '$MODE' (ADR-006):"
  diff -u --label esperado --label assinado \
    <(printf '%s\n' "$expected_plist") <(printf '%s\n' "$signed_plist") \
    | sed 's/^/error:   /' || true
  echo "error: a comparação é do plist inteiro — chaves e valores, em qualquer direção"
  exit 1
fi

echo "Portão: modo $MODE, arquitetura $present_archs e conjunto de direitos exatamente o esperado."
