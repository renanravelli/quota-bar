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
  echo "error: o binário assinado tem arquitetura '$present_archs', e o esperado é exatamente '$EXPECTED_ARCHS'"
  echo "error: fatia adicional é suporte que ninguém consegue testar neste projeto"
  exit 1
fi

if [ "$MODE" = "release" ]; then
  fixture_symbols="$(nm -U "$binary" 2>/dev/null | grep -c 'QuotaBarCoreFixtures' || true)"
  if [ "${fixture_symbols:-0}" -ne 0 ]; then
    echo "error: o binário '$CONFIG' contém $fixture_symbols símbolo(s) de QuotaBarCoreFixtures"
    echo "error: andaime de teste não pode viajar no produto distribuído"
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
  echo "error: arquivo de arte com nome de marca de terceiro no repositório:"
  printf 'error:   %s\n' $brand_named_art
  echo "error: o aplicativo distribuído não incorpora marca de terceiro em nenhuma superfície visual"
  exit 1
fi

SYMBOL_AVAILABILITY_DATABASE='/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist'
MINIMUM_MACOS='14.0'

symbol_sources="$(find "${SRCROOT:-.}"/App/Sources "${SRCROOT:-.}"/Packages/*/Sources \
  -type f -name '*.swift' 2>/dev/null || true)"

if [ -z "$symbol_sources" ]; then
  echo "error: nenhuma fonte Swift de produto encontrada a partir de '${SRCROOT:-.}'"
  echo "error: varredura sem nada para varrer não prova nada, e passar assim seria reprovar em silêncio"
  exit 1
fi

if [ ! -f "$SYMBOL_AVAILABILITY_DATABASE" ]; then
  echo "error: a base de disponibilidade de símbolos não está em '$SYMBOL_AVAILABILITY_DATABASE'"
  echo "error: sem ela não há como afirmar que um nome existe em macOS $MINIMUM_MACOS, e o portão reprova em vez de deixar passar"
  echo "error: se a base mudou de lugar ou de formato, conserte esta verificação ou fixe aqui os trens aceitos"
  exit 1
fi

train_releases="$(/usr/libexec/PlistBuddy -c 'Print :year_to_release' "$SYMBOL_AVAILABILITY_DATABASE" 2>/dev/null \
  | awk '/^ +[^ ]+ = Dict \{$/ { train = $1; next } /^ +macOS = / { print "train", train, $3 }' || true)"
symbol_trains="$(/usr/libexec/PlistBuddy -c 'Print :symbols' "$SYMBOL_AVAILABILITY_DATABASE" 2>/dev/null \
  | awk 'NF == 3 && $2 == "=" { print "symbol", $1, $3 }' || true)"

if [ -z "$train_releases" ] || [ -z "$symbol_trains" ]; then
  echo "error: a base em '$SYMBOL_AVAILABILITY_DATABASE' não tem o formato que esta verificação sabe ler"
  echo "error: o portão reprova em vez de deixar passar: verificação que se apaga sozinha devolve o defeito que ela existe para pegar"
  exit 1
fi

NON_SYMBOL_LITERALS=''

swift_literals() {
  printf '%s\n' "$symbol_sources" | tr '\n' '\0' | xargs -0 grep -hoE "$1" 2>/dev/null || true
}

locate_literal() {
  printf '%s\n' "$symbol_sources" | tr '\n' '\0' \
    | xargs -0 grep -nF "\"$1\"" 2>/dev/null | cut -d: -f1,2 | sed "s|^${SRCROOT:-.}/||" || true
}

