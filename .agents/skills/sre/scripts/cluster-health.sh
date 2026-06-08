#!/usr/bin/env bash
# Read-only cluster health snapshot for the homelab single cluster.
# Uses only read verbs (get/describe/top) + flux get. Never mutates the cluster.
# Usage: ./cluster-health.sh [namespace]

set -euo pipefail

NAMESPACE="${1:-}"

echo "=== Node Status ==="
kubectl get nodes -o wide

echo ""
echo "=== Node Resources ==="
kubectl top nodes 2>/dev/null || echo "(metrics not available)"

echo ""
echo "=== Flux Kustomizations ==="
flux get kustomizations -A 2>/dev/null || echo "(flux CLI not available)"

echo ""
echo "=== Flux HelmReleases ==="
flux get helmreleases -A 2>/dev/null || echo "(flux CLI not available)"

echo ""
echo "=== ExternalSecrets (not SecretSynced) ==="
kubectl get externalsecrets -A 2>/dev/null | grep -iv "SecretSynced" || echo "All ExternalSecrets synced"

if [[ -n "$NAMESPACE" ]]; then
    echo ""
    echo "=== Namespace: $NAMESPACE ==="
    kubectl get all -n "$NAMESPACE"

    echo ""
    echo "=== Recent Events in $NAMESPACE ==="
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -15
else
    echo ""
    echo "=== Problem Pods (non-Running) ==="
    kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || echo "All pods healthy"

    echo ""
    echo "=== Recent Warning Events ==="
    kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -10
fi

echo ""
echo "=== PVC Status (not Bound) ==="
kubectl get pvc -A 2>/dev/null | grep -v "Bound" || echo "All PVCs bound"
