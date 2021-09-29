#!/bin/bash
# echo "$1" | kubectl apply -f -

TFC_AGENT_NAME="tfc-agent"
TFC_POOL_NAME="demo-pool"
# VAULT_NAMESPACE="root"
TFE_ORG=$1

if [ -z "$1" ];then
  echo "You need to specify the TFC/TFE organization as a parameter of this script..."
  exit 1
fi

if [ -z "$VAULT_TOKEN" ];then
  echo "VAULT_TOKEN variable is not set to authenticate into Vault"
  exit 1
fi

if [ -z "$VAULT_ADDR" ];then
  echo "VAULT_ADDR variable is not set for your Vault Address"
  exit 1
fi

if [ -z "$VAULT_NAMESPACE" ];then
  echo "VAULT_NAMESPACE variable is not set for your Vault Address"
  echo "Using \"root\" namespace"
  VAULT_NAMESPACE="root"
fi

if [ -z "$TFE_TOKEN" ];then
  echo "There is no Terraform API token \$TFE_TOKEN variable..."
  if [ -f "$HOME/.terraform.d/credentials.tfrc.json" ];then
    echo "... Using your API token from your \"$HOME/.terraform.d/credentials.tfrc.json\" file"
    TFE_TOKEN=$(cat $HOME/.terraform.d/credentials.tfrc.json | jq -r '.credentials."app.terraform.io".token')
  else
    exit 1
  fi
fi


TFC_POOL_ID=$(curl -s -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" -X GET https://app.terraform.io/api/v2/organizations/$TFE_ORG/agent-pools | jq -r ".data[] | select(.attributes.name == \"$TFC_POOL_NAME\") | .id")

# if [ $(curl -s -H "Authorization: Bearer $TFE_TOKEN" \
# -H "Content-Type: application/vnd.api+json" \
# -X GET https://app.terraform.io/api/v2/organizations/$TFE_ORG/agent-pools \
# | jq -r ".data[].attributes.name | select(. == \"$TFC_POOL_NAME\")") ];then 
#   echo "TRUE"
# fi



# If previous pool ID variable is empty, let's create the pool and retrieve the pool ID
if [ -z "$TFC_POOL_ID" ] || [ "$TFC_POOL_ID" == "null" ];then
  # Creating the agent pool in TFC4B and saving the id in a variable
  TFC_POOL_ID=$(cat << EOF | curl -s -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" -X POST -d @- https://app.terraform.io/api/v2/organizations/$TFE_ORG/agent-pools | jq -r '.data.id' 
  {
    "data": {
      "type": "agent-pools",
      "attributes": {
        "name": "$TFC_POOL_NAME"
      }
    }
  }
EOF
  )
fi

echo "Pool ID is: $TFC_POOL_ID"

TFC_AGENT_TOKEN=$(cat << EOF | curl -s -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" -X POST -d @- https://app.terraform.io/api/v2/agent-pools/$TFC_POOL_ID/authentication-tokens | jq -r '.data.attributes.token'
{
  "data": {
    "type": "authentication-tokens",
    "attributes": {
      "description": "dcanadillas-agent"
    }
  }
}
EOF
)

echo $TFC_AGENT_TOKEN

## Enabling a secrets path and uploading the Vault secret

#vault secrets enable -path waypoint kv
#vault kv put waypoint/tfc tfc_token=$TFC_AGENT_TOKEN tfc_name="$TFC_AGENT_NAME"


cat << EOF | curl -X POST -H "accept: */*" -H "X-Vault-Namespace: $VAULT_NAMESPACE" -H "X-Vault-Token: $VAULT_TOKEN" -d @- "$VAULT_ADDR/v1/sys/mounts/waypoint"
{
  "type": "kv"
}
EOF

cat << EOF | curl -X POST -H "accept: */*" -H "X-Vault-Namespace: $VAULT_NAMESPACE" -H "X-Vault-Token: $VAULT_TOKEN" -d @- "$VAULT_ADDR/v1/waypoint/tfc"
{
  "tfc_name": "$TFC_AGENT_NAME",
  "tfc_token": "$TFC_AGENT_TOKEN"
}
EOF


# cat <<-EOF > creds_values.json
# {
#   "tfc_name": "tfc-agent",
#   "tfc_token": $(curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/kv/data/tfc_tokens | jq '.data.data["dcanadillas-agent"]')
# }
# EOF

# waypoint config set -app agent-kubernetes TFC_AGENT_TOKEN=$(curl -H "X-Vault-Token: $VAULT_TOKEN" -H "accept: */*" $VAULT_ADDR/v1/kv/data/tfc_tokens | jq -r '.data.data["dcanadillas-agent"]')
# waypoint config set -app agent-kubernetes TFC_AGENT_TOKEN=$(curl -H "X-Vault-Token: $VAULT_TOKEN" -H "accept: */*" $VAULT_ADDR/v1/waypoint/tfc | jq -r '.data["tfc_token"]')
# waypoint config set -app agent-kubernetes TFC_AGENT_NAME=$(curl -H "X-Vault-Token: $VAULT_TOKEN" -H "accept: */*" $VAULT_ADDR/v1/waypoint/tfc | jq -r '.data["tfc_name"]')
waypoint config source-set -type=vault -config="addr=$VAULT_ADDR" -config="token=$VAULT_TOKEN" -config="skip_verify=true" -config="namespace=$VAULT_NAMESPACE"

waypoint config get
waypoint config source-get -type=vault