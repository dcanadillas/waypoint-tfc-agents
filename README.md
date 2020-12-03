# Deploy TFC agents in Kubernetes with Waypoint

## Requirements
* Waypoint [binary](https://www.waypointproject.io/downloads)
* Docker installed
* A Kubernetes cluster
* [kubectl]() tool
* [Terraform Cloud account](https://app.terraform.io/app) with a Business tier subscription
* A Terraform Cloud [organization token]()

## A secured happy path (using Vault to store Terraform Cloud agent pool token)

> NOTE: If you use this *happy path* you don't need to go to the other sections of this README. Avoid this and jump to the [next section](#create-an-agent-pool-token-in-terraform-cloud) if you want to do it by your own step by step. 

This section just guides you to run most of the preparation things in a script and uses your own [HashiCorp Vault](https://vaultproject.io) to store your Agent pool token. So, you will also need a Vault token with permissions to enable a K/V secrets engine called `waypoint` and privileges to read and write on it.

There is a Bash script `script.sh` included in this repo  that creates the agent pool token in Terraform Cloud using the REST API, connects to Vault to store the token and configures Waypoint variables with those values. So, you can do everything in your bash terminal by running the following commands in order (replace your variables values for Vault and Terraform Cloud):
```bash
export VAULT_ADDR=<your_vault_address>
export VAULT_TOKEN=<your_vault_token>
export TFE_TOKEN=<your_terraform_cloud_org_token>
export TFE_ORG=<your_terraform_org_name>

kubectl create ns waypoint

waypoint install -platform=kubernetes -nasmespace=waypoint -context-create="waypoint-kubernetes" -accept-tos

./script.sh

waypoint up -app agent-kubernetes
```

## Create an agent pool token in Terraform Cloud

You need to edit or create an agent pool in Terraform Cloud and generate a pool token:

* Creating the agents pool with the API (edit your `TFE_TOKEN` and `TFE_ORG` environment variables with your **organization name** and **organization token** from Terraform Cloud):
```bash
TFC_POOL_ID=$(cat << EOF | curl -s -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" -X POST -d @- https://app.terraform.io/api/v2/organizations/$TFE_ORG/agent-pools | jq -r '.data.id' 
{
  "data": {
    "type": "agent-pools",
    "attributes": {
      "name": "demo-pool"
    }
  }
}
EOF)
```
* Take the `id` of the previous output and use it to generate a token and save it in the `TFC_AGENT_TOKEN` environment variable:
```bash
TFC_AGENT_TOKEN=$(cat << EOF | curl -s -H "Authorization: Bearer $TFE_TOKEN" -H "Content-Type: application/vnd.api+json" -X POST -d @- https://app.terraform.io/api/v2/agent-pools/$TFC_POOL_ID/authentication-tokens | jq -r '.data.attributes.token'
{
  "data": {
    "type": "authentication-tokens",
    "attributes": {
      "description": "my-agent-token"
    }
  }
}
EOF)
```

## Install Waypoint and initialize the project

You can install Waypoint as a Docker container, in Kubernetes, using Nomad, or runnig standalone. Here, we are going to use the same Kubernetes cluster where we are deploying the TFC agent (we create a `waypoint` namespace to deploy):
```bash
kubectl create ns waypoint

waypoint install -platform=kubernetes -nasmespace=waypoint -context-create="tfc-kubernetes-context" -accept-tos
```

You can verify that you can connect to the Waypoint server:
```
$ waypoint context verify
✓ Context "tfc-kubernetes-context" connected successfully.
```

Now, from the root path of this repo (where the `waypoint.hcl` configuration file is located), run:
```bash
waypoint init
```

Connect to your Waypoint UI and check that you see a `tfc-agents` project:

```bash
waypoint ui -authenticate

```

![tfc-agents project](./docs/tfc-agents_project.png)


## Deploy the TFC agent with Waypoint

Now it is time to deploy the Terraform Cloud agent. First set the `waypoint config` with the previous variables defined:

```bash
waypoint config set -app agent-kubernetes TFC_AGENT_TOKEN=$TFC_AGENT_TOKEN
waypoint config set -app agent-kubernetes TFC_AGENT_NAME="tfc-agent-demo"
```


```bash
waypoint up -app agent-kubernetes
```

That's all! You will see your TFC agent connected into the pool:

![tfc-agents deployed](./docs/tfc-agent-deployed.png)

