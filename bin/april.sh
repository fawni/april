#!/bin/sh

HOST=https://april.fawn.moe
CONFIG=$HOME/.config/april/config.json

test -f "$CONFIG" && TOKEN=$(cat "$CONFIG" | jq -er .token)
FILE=$(gum file)
test "$FILE" || exit 1

test "$TOKEN" || TOKEN=$(gum input --placeholder "april token" --password)
RESPONSE=$(curl -sfF "file=@$FILE" "$HOST" -H "Authorization: $TOKEN")

test "$RESPONSE" && echo "$HOST/$RESPONSE"
