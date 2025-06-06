#!/bin/bash

# Langfuse GCP Terraform Deployment Script
# This script automates the deployment of Langfuse on Google Cloud Platform

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if required tools are installed
    if ! command_exists terraform; then
        print_error "Terraform is not installed. Please install it from https://terraform.io/downloads"
        exit 1
    fi
    
    if ! command_exists gcloud; then
        print_error "Google Cloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        print_error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
}

# Function to enable required GCP APIs
enable_apis() {
    print_info "Enabling required GCP APIs..."
    
    local apis=(
        "certificatemanager.googleapis.com"
        "dns.googleapis.com"
        "compute.googleapis.com"
        "file.googleapis.com"
        "redis.googleapis.com"
        "container.googleapis.com"
        "networkconnectivity.googleapis.com"
        "servicenetworking.googleapis.com"
        "sqladmin.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_info "Enabling $api..."
        gcloud services enable "$api" --project="$GCP_PROJECT_ID"
    done
    
    print_success "All APIs enabled successfully!"
}

# Function to validate input parameters
validate_inputs() {
    if [[ -z "$DOMAIN" ]]; then
        print_error "DOMAIN is required. Please set it in the script or pass as environment variable."
        exit 1
    fi
    
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        print_error "GCP_PROJECT_ID is required. Please set it in the script or pass as environment variable."
        exit 1
    fi
    
    if [[ -z "$GCP_REGION" ]]; then
        print_warning "GCP_REGION not set, using default: us-central1"
        GCP_REGION="us-central1"
    fi
    
    print_success "Input validation passed!"
}

# Function to create main.tf file
create_main_tf() {
    print_info "Creating main.tf configuration file..."
    
    cat > main.tf << EOF
# Configure the Google Cloud Provider
provider "google" {
  project = "$GCP_PROJECT_ID"
  region  = "$GCP_REGION"
}

provider "google-beta" {
  project = "$GCP_PROJECT_ID"
  region  = "$GCP_REGION"
}

# Langfuse module
module "langfuse" {
  source = "./"

  # Required
  domain = "$DOMAIN"

  # Optional configurations
  name                                = "$DEPLOYMENT_NAME"
  kubernetes_namespace                = "$KUBERNETES_NAMESPACE"
  subnetwork_cidr                     = "$SUBNETWORK_CIDR"
  database_instance_tier              = "$DATABASE_TIER"
  database_instance_edition           = "$DATABASE_EDITION"
  database_instance_availability_type = "$DATABASE_AVAILABILITY"
  cache_tier                          = "$CACHE_TIER"
  cache_memory_size_gb                = $CACHE_MEMORY_GB
  deletion_protection                 = $DELETION_PROTECTION
  langfuse_chart_version              = "$LANGFUSE_CHART_VERSION"
  use_encryption_key                  = $USE_ENCRYPTION_KEY
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
  value       = "https://$DOMAIN"
}
EOF

    print_success "main.tf created successfully!"
}

# Function to initialize Terraform
terraform_init() {
    print_info "Initializing Terraform..."
    terraform init
    print_success "Terraform initialized successfully!"
}

# Function to apply initial resources (DNS and GKE cluster)
apply_initial_resources() {
    print_info "Applying initial resources (DNS zone and GKE cluster)..."
    print_warning "This step avoids dependency issues and may take 10-15 minutes..."
    
    terraform apply \
        -target="module.langfuse.google_dns_managed_zone.this" \
        -target="module.langfuse.google_container_cluster.this" \
        -auto-approve
    
    print_success "Initial resources applied successfully!"
}

# Function to get nameservers and display DNS delegation instructions
get_dns_info() {
    print_info "Getting DNS nameservers for domain delegation..."
    
    local zone_name="${DOMAIN//./-}"  # Replace dots with hyphens for zone name
    
    print_info "Retrieving nameservers for zone: $zone_name"
    local nameservers
    nameservers=$(gcloud dns managed-zones describe "$zone_name" --format="get(nameServers)" --project="$GCP_PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$nameservers" ]]; then
        print_success "DNS nameservers for $DOMAIN:"
        echo "$nameservers" | tr ';' '\n' | sed 's/^/  - /'
        echo ""
        print_warning "IMPORTANT: You need to update your domain's nameservers with your DNS provider!"
        print_warning "Set the nameservers listed above for domain: $DOMAIN"
        echo ""
        print_info "After updating nameservers, press Enter to continue..."
        read -r
    else
        print_warning "Could not retrieve nameservers. They will be available after initial deployment."
    fi
}

# Function to apply full infrastructure
apply_full_infrastructure() {
    print_info "Applying full infrastructure..."
    print_warning "This may take 20-30 minutes to complete..."
    
    terraform apply -auto-approve
    
    print_success "Full infrastructure deployed successfully!"
}

