#! /bin/bash
#
# Postfacto, a free, open-source and self-hosted retro tool aimed at helping
# remote teams.
#
# Copyright (C) 2016 - Present Pivotal Software, Inc.
#
# This program is free software: you can redistribute it and/or modify
#
# it under the terms of the GNU Affero General Public License as
#
# published by the Free Software Foundation, either version 3 of the
#
# License, or (at your option) any later version.
#
#
#
# This program is distributed in the hope that it will be useful,
#
# but WITHOUT ANY WARRANTY; without even the implied warranty of
#
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#
# GNU Affero General Public License for more details.
#
#
#
# You should have received a copy of the GNU Affero General Public License
#
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! $* =~ --skip-package ]];
then
  "$SCRIPT_DIR/package.sh"
fi

if [[ ! $* =~ --skip-heroku ]];
then
  heroku whoami \
    || (echo 'You need to have the Heroku CLI installed and be logged in' \
      && exit 1)
fi

if [[ ! $* =~ --skip-cf ]];
then
  cf target \
    || (echo 'You need to have the CF CLI installed and be logged in' \
      && exit 1)
fi

curl -L -o "$SCRIPT_DIR/last-release.zip" 'https://github.com/pivotal/postfacto/releases/latest/download/package.zip'
unzip "$SCRIPT_DIR/package.zip"
unzip "$SCRIPT_DIR/last-release.zip" -d "$SCRIPT_DIR/last-release"
echo 'Setup complete'

NOW=$(date +%s)

OLD_APP="postfacto-old-app-${NOW}"
NEW_APP="postfacto-new-app-${NOW}"

if [[ ! $* =~ --skip-cf ]];
then
  echo '####### Cloud Foundry'

  SPACE="postfacto-space-${NOW}"

  cf create-space $SPACE
  cf target -s $SPACE

  cf create-service \
    ${REDIS_SERVICE:-'p-redis'} \
    ${REDIS_PLAN:-'shared-vm'} \
    postfacto-redis

  cf create-service \
    ${DB_SERVICE:-'p.mysql'} \
    ${DB_PLAN:-'db-small'} \
    postfacto-db

  while [[ $(cf services) =~ 'create in progress' ]];
  do
    echo 'Service creation in progress'
    sleep 5
  done

  pushd "$SCRIPT_DIR/last-release/package/pws" # TODO: change pws to cf
    echo 'Deploying old version to Cloud Foundry'
    ENABLE_ANALYTICS=false ./deploy.sh $OLD_APP
  popd

  pushd "$SCRIPT_DIR/package/pws" # TODO: change pws to cf
    echo 'Upgrading old version on Cloud Foundry'
    ENABLE_ANALYTICS=false ./upgrade.sh $OLD_APP
  popd

  pushd "$SCRIPT_DIR/package"
    # smoke test after upgrade
    OLD_APP_URL="https://$OLD_APP.cfapps.io"
    OLD_APP_ADMIN_URL="https://$OLD_APP.cfapps.io/admin"

    ./smoke-test.sh $OLD_APP_URL $OLD_APP_ADMIN_URL email@example.com password
  popd

  pushd "$SCRIPT_DIR/last-release/package/pws" # TODO: change pws to cf
    echo 'Deploying new version to Cloud Foundry'
    ENABLE_ANALYTICS=false ./deploy.sh $NEW_APP
  popd

  pushd "$SCRIPT_DIR/package"
    # smoke test after upgrade
    APP_URL="https://$NEW_APP.cfapps.io"
    APP_ADMIN_URL="https://$NEW_APP.cfapps.io/admin"

    ./smoke-test.sh $APP_URL $APP_ADMIN_URL email@example.com password
  popd

  echo 'Cleaning up Cloud Foundry'
  for APP in $OLD_APP $NEW_APP
  do
    cf delete $APP -f -r
  done

  for SERVICE in 'postfacto-redis' 'postfacto-db'
  do
    cf delete-service $SERVICE -f
  done

  while [[ $(cf services) =~ 'delete in progress' ]];
  do
    echo 'Service deletion in progress'
    sleep 5
  done

  cf delete-space $SPACE -f
fi

if [[ ! $* =~ --skip-heroku ]];
then
  echo '####### Heroku'

  pushd "$SCRIPT_DIR/last-release/package/heroku"
    echo 'Deploying old version to Heroku'
    ENABLE_ANALYTICS=false ./deploy.sh $OLD_APP
  popd

  pushd "$SCRIPT_DIR/package/heroku"
    echo 'Upgrading old version on Heroku'
    ENABLE_ANALYTICS=false ./upgrade.sh $OLD_APP
  popd

   pushd "$SCRIPT_DIR/package"
    # smoke test after upgrade
    OLD_APP_URL=$(heroku info $OLD_APP -s | grep web_url | cut -d= -f2)
    OLD_APP_ADMIN_URL="$OLD_APP_URL/admin"

    ./smoke-test.sh $OLD_APP_URL $OLD_APP_ADMIN_URL email@example.com password
  popd

  pushd "$SCRIPT_DIR/package/heroku"
    echo 'Deploying new version to Heroku'
    ENABLE_ANALYTICS=false ./deploy.sh $NEW_APP
  popd

  pushd "$SCRIPT_DIR/package"
    # smoke test after upgrade
    APP_URL=$(heroku info $NEW_APP -s | grep web_url | cut -d= -f2)
    APP_ADMIN_URL="$NEW_APP/admin"

    ./smoke-test.sh $APP_URL $APP_ADMIN_URL email@example.com password
  popd

  echo 'Cleaning up Heroku'
  for APP in $OLD_APP $NEW_APP
  do
    heroku apps:delete -a $APP -c $APP
  done
fi

echo 'Cleaning up working directory'
rm -rf "$SCRIPT_DIR/last-release" "$SCRIPT_DIR/last-release.zip" "$SCRIPT_DIR/package"
