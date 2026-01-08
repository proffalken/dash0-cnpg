# Dash0 CNPG

Example Kubernetes values for [CloudNative Postgresql](https://cloudnative-pg.io/) and the [Open Telemetry Collector](https://opentelemetry.io/docs/collector/) to send data to [Dash0](https://dash0.com).

## Setup

Make sure you have a working kubernetes cluster (I use [k3s](https://k3s.io/)) and that `kubectl get nodes` returns a list of the nodes in the cluster.

Once that's working, clone this repo to your local machine and run `./bin/setup.sh`, which will show you the variables that you need to set and then install everything.
