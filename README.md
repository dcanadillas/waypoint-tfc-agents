# Deploy TFC agents in Kubernetes with Waypoint

> NOTE: This is not an official HashiCorp repository and it is a WIP, so it might change frequently. The goal of this repository is to share knowledge.

## Why this...

You can deploy [Terraform Cloud agent docker container](https://hub.docker.com/r/hashicorp/tfc-agent) in Kubernetes just by a simple `kubectl apply -f <your_deploy_manifest>.yaml` command. But then you need to be aware about a couple of things:
* You need to inject a token variable in the container to authenticate to Terraform Cloud from the agent, so your deployment manifest needs to have the token variable definition (clear text or parametrized by some other Kubernetes templating tool like Helm, Kustomize or Kpt), or using some other Kubernetes mount points (`secrets`, `configMaps` or other mount volumes way)
* When you deploy the agent, you need some Kubernetes knowledge and playground to do the debugging, like watching container logs or statuses
* Updating the agent means updating the manifest and redeploy again

There are some **security concerns** then about managing variables definitions in the Kubernetes manifest, and also some Kubernetes knowledge (not very advanced, but you need to have it) to do the agent monitoring.

So, I have decided to use a simple deployment tool like [Waypoint](https://www.waypointproject.io/) that helps on this by:
* Injecting the container variables without the need to define them on the manifest, so you can secure the process in different ways
* Using HashiCorp Vault to store the Terraform Cloud Agent token in a secured way
* Watching container logs on the agent without having to access the Kubernetes cluster from your local machine
* To update your agent is as simple as running the following command: `waypoint up`

The goal of this repo is more a knowledge sharing thing about Waypoint deployments, but this use case could be a good example of securing your Terraform Cloud hosted agent deployments in Kubernetes to integrate in your CI/CD orchestration.

Following high level diagram explains the deployment:

![Waypoint TFC agent deployment diagram](./docs/Waypoint_TFC_Agents.png)

## Requirements
* Waypoint [binary](https://www.waypointproject.io/downloads) 0.5.2+
* Docker installed
* A Kubernetes cluster (I use [Minikube](https://kubernetes.io/docs/tutorials/kubernetes-basics/create-cluster/cluster-intro/) for a local test)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) tool
* [Terraform Cloud account](https://app.terraform.io/app) with a Business tier subscription
* A Terraform Cloud [organization token](https://www.terraform.io/docs/cloud/users-teams-organizations/api-tokens.html#organization-api-tokens)
* A Vault instance accessible by your terminal and your agent containers (you can use [HCP Vault](https://portal.cloud.hashicorp.com/sign-up?utm_source=cloud_landing&utm_content=offers_vault) free credits)

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

waypoint install -platform=kubernetes -k8s-namespace=waypoint -context-create="waypoint-kubernetes" -accept-tos

waypoint server config-set -advertise-addr=waypoint.waypoint:9701 -advertise-tls=true -advertise-tls-skip=true

waypoint init

./script.sh $TFE_ORG

waypoint up -app agent-kubernetes

waypoint ui -authenticate
```

Then, you can access or execute any command in the container of the agent by using waypoint. For example, if you want to access to the container's terminal:
```bash
waypoint exec -app agent-kubernetes bash
```

And you can access to the containers logs (you can [use also de UI](#deploy-the-tfc-agent-with-waypoint)):
```bash
waypoint logs -app agent-kubernetes
```

## The manual process

If you want to create every step by your own you can follow the following sections

### Create an agent pool token in Terraform Cloud

You need to edit or create an agent pool in Terraform Cloud and generate a pool token. You can do it easily with the Terraform Cloud API as follows:

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

### Store your secrets (TFC agent name and agent token) in Vault

> NOTE: Bear in mind that you are storing the previous data created from Terraform Cloud, so if you did it manually, just copy the Terraform Agent token created before and use it as your `$TFC_AGENT_TOKEN` variable.

Configure your Vault variables `$VAULT_ADDR`, `$VAULT_TOKEN` and `VAULT_NAMESPACE` (if using Vault Enterprise or HCP Vault) and create the secrets with:

```bash
vault secrets enable -path=waypoint kv

vault kv put waypoint2/tfc tfc_name=tfc-agent tfc_token=$TFC_AGENT_TOKEN
```

Check that the secrets are stored. Here is the example of the command and output:
```
$ vault kv get waypoint/tfc
====== Data ======
Key          Value
---          -----
tfc_name     tfc-agent
tfc_token    PCeOzEHFQwEb8A.atlasv1.myIzFm....
```

### Install Waypoint and initialize the project

You can install Waypoint as a Docker container, in Kubernetes, using Nomad, or runnig standalone. Here, we are going to use the same Kubernetes cluster where we are deploying the TFC agent (we create a `waypoint` namespace to deploy):
```bash
kubectl create ns waypoint

waypoint install -platform=kubernetes -k8s-nasmespace=waypoint -context-create="tfc-kubernetes-context" -accept-tos
```

You can verify that you can connect to the Waypoint server:
```
$ waypoint context verify
✓ Context "tfc-kubernetes-context" connected successfully.
```

We want to be sure that all the [Waypoint Entrypoint variables](https://www.waypointproject.io/docs/waypoint-hcl/variables/entrypoint) are going to be injected to our deployment. Even though that this should be set by default in the previous installation, we just execute the following command to reconfigure correctly:

```bash
waypoint server config-set -advertise-addr=waypoint.waypoint:9701 \
-advertise-tls=true \
-advertise-tls-skip-verify=true
```

> NOTE: Look at the `-advertise-addr=waypoint.waypoint:9701` parameter. This value is for the service used in our Kubernetes deployment, so our agent entrypoint that is going to be deployed in the same Kubernetes cluster is able to connect.

Now, from the root path of this repo (where the `waypoint.hcl` configuration file is located), run:
```bash
waypoint init
```

Connect to your Waypoint UI and check that you see a `tfc-agents` project:

```bash
waypoint ui -authenticate

```

![tfc-agents project](./docs/tfc-agents_project.png)


### Deploy the TFC agent with Waypoint

The TFC Agent name and token are retrieved from Vault through the Waypoint Configuration in the `waypoint.hcl`. You can check that the block is already defined there:

```hcl
config {
  env = {
    "TFC_AGENT_NAME" = configdynamic("vault", {
      path = "waypoint/tfc"
      key = "tfc_name"
    })
    "TFC_AGENT_TOKEN" = "${configdynamic("vault", {
      path = "waypoint/tfc"
      key = "tfc_token"
    })}"
  }
}
```

Now it is time to deploy the Terraform Cloud agent. Let's synchronize first the Waypoint injection variables:
```bash
waypoint config sync -app agent-kubernetes
```

And we can check that it is configured:
```
$ waypoint config get 
  SCOPE |      NAME       |        VALUE         
--------+-----------------+----------------------
        | TFC_AGENT_NAME  | <dynamic via vault>  
        | TFC_AGENT_TOKEN | <dynamic via vault> 
```

Let's deploy now the agent in the Kubernetes cluster (configured to deploy to `tfc` namespace):

```bash
waypoint up -app agent-kubernetes
```

That's all! You will see your TFC agent connected into the pool in the Terraform Cloud UI:

![tfc-agents deployed](./docs/tfc-agent-deployed.png)

Also, you can check the agents logs from the Waypoint Project UI:

![TFC Agents logs](./docs/Waypoint-tfc-agent-logs.png)

Or doing it by CLI (output included):
```
$ waypoint logs -app agent-kubernetes
2021-09-29T16:38:30.827Z V9FQDS: [INFO]  entrypoint: entrypoint starting:
deployment_id=01FGS6FRM792NZC8P00X6TNJ4E instance_id=01FGS6QZM5XCAN7X7NH5V9FQDS
args=["/home/tfc-agent/bin/tfc-agent"]
2021-09-29T16:38:30.827Z V9FQDS: [INFO]  entrypoint: entrypoint version: full_string=v0.5.1 version=v0.5.1
prerelease="" metadata="" revision=""
2021-09-29T16:38:30.827Z V9FQDS: [INFO]  entrypoint: server version info: version=v0.5.2 api_min=1
api_current=1 entrypoint_min=1 entrypoint_current=1
2021-09-29T16:38:31.737Z V9FQDS: [INFO]  entrypoint.config.watcher: env vars changed, sending new child
command
2021-09-29T16:38:31.737Z V9FQDS: [INFO]  entrypoint.child: starting child process:
args=["/home/tfc-agent/bin/tfc-agent"] cmd=/home/tfc-agent/bin/tfc-agent
2021-09-29T16:38:31.746Z V9FQDS: 2021-09-29T16:38:31.746Z [INFO]  agent: Starting: name=tfc-agent
version=0.4.1
2021-09-29T16:38:31.761Z V9FQDS: 2021-09-29T16:38:31.760Z [INFO]  core: Starting: version=0.4.1
2021-09-29T16:38:32.517Z V9FQDS: 2021-09-29T16:38:32.516Z [INFO]  core: Agent registered successfully with
Terraform Cloud: id=agent-fX9kYCDzcQgm5Noh pool-id=apool-vWL1yZP17UmSYkev
2021-09-29T16:38:32.646Z V9FQDS: 2021-09-29T16:38:32.646Z [INFO]  agent: Core version is up to date:
version=0.4.1
2021-09-29T16:38:32.647Z V9FQDS: 2021-09-29T16:38:32.646Z [INFO]  core: Waiting for next job
```

## Undeploy the agent

It is very simple to remove the deployment of the agent:

```bash
waypoint destroy -app agent-kubernetes -auto-approve
```

You should see that kubernetes deployment, pod and replicaSet are deleted (CLI output shown):
```
» Destroying deployments for application 'agent-kubernetes'...
✓ Executing kubectl to destroy...
 │ pod "tfc-agent-55b78f4c6d-8rqzx" deleted
 │ deployment.apps "tfc-agent" deleted
 │ replicaset.apps "tfc-agent-55b78f4c6d" deleted
Destroy successful!
```