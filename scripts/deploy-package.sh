# publish package and save the package Id and cap ID
eval $(sui client publish --json | jq -r '
  .objectChanges[] |
  if .type == "published" then
    "PACKAGE_ID=\(.packageId)"
  elif .objectType | contains("::game::CoinFlipCap") then
    "COIN_FLIP_CAP=\(.objectId)"
  else empty end
')

echo $COIN_FLIP_CAP
echo $PACKAGE_ID