# Function to check SSL certificate status
check_ssl_status() {
    print_info "Checking SSL certificate status..."
    
    local cert_name="$DEPLOYMENT_NAME"
    local status
    status=$(gcloud compute ssl-certificates describe "$cert_name" --format="get(managed.status)" --project="$GCP_PROJECT_ID" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$status" == "ACTIVE" ]]; then
        print_success "SSL certificate is ACTIVE and ready!"
    elif [[ "$status" == "PROVISIONING" ]]; then
        print_warning "SSL certificate is still PROVISIONING. This can take up to 20 minutes."
        print_info "You can check status with: gcloud compute ssl-certificates list --project=$GCP_PROJECT_ID"
    else
        print_warning "SSL certificate status: $status"
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    echo ""
    print_success "🎉 Langfuse deployment completed!"
    echo ""
    print_info "Deployment Summary:"
    echo "  - Domain: $DOMAIN"
    echo "  - Project: $GCP_PROJECT_ID"
    echo "  - Region: $GCP_REGION"
    echo "  - Deployment Name: $DEPLOYMENT_NAME"
    echo ""
    print_info "Access your Langfuse instance at: https://$DOMAIN"
    echo ""
    print_warning "Note: If you see SSL errors, the certificate may still be provisioning."
    print_info "Check certificate status: gcloud compute ssl-certificates list --project=$GCP_PROJECT_ID"
    echo ""
    print_info "Useful commands:"
    echo "  - Get cluster credentials: gcloud container clusters get-credentials $DEPLOYMENT_NAME --region=$GCP_REGION --project=$GCP_PROJECT_ID"
    echo "  - Check pods: kubectl get pods -n $KUBERNETES_NAMESPACE"
    echo "  - View logs: kubectl logs -f deployment/langfuse -n $KUBERNETES_NAMESPACE"
}

# Function to cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. You may want to clean up resources."
    print_info "To destroy infrastructure: terraform destroy"
}

# Main deployment function
main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  Langfuse GCP Deployment                     ║"
    echo "║           Automated Terraform Deployment Script             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Load configuration from file if it exists
    if [[ -f "deploy.config.local" ]]; then
        print_info "Loading configuration from deploy.config.local"
        source deploy.config.local
    else
        print_warning "No config file found. Using environment variables or defaults."
    fi
    
    # Configuration Variables (can be overridden by environment variables)
    # Required variables
    DOMAIN="${DOMAIN:-}"                                    # e.g., "langfuse.example.com"
    GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"                   # Your GCP project ID
    
    # Optional variables with defaults
    GCP_REGION="${GCP_REGION:-us-central1}"                # GCP region
    DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-langfuse}"         # Name for resources
    KUBERNETES_NAMESPACE="${KUBERNETES_NAMESPACE:-langfuse}" # K8s namespace
    SUBNETWORK_CIDR="${SUBNETWORK_CIDR:-10.0.0.0/16}"    # VPC subnet CIDR
    DATABASE_TIER="${DATABASE_TIER:-db-perf-optimized-N-2}" # Database instance type
    DATABASE_EDITION="${DATABASE_EDITION:-ENTERPRISE_PLUS}" # Database edition
    DATABASE_AVAILABILITY="${DATABASE_AVAILABILITY:-REGIONAL}" # Database availability
    CACHE_TIER="${CACHE_TIER:-STANDARD_HA}"               # Redis tier
    CACHE_MEMORY_GB="${CACHE_MEMORY_GB:-1}"               # Redis memory in GB
    DELETION_PROTECTION="${DELETION_PROTECTION:-true}"    # Enable deletion protection
    LANGFUSE_CHART_VERSION="${LANGFUSE_CHART_VERSION:-1.2.15}" # Helm chart version
    USE_ENCRYPTION_KEY="${USE_ENCRYPTION_KEY:-true}"      # Use encryption key
    
    # Validate inputs
    validate_inputs
    
    # Check prerequisites
    check_prerequisites
    
    # Set GCP project
    print_info "Setting GCP project to: $GCP_PROJECT_ID"
    gcloud config set project "$GCP_PROJECT_ID"
    
    # Enable APIs
    enable_apis
    
    # Create main.tf
    # Skip main.tf creation - use existing file
    print_info "Using existing main.tf configuration"
    
    # Terraform workflow
    terraform_init
    
    # Apply initial resources
    apply_initial_resources
    
    # Get DNS info and wait for user to configure nameservers
    get_dns_info
    
    # Apply full infrastructure
    apply_full_infrastructure
    
    # Check SSL status
    check_ssl_status
    
    # Show summary
    show_deployment_summary
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Run main function
main "$@" 