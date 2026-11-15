#!/bin/sh
set -eu
printf '%s\n' 'Lunamo 公証設定（Apple ID方式・ファイルは不要）'
printf 'Apple Developerに登録したメールアドレス: '
IFS= read -r lunamo_apple_id
test -n "$lunamo_apple_id" || exit 1
lunamo_team=$(security find-identity -v -p codesigning | sed -nE 's/.*"Developer ID Application: .* \(([A-Z0-9]{10})\)".*/\1/p' | sort -u)
case "$lunamo_team" in
  ''|*'
'*) printf 'Developer Team ID: '; IFS= read -r lunamo_team ;;
  *) printf '署名証明書のTeam IDを使用: %s\n' "$lunamo_team" ;;
esac
test -n "$lunamo_team" || exit 1
printf '%s\n' '次のPassword欄にアプリ用パスワードを入力してください（画面には表示されません）。'
xcrun notarytool store-credentials lunamo-notary --apple-id "$lunamo_apple_id" --team-id "$lunamo_team"
printf '%s\n' 'Saved: lunamo-notary'
