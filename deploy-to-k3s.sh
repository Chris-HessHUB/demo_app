#!/bin/bash

#############################################################################
# Flask-MySQL K3s Deployment Script
# Description: Deploys a Flask application with MySQL backend to k3s cluster
# Author: DevOps Team
# Date: $(date +%Y-%m-%d)
#############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_DIR="/home/ubuntu/flask-mysql-k3s"  # Update this path to match your cloned repo location
NAMESPACE_FLASK="flask-app"
NAMESPACE_MYSQL="mysql"
MYSQL_POD_LABEL="app=mysql"
FLASK_POD_LABEL="app=flask"

#############################################################################
# Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 could not be found. Please install $1 first."
        exit 1
    fi
}

wait_for_pod() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}  # Default timeout 5 minutes
    
    print_info "Waiting for pods with label '$label' in namespace '$namespace' to be ready..."
    
    if kubectl wait --for=condition=ready pod \
        --selector=$label \
        --namespace=$namespace \
        --timeout=${timeout}s 2>/dev/null; then
        print_success "Pods are ready!"
        return 0
    else
        print_warning "Pods did not become ready within ${timeout} seconds"
        return 1
    fi
}

#############################################################################
# Pre-flight Checks
#############################################################################

print_header "Pre-flight Checks"

# Check for required commands
print_info "Checking for required commands..."
check_command kubectl
check_command grep
check_command awk

# Verify k3s is running
print_info "Verifying k3s cluster is accessible..."
if kubectl cluster-info &> /dev/null; then
    print_success "K3s cluster is accessible"
    kubectl cluster-info | head -2
else
    print_error "Cannot connect to k3s cluster. Please ensure k3s is running."
    exit 1
fi

# Check if project directory exists
print_info "Checking project directory..."
if [ ! -d "$PROJECT_DIR" ]; then
    print_error "Project directory $PROJECT_DIR does not exist."
    print_info "Please update the PROJECT_DIR variable in this script or clone the repository."
    exit 1
fi
cd "$PROJECT_DIR"
print_success "Project directory found: $PROJECT_DIR"

# List all manifest files
print_info "Found the following Kubernetes manifests:"
ls -la *.yaml

#############################################################################
# Clean up any existing deployment (optional)
#############################################################################

print_header "Cleanup Check"

# Check if namespaces already exist
if kubectl get namespace $NAMESPACE_FLASK &> /dev/null; then
    print_warning "Namespace '$NAMESPACE_FLASK' already exists."
    read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting namespace $NAMESPACE_FLASK..."
        kubectl delete namespace $NAMESPACE_FLASK --wait=true
        print_success "Namespace deleted"
    fi
fi

if kubectl get namespace $NAMESPACE_MYSQL &> /dev/null; then
    print_warning "Namespace '$NAMESPACE_MYSQL' already exists."
    read -p "Do you want to delete and recreate it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting namespace $NAMESPACE_MYSQL..."
        kubectl delete namespace $NAMESPACE_MYSQL --wait=true
        print_success "Namespace deleted"
    fi
fi

#############################################################################
# Deploy Namespaces
#############################################################################

print_header "Creating Namespaces"

print_info "Applying namespaces.yaml..."
kubectl apply -f namespaces.yaml
print_success "Namespaces created"
kubectl get namespaces | grep -E "(flask-app|mysql|NAME)"

#############################################################################
# Deploy MySQL Components
#############################################################################

print_header "Deploying MySQL Database"

# Deploy MySQL ConfigMap for initialization
print_info "Creating MySQL initialization ConfigMap..."
kubectl apply -f mysql-initdb.yaml
print_success "MySQL initialization ConfigMap created"

# Deploy MySQL StatefulSet
print_info "Deploying MySQL StatefulSet..."
kubectl apply -f mysql-statefulset.yaml
print_success "MySQL StatefulSet deployed"

# Deploy MySQL Service
print_info "Creating MySQL Service..."
kubectl apply -f mysql-svc.yaml
print_success "MySQL Service created"

# Wait for MySQL to be ready
wait_for_pod $NAMESPACE_MYSQL $MYSQL_POD_LABEL 180

# Verify MySQL deployment
print_info "MySQL deployment status:"
kubectl get all -n $NAMESPACE_MYSQL

