#!/bin/bash

echo -n "=== INFO: Working in $(pwd)"

### Check the environment variables are set
if [[ -z "$DASH0_AUTH_TOKEN" ]]; then
  echo -n "=== ERROR: Dash0 Authentication Token is not set.  Please run \"export DASH0_AUTH_TOKEN=<your auth token here>\" before running this script"
  exit 2
else
  echo "=== Dash0 Authentication Token set. Proceeding..."
fi

if [[ -z "$DASH0_ENDPOINT" ]]; then
  echo -n "=== ERROR: Dash0 Endpoint is not set.  Please run \"export DASH0_ENDPOINT=<your endpoint here>\" before running this script"
  exit 2
else
  echo "=== Dash0 Endpoint set. Proceeding..."
fi

if [[ -z "$DASH0_API_ENDPOINT" ]]; then
  echo -n "=== ERROR: Dash0 API Endpoint is not set.  Please run \"export DASH0_API_ENDPOINT=<your api endpoint here>\" before running this script"
  exit 2
else
  echo "=== Dash0 API Endpoint set. Proceeding..."
fi

### Check for optional dataset argument
DATASET_FLAG=""
if [[ -n "$1" ]]; then
  DATASET_FLAG="--set operator.dash0Export.dataset=$1"
  echo "=== Using Dash0 dataset: $1"
fi

echo -n "=== Installing helm charts"
helm repo add dash0-operator https://dash0hq.github.io/dash0-operator
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo -n "=== Adding the Cloudnative PostgreSQL controller to your kubernetes cluster"
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/releases/cnpg-1.28.0.yaml

echo -n "=== Setting up the namespaces"
kubectl create ns pgsql

echo -n "=== Installing the Dash0 Operator"
kubectl create namespace dash0-system
kubectl create secret generic dash0-authorization-secret \
  --namespace dash0-system \
  --from-literal=token="${DASH0_AUTH_TOKEN}"

helm upgrade --install \
  --namespace dash0-system \
  --set operator.dash0Export.enabled=true \
  --set operator.dash0Export.endpoint=${DASH0_ENDPOINT} \
  --set operator.dash0Export.apiEndpoint=${DASH0_API_ENDPOINT} \
  ${DATASET_FLAG} \
  --set operator.dash0Export.secretRef.name=dash0-authorization-secret \
  --set operator.dash0Export.secretRef.key=token \
  dash0-operator \
  dash0-operator/dash0-operator

echo -n "=== Applying the Dash0 Operator to the pgsql namespace"
kubectl apply -n pgsql -f values/dash0/ns-enable.yaml

echo -n "=== Deploying the Cloudnative PGSQL cluster"
kubectl apply -f values/cnpg/cluster-values.yaml

echo -n "=== Deploying the testdb database"
kubectl apply -f values/cnpg/test-database.yaml

echo -n "=== Deploying the OpenTelemetry Collectors"
helm upgrade --install otel-collector-ds open-telemetry/opentelemetry-collector --namespace opentelemetry  -f values/otelcol/daemonset-values.yaml
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector --namespace opentelemetry  -f values/otelcol/deployment-values.yaml

echo -n "=== Setup finished, you should now be able to install the dashboards from the integrations into Dash0 and see metrics and logs appear shortly."
