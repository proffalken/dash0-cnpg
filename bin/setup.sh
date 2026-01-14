#!/bin/bash

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Setup script for deploying CloudNative PostgreSQL with Dash0 monitoring.

OPTIONS:
  -d, --dataset NAME    Specify the Dash0 dataset name to send telemetry data to.
                        If not specified, the default dataset will be used.
  -h, --help            Display this help message and exit.

REQUIRED ENVIRONMENT VARIABLES:
  DASH0_AUTH_TOKEN      Your Dash0 authentication token
  DASH0_ENDPOINT        Your Dash0 endpoint URL
  DASH0_API_ENDPOINT    Your Dash0 API endpoint URL

EXAMPLES:
  # Use default dataset
  ./$(basename "$0")

  # Send data to a specific dataset
  ./$(basename "$0") --dataset magnus
  ./$(basename "$0") -d production

EOF
  exit 0
}

### Parse command line arguments
DATASET_NAME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -d|--dataset)
      if [[ -z "$2" || "$2" == -* ]]; then
        echo "=== ERROR: --dataset requires a value"
        exit 1
      fi
      DATASET_NAME="$2"
      shift 2
      ;;
    *)
      echo "=== ERROR: Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

### Validate dataset name if provided
if [[ -n "$DATASET_NAME" ]]; then
  # Check for invalid characters (allow alphanumeric, hyphens, underscores)
  if [[ ! "$DATASET_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "=== ERROR: Dataset name '$DATASET_NAME' contains invalid characters."
    echo "Only alphanumeric characters, hyphens, and underscores are allowed."
    exit 1
  fi
  echo "=== Using Dash0 dataset: $DATASET_NAME"
fi

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

### Set dataset flag for helm if dataset name was provided
DATASET_FLAG=""
if [[ -n "$DATASET_NAME" ]]; then
  DATASET_FLAG="--set operator.dash0Export.dataset=$DATASET_NAME"
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
