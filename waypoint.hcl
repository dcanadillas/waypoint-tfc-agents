variable "gcp_project" {
  description = "GCP project for a GCR push registry"
  default = "hc-dcanadillas"
}
variable "gcp_location" {
  description = "GCP location"
}


project = "tfc-agents"

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


app "agent-kubernetes" {
  path = "${path.project}"
  url {
    auto_hostname = false
  }

  build {
    use "docker-pull" {
      image = "hashicorp/tfc-agent"
      tag = "latest"
    }
    registry {
      use "docker" {
        image = "gcr.io/${var.gcp_project}/tfc-agent"
        tag   = "latest"
        local = true
      }
    }
  }

  deploy {
    # Applying the Kubernestes namespace to deploy the agent
    hook {
      when = "before"
      command = [
        "bash",
        "-c",
        "echo '{\"apiVersion\": \"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"tfc\"}}' | kubectl apply -f -"
      ]
    }
    use "kubernetes-apply" {
      path = templatefile("${path.app}/tfc-agent.yaml")
      prune_label = "app=tfc-agent"
    }
  }
}

app "agent-docker" {
  url {
    auto_hostname = false
  }

  build {
    use "docker-pull" {
      image = "hashicorp/tfc-agent"
      tag = "latest"
    }
    registry {
      use "docker" {
        image = "gcr.io/${var.gcp_project}/tfc-agent"
        tag   = "latest"
        # local = true
      }
    }
  }
    
  deploy {
    use "docker" {}
  }
}

app "agent-cloudrun" {
    url {
    auto_hostname = false
  }

  build {
    use "docker-pull" {
      image = "hashicorp/tfc-agent"
      tag = "latest"
    }
    registry {
      use "docker" {
        image = "gcr.io/${var.gcp_project}/tfc-agent"
        tag   = "latest"
      }
    }
  }
    
  deploy {
    use "google-cloud-run" {
      project  = var.gcp_project
      location = var.gcp_location

      capacity {
          memory                     = 1024
          cpu_count                  = 2
          max_requests_per_container = 10
          request_timeout            = 300
      }
      auto_scaling {
          max = 5
      }
    }
  }
}