# Check MySQL pod logs
print_info "Checking MySQL pod logs for initialization..."
sleep 5  # Give MySQL a moment to initialize
MYSQL_POD=$(kubectl get pods -n $NAMESPACE_MYSQL -l $MYSQL_POD_LABEL -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n $NAMESPACE_MYSQL $MYSQL_POD --tail=20 | grep -i "ready for connections" || true

#############################################################################
# Deploy Flask Application
#############################################################################

print_header "Deploying Flask Application"

# Deploy database credentials Secret
print_info "Creating database credentials Secret..."
kubectl apply -f db-credentials.yaml
print_success "Database credentials Secret created"

# Deploy Flask ConfigMap
print_info "Creating Flask ConfigMap..."
kubectl apply -f flask-config.yaml
print_success "Flask ConfigMap created"

# Deploy Flask Deployment
print_info "Deploying Flask application..."
kubectl apply -f flask-deployment.yaml
print_success "Flask Deployment created"

# Deploy Flask Service
print_info "Creating Flask Service (LoadBalancer)..."
kubectl apply -f flask-svc.yaml
print_success "Flask Service created"

# Wait for Flask pods to be ready
wait_for_pod $NAMESPACE_FLASK $FLASK_POD_LABEL 180

# Verify Flask deployment
print_info "Flask deployment status:"
kubectl get all -n $NAMESPACE_FLASK

#############################################################################
# Verify Complete Deployment
#############################################################################

print_header "Deployment Verification"

# Check all pods across both namespaces
print_info "All pods status:"
kubectl get pods -n $NAMESPACE_MYSQL
echo
kubectl get pods -n $NAMESPACE_FLASK

# Check services
print_info "All services:"
kubectl get svc -n $NAMESPACE_MYSQL
echo
kubectl get svc -n $NAMESPACE_FLASK

# Check PersistentVolumeClaims
print_info "PersistentVolumeClaims:"
kubectl get pvc -n $NAMESPACE_MYSQL

#############################################################################
# Get Application Access Information
#############################################################################

print_header "Application Access Information"

# Get Flask service details
FLASK_SVC_TYPE=$(kubectl get svc flask-svc -n $NAMESPACE_FLASK -o jsonpath='{.spec.type}')
print_info "Flask Service Type: $FLASK_SVC_TYPE"

if [ "$FLASK_SVC_TYPE" == "LoadBalancer" ]; then
    # For k3s, LoadBalancer services are handled by ServiceLB (Klipper)
    print_info "Checking LoadBalancer status..."
    
    # Get the external IP (might be pending initially)
    EXTERNAL_IP=$(kubectl get svc flask-svc -n $NAMESPACE_FLASK -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    if [ -z "$EXTERNAL_IP" ]; then
        # If no external IP, might be using node IP
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        NODE_PORT=$(kubectl get svc flask-svc -n $NAMESPACE_FLASK -o jsonpath='{.spec.ports[0].nodePort}')
        
        print_warning "LoadBalancer IP is pending. In k3s, you can access the application using:"
        print_success "Node IP: http://$NODE_IP"
        if [ ! -z "$NODE_PORT" ]; then
            print_success "NodePort: http://$NODE_IP:$NODE_PORT"
        fi
    else
        print_success "Flask application is accessible at: http://$EXTERNAL_IP"
    fi
fi

# Alternative access method using port-forward
print_info "\nAlternatively, you can access the application using port-forward:"
echo "kubectl port-forward -n $NAMESPACE_FLASK svc/flask-svc 8080:80"
echo "Then access at: http://localhost:8080"

#############################################################################
# Test Database Connectivity
#############################################################################

print_header "Testing Database Connectivity"

print_info "Testing MySQL connectivity from Flask pod..."
FLASK_POD=$(kubectl get pods -n $NAMESPACE_FLASK -l $FLASK_POD_LABEL -o jsonpath='{.items[0].metadata.name}')

# Check if Flask pod can resolve MySQL service
print_info "Checking DNS resolution of MySQL service..."
kubectl exec -n $NAMESPACE_FLASK $FLASK_POD -- nslookup mysql-svc.mysql.svc.cluster.local || true

#############################################################################
# Troubleshooting Commands
#############################################################################

print_header "Useful Commands for Troubleshooting"

cat << EOF
# Check Flask application logs:
kubectl logs -n $NAMESPACE_FLASK -l $FLASK_POD_LABEL -f

# Check MySQL logs:
kubectl logs -n $NAMESPACE_MYSQL -l $MYSQL_POD_LABEL -f

# Access MySQL shell:
kubectl exec -it -n $NAMESPACE_MYSQL $MYSQL_POD -- mysql -u root -prootpassword

# Test MySQL connection from Flask pod:
kubectl exec -it -n $NAMESPACE_FLASK $FLASK_POD -- /bin/sh

# Scale Flask deployment:
kubectl scale deployment flask-deployment -n $NAMESPACE_FLASK --replicas=3

# Check events in namespaces:
kubectl get events -n $NAMESPACE_FLASK --sort-by='.lastTimestamp'
kubectl get events -n $NAMESPACE_MYSQL --sort-by='.lastTimestamp'

# Delete everything (cleanup):
kubectl delete namespace $NAMESPACE_FLASK
kubectl delete namespace $NAMESPACE_MYSQL
EOF

#############################################################################
# Summary
#############################################################################

print_header "Deployment Summary"

print_success "Flask-MySQL application has been successfully deployed to k3s!"
print_info "MySQL is running in namespace: $NAMESPACE_MYSQL"
print_info "Flask app is running in namespace: $NAMESPACE_FLASK"
print_info "Flask replicas: 2"
print_info "MySQL replicas: 1 (StatefulSet)"
print_info "Storage: 1Gi persistent volume for MySQL"

echo -e "\n${GREEN}Deployment completed successfully!${NC}"

# Optional: Show real-time pod status
print_header "Real-time Pod Status (Press Ctrl+C to exit)"
watch -n 2 "kubectl get pods -n $NAMESPACE_MYSQL && echo && kubectl get pods -n $NAMESPACE_FLASK"
