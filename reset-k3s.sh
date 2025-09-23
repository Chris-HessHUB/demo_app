#!/bin/bash

#############################################
# K3s Kubernetes Environment Reset Script
# This script will clean your k3s cluster
# to a factory-like state
#############################################

set -e  # Exit on any error

echo "========================================="
echo "Starting K3s Environment Reset"
echo "========================================="

# Function to wait for namespace deletion
wait_for_namespace_deletion() {
    local namespace=$1
    local max_wait=60
    local counter=0
    
    echo "Waiting for namespace '$namespace' to be deleted..."
    while kubectl get namespace "$namespace" &>/dev/null; do
        if [ $counter -ge $max_wait ]; then
            echo "Warning: Namespace '$namespace' is taking too long to delete"
            break
        fi
        sleep 1
        ((counter++))
    done
}

echo ""
echo "Step 1: Deleting all non-system namespaces..."
echo "---------------------------------------------"

# Get all namespaces except kube-system, kube-public, kube-node-lease, default
NAMESPACES=$(kubectl get namespaces -o name | grep -v -E 'namespace/(kube-system|kube-public|kube-node-lease|default)' | cut -d/ -f2)

if [ -z "$NAMESPACES" ]; then
    echo "No custom namespaces found to delete."
else
    for ns in $NAMESPACES; do
        echo "Deleting namespace: $ns"
        kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null || true
        wait_for_namespace_deletion "$ns"
    done
fi

echo ""
echo "Step 2: Cleaning up resources in default namespace..."
echo "---------------------------------------------"

# Delete all deployments, services, pods, etc. in default namespace
echo "Deleting deployments..."
kubectl delete deployments --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting statefulsets..."
kubectl delete statefulsets --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting daemonsets..."
kubectl delete daemonsets --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting services (except kubernetes service)..."
kubectl delete services --all -n default --field-selector metadata.name!=kubernetes --force --grace-period=0 2>/dev/null || true

echo "Deleting pods..."
kubectl delete pods --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting configmaps..."
kubectl delete configmaps --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting secrets..."
kubectl delete secrets --all -n default --force --grace-period=0 2>/dev/null || true

echo "Deleting persistent volume claims..."
kubectl delete pvc --all -n default --force --grace-period=0 2>/dev/null || true

echo ""
echo "Step 3: Cleaning up cluster-wide resources..."
echo "---------------------------------------------"

echo "Deleting persistent volumes..."
kubectl delete pv --all --force --grace-period=0 2>/dev/null || true

echo "Deleting ingresses from all namespaces..."
kubectl delete ingress --all --all-namespaces --force --grace-period=0 2>/dev/null || true

echo "Deleting network policies from all namespaces..."
kubectl delete networkpolicy --all --all-namespaces --force --grace-period=0 2>/dev/null || true

echo ""
echo "Step 4: Cleaning up Helm releases (if any)..."
echo "---------------------------------------------"
if command -v helm &> /dev/null; then
    echo "Helm found, cleaning up releases..."
    helm list --all-namespaces -q | xargs -I {} helm uninstall {} --namespace $(helm list --all-namespaces | grep {} | awk '{print $2}') 2>/dev/null || true
else
    echo "Helm not found, skipping..."
fi

echo ""
echo "Step 5: Final cleanup..."
echo "---------------------------------------------"

# Force cleanup of any terminating namespaces
echo "Forcing cleanup of any stuck terminating namespaces..."
for ns in $(kubectl get ns --field-selector status.phase=Terminating -o name | cut -d/ -f2); do
    echo "Force removing finalizers from namespace: $ns"
    kubectl get namespace "$ns" -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
done

echo ""
echo "Step 6: Verifying clean state..."
echo "---------------------------------------------"

echo "Current namespaces:"
kubectl get namespaces

echo ""
echo "Resources in default namespace:"
kubectl get all -n default

echo ""
echo "Persistent Volumes:"
kubectl get pv

echo ""
echo "========================================="
echo "K3s Environment Reset Complete!"
echo "Your cluster is now in a clean state."
echo "========================================="
