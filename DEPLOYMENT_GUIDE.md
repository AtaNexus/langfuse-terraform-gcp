# Langfuse GCP Deployment Guide

This guide will help you deploy Langfuse on Google Cloud Platform using the automated deployment script.

## Overview

The deployment script (`deploy.sh`) automates the entire process of deploying Langfuse on GCP using Terraform. It includes:

- ✅ **Automated infrastructure provisioning** (GKE, PostgreSQL, Redis, Storage, Networking)
- ✅ **SSL certificate management** with Google Certificate Manager
- ✅ **DNS configuration** with Google Cloud DNS
- ✅ **Security best practices** (encryption, IAM, network isolation)
- ✅ **Production-ready defaults** with high availability options
- ✅ **Cost optimization** options for development environments

## Prerequisites

Before running the deployment script, ensure you have:

1. **Google Cloud Account** with billing enabled
2. **Domain ownership** - You must own the domain you plan to use
3. **Required tools installed:**
   - [Terraform](https://terraform.io/downloads) (>= 1.0)
   - [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
   - [kubectl](https://kubernetes.io/docs/tasks/tools/) (for managing the cluster)

## Quick Start

### 1. Clone and Prepare

```bash
# Navigate to the project directory
cd langfuse-terraform-gcp

# Make the deployment script executable
chmod +x deploy.sh
```

### 2. Configure Your Deployment

Copy and customize the configuration file:

```bash
cp deploy.config deploy.config.local
```

Edit `deploy.config.local` with your settings:

```bash
# Required
DOMAIN="langfuse.yourdomain.com"
GCP_PROJECT_ID="your-gcp-project-id"

# Optional (defaults are production-ready)
GCP_REGION="us-central1"
DEPLOYMENT_NAME="langfuse"
```

### 3. Authenticate with Google Cloud

```bash
# Login to Google Cloud
gcloud auth login

# Set your project (if not already set)
gcloud config set project YOUR_PROJECT_ID
```

### 4. Run the Deployment

```bash
./deploy.sh
```

The script will:
1. ✅ Check prerequisites
2. ✅ Enable required GCP APIs
3. ✅ Create initial infrastructure (DNS zone, GKE cluster)
4. ⏸️ **Pause for DNS configuration** (you'll need to update nameservers)
5. ✅ Deploy full infrastructure
6. ✅ Install Langfuse via Helm

### 5. Configure DNS

When the script pauses, you'll see nameservers like:

```
DNS nameservers for langfuse.yourdomain.com:
  - ns-cloud-a1.googledomains.com.
  - ns-cloud-a2.googledomains.com.
  - ns-cloud-a3.googledomains.com.
  - ns-cloud-a4.googledomains.com.
```

**Update your domain's nameservers** with your DNS provider using these values, then press Enter to continue.

### 6. Access Langfuse

After deployment completes (20-30 minutes), access Langfuse at:
```
https://langfuse.yourdomain.com
```

> **Note:** SSL certificates may take up to 20 minutes to provision. If you see SSL errors initially, wait and try again.

## Configuration Options

### Environment-Specific Configurations

#### Development Environment
For cost optimization in development:

```bash
# deploy.config.local
DATABASE_TIER="db-standard-1"
DATABASE_EDITION="ENTERPRISE"
DATABASE_AVAILABILITY="ZONAL"
CACHE_TIER="BASIC"
DELETION_PROTECTION="false"
```

#### Production Environment
Use the defaults or enhance for high-scale:

```bash
# deploy.config.local
DATABASE_TIER="db-perf-optimized-N-4"
DATABASE_EDITION="ENTERPRISE_PLUS"
DATABASE_AVAILABILITY="REGIONAL"
CACHE_TIER="STANDARD_HA"
CACHE_MEMORY_GB="4"
```

### Advanced Configuration

#### Custom Network Settings
```bash
SUBNETWORK_CIDR="172.16.0.0/16"  # If 10.0.0.0/16 conflicts
```

#### Multiple Deployments
Deploy multiple instances in the same project:

```bash
DEPLOYMENT_NAME="langfuse-prod"
DOMAIN="langfuse-prod.yourdomain.com"

# For another instance:
DEPLOYMENT_NAME="langfuse-staging"
DOMAIN="langfuse-staging.yourdomain.com"
```

## Deployment Architecture

The deployment creates:

```
┌─────────────────────────────────────────────────────────────┐
│                        Google Cloud                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │   Cloud DNS     │  │     VPC      │  │  Load Balancer  │ │
│  │  (DNS Zone)     │  │  (Networking)│  │   (Ingress)     │ │
│  └─────────────────┘  └──────────────┘  └─────────────────┘ │
│                                                             │
│  ┌─────────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │  GKE Cluster    │  │  Cloud SQL   │  │ Memorystore     │ │
│  │  (Kubernetes)   │  │ (PostgreSQL) │  │   (Redis)       │ │
│  └─────────────────┘  └──────────────┘  └─────────────────┘ │
│                                                             │
│  ┌─────────────────┐  ┌──────────────┐                     │
│  │ Cloud Storage   │  │   KMS Keys   │                     │
│  │   (Buckets)     │  │ (Encryption) │                     │
│  └─────────────────┘  └──────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

## Post-Deployment

### Access Your Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials langfuse --region=us-central1 --project=YOUR_PROJECT_ID

# Check Langfuse pods
kubectl get pods -n langfuse

# View Langfuse logs
kubectl logs -f deployment/langfuse -n langfuse
```

### Monitor SSL Certificate

```bash
# Check certificate status
gcloud compute ssl-certificates list

# Watch for ACTIVE status
gcloud compute ssl-certificates describe langfuse --format="get(managed.status)"
```

### Scaling

```bash
# Scale Langfuse deployment
kubectl scale deployment langfuse --replicas=3 -n langfuse

# Scale GKE nodes (if needed)
gcloud container clusters resize langfuse --num-nodes=3 --region=us-central1
```

## Troubleshooting

### Common Issues

#### 1. SSL Certificate Issues
```bash
# Check certificate status
gcloud compute ssl-certificates list

# If still PROVISIONING, wait up to 20 minutes
# If FAILED_NOT_VISIBLE, check DNS propagation
```

#### 2. DNS Not Resolving
```bash
# Check DNS propagation
nslookup langfuse.yourdomain.com

# Verify nameservers are updated
dig NS yourdomain.com
```

#### 3. Pods Not Starting
```bash
# Check pod status
kubectl get pods -n langfuse

# View pod logs
kubectl describe pod POD_NAME -n langfuse
kubectl logs POD_NAME -n langfuse
```

#### 4. Database Connection Issues
```bash
# Check database status
gcloud sql instances list

# Test connection from pod
kubectl exec -it POD_NAME -n langfuse -- pg_isready -h DATABASE_IP
```

### Getting Help

1. **Check the logs:**
   ```bash
   kubectl logs -f deployment/langfuse -n langfuse
   ```

2. **Verify all resources:**
   ```bash
   terraform show
   ```

3. **GCP Console:** Check [GCP Console](https://console.cloud.google.com) for resource status

4. **Community Support:**
   - [Langfuse Documentation](https://langfuse.com/docs)
   - [Langfuse Discord](https://langfuse.com/discord)
   - [GitHub Issues](https://github.com/langfuse/langfuse-terraform-gcp/issues)

## Cleanup

To destroy all resources (⚠️ **This will delete all data**):

```bash
terraform destroy
```

For development environments with `deletion_protection=false`, this will work immediately.
For production environments, you may need to:

1. Disable deletion protection in the console first, or
2. Set `deletion_protection=false` in config and run `terraform apply` first

## Cost Estimation

### Development Environment
- **GKE:** ~$75/month (small cluster)
- **Cloud SQL:** ~$25/month (db-standard-1, zonal)
- **Redis:** ~$15/month (basic tier)
- **Storage/Network:** ~$5/month
- **Total:** ~$120/month

### Production Environment
- **GKE:** ~$150/month (regional cluster)
- **Cloud SQL:** ~$150/month (perf-optimized, regional)
- **Redis:** ~$50/month (standard-ha)
- **Storage/Network:** ~$10/month
- **Total:** ~$360/month

> Costs are estimates and may vary based on usage, region, and actual configuration.

## Security Considerations

The deployment includes security best practices:

- ✅ **Network isolation** with private subnets
- ✅ **Encryption at rest** for databases and storage
- ✅ **Encryption in transit** with TLS/SSL
- ✅ **IAM service accounts** with minimal permissions
- ✅ **Workload Identity** for secure pod-to-GCP communication
- ✅ **Firewall rules** restricting access
- ✅ **KMS encryption keys** for sensitive data

For additional security, consider:
- Setting up VPC Service Controls
- Enabling audit logging
- Implementing network policies
- Regular security scanning

## Next Steps

After successful deployment:

1. **Create your first project** in Langfuse
2. **Set up integrations** with your LLM applications
3. **Configure users and permissions**
4. **Set up monitoring** and alerting
5. **Plan for backups** and disaster recovery

For more information, visit the [Langfuse Documentation](https://langfuse.com/docs). 