# Configure the Google Cloud Provider
provider "google" {
  project = "atanexus-ai-fl2b0"
  region  = "us-central1"
}

provider "google-beta" {
  project = "atanexus-ai-fl2b0"
  region  = "us-central1"
}

# Langfuse module
module "langfuse" {
  source = "github.com/langfuse/langfuse-terraform-gcp?ref=main"

  # Required
  domain = "langfuse.atanexus.com"

  # Optional configurations - Optimized for cost
  name                                = "langfuse"
  kubernetes_namespace                = "langfuse"
  subnetwork_cidr                     = "10.0.0.0/16"
  
  # Database optimization - Significant cost savings
  database_instance_tier              = "db-standard-1"          # Changed from db-perf-optimized-N-2
  database_instance_edition           = "ENTERPRISE"             # Changed from ENTERPRISE_PLUS
  database_instance_availability_type = "ZONAL"                 # Changed from REGIONAL
  
  # Cache optimization - Cost savings for development/testing
  cache_tier                          = "BASIC"                 # Changed from STANDARD_HA
  cache_memory_size_gb                = 1
  
  # Keep production-ready features
  deletion_protection                 = true
  langfuse_chart_version              = "1.2.15"
  use_encryption_key                  = true
}

# Configure Kubernetes provider using the cluster created by the module
provider "kubernetes" {
  host                   = module.langfuse.cluster_host
  cluster_ca_certificate = module.langfuse.cluster_ca_certificate
  token                  = module.langfuse.cluster_token
}

# Configure Helm provider using the cluster created by the module
provider "helm" {
  kubernetes {
    host                   = module.langfuse.cluster_host
    cluster_ca_certificate = module.langfuse.cluster_ca_certificate
    token                  = module.langfuse.cluster_token
  }
}

# Outputs
output "cluster_name" {
  description = "GKE Cluster Name"
  value       = module.langfuse.cluster_name
}

output "cluster_host" {
  description = "GKE Cluster endpoint"
  value       = module.langfuse.cluster_host
}

output "langfuse_url" {
  description = "URL to access Langfuse"
  value       = "https://langfuse.atanexus.com"
}
