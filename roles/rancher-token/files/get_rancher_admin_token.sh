#!/bin/bash

set -e


if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "One or more arguments are null or not provided."
  echo "Usage: ${BASH_SOURCE[0]##*/} <rancher_url> <admin_username> <admin_password>"
  exit 1
fi

export RANCHER_URL=$1
export RANCHER_ADMIN_USERNAME=$2
export RANCHER_ADMIN_PASSWORD=$3

sleep 15

# Login
loginurl="${RANCHER_URL}/v3-public/localProviders/local?action=login"
data="{\"username\": \"${RANCHER_ADMIN_USERNAME}\", \"password\": \"${RANCHER_ADMIN_PASSWORD}\"}"

LOGINRESPONSE=`curl -s $loginurl -H 'content-type: application/json' --data-binary "$data" --insecure`
LOGINTOKEN=`echo $LOGINRESPONSE | jq -r .token`

# Create API key
apitokenurl="${RANCHER_URL}/v3/token"
data="{\"type\":\"token\",\"description\":\"automation\"}"
APIRESPONSE=`curl -s $apitokenurl -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary "$data" --insecure`
# Extract and store token
APITOKEN=`echo $APIRESPONSE | jq -r .token`
/bin/echo "${APITOKEN}"

#/bin/echo "{ \"token\": \"${APITOKEN}\" }"