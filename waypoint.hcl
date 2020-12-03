project = "tfc-agents"


app "agent-kubernetes" {
  url {
    auto_hostname = false
  }

  build {
    use "docker-pull" {
      image = "hashicorp/tfc-agent"
      tag = "latest"
    }
    # use "docker" {}
    registry {
      use "docker" {
        image = "gcr.io/hc-dcanadillas/tfc-agent"
        tag   = "latest"
      }
    }
  }

  deploy {
#    use "kubernetes" {
#      static_environment = {
#        TFC_AGENT_TOKEN = "${jsondecode(file("./creds.json"))["tfc_token"]}"
#        TFC_AGENT_NAME = jsondecode(file("./creds.json"))["tfc_name"]
#      }
#    }
#    hook {
#      when = "before"
#      command = [
#        "./script.sh"
#      ]
#    }
    use "exec" {
      command = [
        "kubectl",
        "apply",
        "-f",
        "<TPL>"
      ]
      template {
        path = "./tfc-agent.yaml"
      }
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
        image = "gcr.io/hc-dcanadillas/tfc-agent"
        tag   = "latest"
      }
    }
  }
    
  deploy {
    use "docker" {
    }
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
        image = "gcr.io/hc-dcanadillas/tfc-agent"
        tag   = "latest"
      }
    }
  }
    
  deploy {
    use "google-cloud-run" {
      project  = "${jsondecode(file("gcp_values.json"))["project"]}"
      location = "${jsondecode(file("gcp_values.json"))["region"]}"

      capacity {
          memory                     = 1024
          cpu_count                  = 2
          max_requests_per_container = 10
          request_timeout            = 300
      }

      static_environment = {
        TFC_AGENT_TOKEN = "${jsondecode(file("./creds.json"))["tfc_token"]}"
        TFC_AGENT_NAME = jsondecode(file("./creds.json"))["tfc_name"]
      }

      auto_scaling {
          max = 5
      }
    }
  }
}
