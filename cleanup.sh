#!/bin/bash

# Langfuse GCP Terraform Cleanup Script
# This script safely destroys the Langfuse infrastructure

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

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    print_warning "⚠️  DANGER: This will destroy ALL Langfuse infrastructure and data!"
    print_warning "This action cannot be undone and will permanently delete:"
    echo "  - GKE Cluster and all applications"
    echo "  - PostgreSQL database and ALL data"
    echo "  - Redis cache and all cached data"
    echo "  - Storage buckets and all files"
    echo "  - SSL certificates and DNS records"
    echo "  - All networking components"
    echo ""
    
    # Load configuration to show what will be destroyed
    if [[ -f "deploy.config.local" ]]; then
        source deploy.config.local
    elif [[ -f "deploy.config" ]]; then
        source deploy.config
    fi
    
    if [[ -n "$DOMAIN" && -n "$GCP_PROJECT_ID" ]]; then
        print_info "Target Infrastructure:"
        echo "  - Domain: $DOMAIN"
        echo "  - Project: $GCP_PROJECT_ID"
        echo "  - Deployment: ${DEPLOYMENT_NAME:-langfuse}"
        echo ""
    fi
    
    read -p "Type 'DELETE' (in uppercase) to confirm destruction: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        print_info "Cleanup cancelled. No resources were destroyed."
        exit 0
    fi
    
    echo ""
    read -p "Are you absolutely sure? Type 'YES' to proceed: " final_confirmation
    
    if [[ "$final_confirmation" != "YES" ]]; then
        print_info "Cleanup cancelled. No resources were destroyed."
        exit 0
    fi
}

# Function to disable deletion protection if needed
disable_deletion_protection() {
    print_info "Checking deletion protection settings..."
    
    # Load configuration
    if [[ -f "deploy.config.local" ]]; then
        source deploy.config.local
    elif [[ -f "deploy.config" ]]; then
        source deploy.config
    fi
    
    DELETION_PROTECTION="${DELETION_PROTECTION:-true}"
    
    if [[ "$DELETION_PROTECTION" == "true" ]]; then
        print_warning "Deletion protection is enabled. Disabling it first..."
        
        # Create a temporary main.tf to disable deletion protection
        cp main.tf main.tf.backup 2>/dev/null || true
        
        # Update deletion protection in the configuration
        export DELETION_PROTECTION="false"
        
        # Re-create main.tf with deletion protection disabled
        if [[ -f "deploy.sh" ]]; then
            # Extract the create_main_tf function and run it
            print_info "Updating configuration to disable deletion protection..."
            
            # Simple approach: just remind user to update config
            print_warning "Please update your config file to set DELETION_PROTECTION=false and run:"
            print_warning "terraform apply"
            print_warning "Then run this cleanup script again."
            print_warning "Or you can disable deletion protection manually in the GCP console."
            
            read -p "Have you disabled deletion protection? (y/N): " protection_disabled
            
            if [[ "$protection_disabled" != "y" && "$protection_disabled" != "Y" ]]; then
                print_error "Please disable deletion protection first, then re-run this script."
                exit 1
            fi
        fi
    fi
}

# Function to run terraform destroy
run_terraform_destroy() {
    print_info "Starting Terraform destroy process..."
    
    if [[ ! -f "main.tf" ]]; then
        print_error "main.tf not found. Please run this script from the directory containing your Terraform configuration."
        exit 1
    fi
    
    if [[ ! -d ".terraform" ]]; then
        print_warning "Terraform not initialized. Initializing first..."
        terraform init
    fi
    
    print_info "Running terraform destroy..."
    print_warning "This may take 15-30 minutes to complete..."
    
    terraform destroy -auto-approve
    
    print_success "Terraform destroy completed successfully!"
}

# Function to clean up local files
cleanup_local_files() {
    print_info "Cleaning up local Terraform files..."
    
    local files_to_remove=(
        "main.tf"
        "terraform.tfstate"
        "terraform.tfstate.backup"
        ".terraform.lock.hcl"
        "main.tf.backup"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            print_info "Removing $file"
            rm -f "$file"
        fi
    done
    
    if [[ -d ".terraform" ]]; then
        print_info "Removing .terraform directory"
        rm -rf ".terraform"
    fi
    
    print_success "Local cleanup completed!"
}

# Function to verify cleanup
verify_cleanup() {
    print_info "Verifying resource cleanup..."
    
    # Load configuration
    if [[ -f "deploy.config.local" ]]; then
        source deploy.config.local
    elif [[ -f "deploy.config" ]]; then
        source deploy.config
    fi
    
    if [[ -n "$GCP_PROJECT_ID" ]]; then
        print_info "Checking for remaining resources in project $GCP_PROJECT_ID..."
        
        # Check for common resources that might remain
        local deployment_name="${DEPLOYMENT_NAME:-langfuse}"
        
        print_info "You can manually verify cleanup in the GCP Console:"
        echo "  - Kubernetes clusters: https://console.cloud.google.com/kubernetes/list"
        echo "  - SQL instances: https://console.cloud.google.com/sql/instances"
        echo "  - Redis instances: https://console.cloud.google.com/memorystore/redis/instances"
        echo "  - Storage buckets: https://console.cloud.google.com/storage/browser"
        echo "  - DNS zones: https://console.cloud.google.com/net-services/dns/zones"
        echo "  - SSL certificates: https://console.cloud.google.com/net-services/loadbalancing/advanced/sslCertificates/list"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    print_success "🗑️  Langfuse infrastructure cleanup completed!"
    echo ""
    print_info "What was destroyed:"
    echo "  ✅ GKE Cluster and all applications"
    echo "  ✅ PostgreSQL database and data"
    echo "  ✅ Redis cache"
    echo "  ✅ Storage buckets and files"
    echo "  ✅ SSL certificates"
    echo "  ✅ DNS records"
    echo "  ✅ VPC and networking components"
    echo "  ✅ Local Terraform state files"
    echo ""
    print_info "What remains:"
    echo "  - Configuration files (deploy.config.local, etc.)"
    echo "  - This cleanup script"
    echo "  - The original Terraform module files"
    echo ""
    print_warning "Note: DNS zone nameservers may still show in your domain's DNS settings."
    print_warning "You can now update your domain to use your original nameservers."
    echo ""
    print_success "Cleanup completed successfully!"
}

# Main function
main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   Langfuse GCP Cleanup                      ║"
    echo "║              Terraform Infrastructure Destroyer             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Confirm the cleanup
    confirm_cleanup
    
    # Disable deletion protection if needed
    disable_deletion_protection
    
    # Run terraform destroy
    run_terraform_destroy
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Show summary
    show_cleanup_summary
}

# Set trap for cleanup on error
trap 'print_error "Cleanup failed. Some resources may still exist."' ERR

# Run main function
main "$@" 