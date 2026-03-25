#!/bin/bash
# =============================================================
# vault-init.sh — CSO2 HashiCorp Vault Secret Seeder
# =============================================================
# Usage (from Git Bash):
#   chmod +x Infrastructure/cso2/scripts/vault-init.sh
#   ./Infrastructure/cso2/scripts/vault-init.sh cso2-dev
# =============================================================

set -e

# ----------------------------------------------------------------
# PASSWORDS — must match your .env.* files exactly
# ----------------------------------------------------------------
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="Cso2Postgres@2024"
CSO2_USER="cso2"
CSO2_PASSWORD="Cso2App@2024"
MONGO_ROOT_USER="admin"
MONGO_ROOT_PASSWORD="Cso2Mongo@2024"
# ----------------------------------------------------------------

NAMESPACE=${1:-cso2-dev}

echo "========================================"
echo "=== CSO2 Vault Init Script           ==="
echo "========================================"
echo "Namespace : $NAMESPACE"
echo ""

echo "[0/5] Finding Vault pod..."
VAULT_POD=$(kubectl get pod -n "$NAMESPACE" -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)

if [ -z "$VAULT_POD" ]; then
  echo ""
  echo "ERROR: No vault pod found in namespace '$NAMESPACE'"
  echo "Fix: Make sure you ran:"
  echo "  kubectl create namespace cso2-dev"
  echo "  kubectl apply -k Infrastructure/cso2/k8s/overlays/dev"
  exit 1
fi

echo "      Found: $VAULT_POD"
echo ""

echo "[1/5] Waiting for Vault pod to be ready (up to 2 minutes)..."
kubectl wait --for=condition=ready pod "$VAULT_POD" -n "$NAMESPACE" --timeout=120s
echo "      Vault is ready."
echo ""

echo "[2/5] Enabling KV v2 secrets engine..."
kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
  env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
  vault secrets enable -path=secret kv-v2 2>/dev/null \
  && echo "      KV v2 enabled at secret/" \
  || echo "      KV already enabled, skipping."
echo ""

echo "[3/5] Writing PostgreSQL secrets..."
kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
  env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv put secret/cso2/postgresql \
    POSTGRES_USER="$POSTGRES_USER" \
    POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    CSO2_USER="$CSO2_USER" \
    CSO2_PASSWORD="$CSO2_PASSWORD"
echo "      Written: secret/cso2/postgresql"
echo ""

echo "[4/5] Writing MongoDB secrets..."
kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
  env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv put secret/cso2/mongodb \
    MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USER" \
    MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD"
echo "      Written: secret/cso2/mongodb"
echo ""

echo "[5/5] Writing per-service secrets..."
echo ""

echo "  --- PostgreSQL services ---"
for SERVICE in user-identity-service order-service support-service reporting-and-analysis-service; do
  kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
    env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
    vault kv put "secret/cso2/services/$SERVICE" \
      DATABASE_USERNAME="$CSO2_USER" \
      DATABASE_PASSWORD="$CSO2_PASSWORD"
  echo "  Written: secret/cso2/services/$SERVICE"
done

echo ""

MONGO_URI="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@mongodb:27017"

echo "  --- MongoDB services ---"
for SERVICE in product-catalogue-service content-service notifications-service shoppingcart-wishlist-service support-service; do
  kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
    env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
    vault kv put "secret/cso2/services/$SERVICE-mongo" \
      MONGODB_URI="${MONGO_URI}"
  echo "  Written: secret/cso2/services/$SERVICE-mongo"
done

echo ""
echo "  --- Shared app secrets (mail, twilio, AI) ---"
kubectl exec -n "$NAMESPACE" "$VAULT_POD" -- \
  env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv put secret/cso2/app-secrets \
    mail_username="user@example.com" \
    mail_password="change_me" \
    twilio_account_sid="change_me" \
    twilio_auth_token="change_me" \
    twilio_phone_number="change_me" \
    gemini_api_key="change_me"
echo "  Written: secret/cso2/app-secrets (mail, twilio, gemini — update values before use)"

echo ""
echo "========================================"
echo "=== Done! All secrets stored in Vault ==="
echo "========================================"
echo ""
echo "Verify in browser:"
echo "  kubectl port-forward -n $NAMESPACE $VAULT_POD 8200:8200"
echo "  Open: http://localhost:8200  (Token: root)"
echo ""
echo "Verify in terminal:"
echo "  kubectl exec -n $NAMESPACE $VAULT_POD -- env VAULT_TOKEN=root VAULT_ADDR=http://127.0.0.1:8200 vault kv get secret/cso2/postgresql"