used_names="$(swift_literals '"[^"]*"' | tr -d '"' | sort -u | awk 'NF == 1 { print "used", $1 }' || true)"
requested_names="$(swift_literals '(systemName|systemSymbolName|systemImage): *"[^"]+"' \
  | grep -oE '"[^"]+"' | tr -d '"' | sort -u | awk 'NF == 1 { print "requested", $1 }' || true)"

exempt_names="$(printf '%s\n' "$NON_SYMBOL_LITERALS" | awk 'NF == 1 { print "exempt", $1 }')"

symbol_verdict="$(printf '%s\n%s\n%s\n%s\n%s\n' \
  "$train_releases" "$symbol_trains" "$used_names" "$requested_names" "$exempt_names" \
  | awk -v minimum="$MINIMUM_MACOS" '
      function exceeds_minimum(version,   have, want, i) {
        split(version, have, "."); split(minimum, want, ".")
        for (i = 1; i <= 3; i++) {
          if ((have[i] + 0) > (want[i] + 0)) return 1
          if ((have[i] + 0) < (want[i] + 0)) return 0
        }
        return 0
      }
      $1 == "train" { release[$2] = $3; next }
      $1 == "symbol" { train[$2] = $3; next }
      $1 == "requested" { requested[$2] = 1; used[$2] = 1; next }
      $1 == "used" { used[$2] = 1; next }
      $1 == "exempt" { exempt[$2] = 1; next }
      END {
        for (name in used) {
          if (!(name in train)) continue
          if ((name in exempt) && !(name in requested)) continue
          checked++
          if (!(train[name] in release)) {
            print "untrained " name " — trem " train[name]
          } else if (exceeds_minimum(release[train[name]])) {
            print "too-new " name " — trem " train[name] ", exige macOS " release[train[name]]
          }
        }
        for (name in requested) if (!(name in train)) print "unknown " name
        print "checked " checked + 0
      }
    ')"

offenders_of_kind() {
  printf '%s\n' "$symbol_verdict" | awk -v kind="$1" '$1 == kind { $1 = ""; sub(/^ /, ""); print }'
}

too_new="$(offenders_of_kind too-new)"
if [ -n "$too_new" ]; then
  echo "error: nome de símbolo do sistema indisponível no alvo mínimo macOS $MINIMUM_MACOS:"
  printf '%s\n' "$too_new" | while IFS= read -r offender; do
    echo "error:   $offender"
    locate_literal "${offender%% *}" | sed 's/^/error:     /'
  done
  echo "error: o nome compila sem aviso e desenha o vazio no alvo mínimo"
  echo "error: a máquina que o introduz roda sistema mais novo, onde ele existe — o defeito não aparece para quem o criou"
  echo "error: se o literal apontado não é nome de símbolo, declare-o em NON_SYMBOL_LITERALS neste portão"
  exit 1
fi

untrained="$(offenders_of_kind untrained)"
if [ -n "$untrained" ]; then
  echo "error: símbolo cujo trem de lançamento não está mapeado para versão de macOS:"
  printf '%s\n' "$untrained" | sed 's/^/error:   /'
  echo "error: sem o mapeamento não se afirma disponibilidade, e o portão reprova em vez de supor"
  exit 1
fi

unknown="$(offenders_of_kind unknown)"
if [ -n "$unknown" ]; then
  echo "error: nome pedido ao sistema que a base de símbolos não conhece:"
  printf '%s\n' "$unknown" | sed 's/^/error:   /'
  echo "error: nome que o sistema não reconhece não desenha em versão nenhuma"
  exit 1
fi

echo "Portão: $(offenders_of_kind checked) nome(s) de símbolo do sistema conferidos contra macOS $MINIMUM_MACOS."

if [ "$MODE" = "release" ]; then
  bundled_art="$(find "$APP_PATH" -type f 2>/dev/null | grep -iE "\.($art_extensions)$" || true)"
  if [ -n "$bundled_art" ]; then
    echo "error: o bundle '$CONFIG' contém arte fora do conjunto aprovado:"
    printf 'error:   %s\n' $bundled_art
    echo "error: só a arte própria e aprovada é distribuída; o resto sai do produto"
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
      echo "error: o catálogo de recursos de '$CONFIG' contém entradas fora do conjunto aprovado:"
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
    echo "error: reconstrua com a ação de build, ou confira em modo 'test-host'"
    exit 1
  fi
fi

if [ "$signed_plist" != "$expected_plist" ]; then
  echo "error: o conjunto de direitos do produto não é o esperado no modo '$MODE':"
  diff -u --label esperado --label assinado \
    <(printf '%s\n' "$expected_plist") <(printf '%s\n' "$signed_plist") \
    | sed 's/^/error:   /' || true
  echo "error: a comparação é do plist inteiro — chaves e valores, em qualquer direção"
  exit 1
fi

echo "Portão: modo $MODE, arquitetura $present_archs e conjunto de direitos exatamente o esperado."
