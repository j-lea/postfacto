# Have am access token
GITHUB_USERNAME=$1
ACCESS_TOKEN=$2
REPO_API_URL=$3
OUTPUT_FILE_PATH=$4

# Get the asset url of the only draft
asset_url=$(curl -u $GITHUB_USERNAME:$ACCESS_TOKEN \
          --header "Accept: application/json" \
          --request GET \
          $REPO_API_URL \
          | jq --raw-output '.[] | select(.draft==true).assets[0].url')

# Get the redirect url
redirect_url=$(curl --silent --show-error \
          --header "Authorization: token $ACCESS_TOKEN" \
          --header "Accept: application/octet-stream" \
          --request GET \
          --write-out "%{redirect_url}" \
          $asset_url)

curl --silent --show-error \
          --header "Accept: application/octet-stream" \
          --output $OUTPUT_FILE_PATH \
          --request GET \
          $redirect_url