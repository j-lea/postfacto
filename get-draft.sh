#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get the asset url of the only draft
asset_url=$(curl -u $GITHUB_USERNAME:$ACCESS_TOKEN \
          --header "Accept: application/json" \
          --request GET \
          $REPO_API_URL \
          | jq --raw-output 'sort_by(.created_at) | .[] | select(.draft==true).assets[0].url' | head -n 1)

# Get the redirect url
redirect_url=$(curl --silent --show-error \
          --header "Authorization: token $ACCESS_TOKEN" \
          --header "Accept: application/octet-stream" \
          --request GET \
          --write-out "%{redirect_url}" \
          $asset_url)

curl --silent --show-error \
          --header "Accept: application/octet-stream" \
          --output $SCRIPT_DIR/package2.zip \
          --request GET \
          $redirect_url