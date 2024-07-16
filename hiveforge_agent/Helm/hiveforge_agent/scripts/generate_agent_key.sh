#!/bin/bash
master_key=$1
agent_id=$2
echo -n $master_key$agent_id | openssl dgst -sha256 -hmac $master_key -binary | base64
