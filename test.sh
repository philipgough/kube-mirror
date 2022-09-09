#!/usr/bin/env bash

set -e -x -o pipefail

function cleanup {
  echo 'deleting cluster'
  kind delete cluster --name jsonnet-test
}

trap cleanup EXIT


function run() {
    setup_cluster
    deploy_test_services

    # Port forward the proxy
    kubectl -n mirror port-forward svc/mirror-proxy 8080:8080 > /dev/null 2>&1 &
    if [ $? -ne 0 ]; then
        echo "Failed to port forward"
        exit 1
    fi

    while ! timeout 1 bash -c "echo > /dev/tcp/localhost/8080"; do
      sleep 1
    done

    # Generate some traffic to increase counter
    for i in {1..5}; do curl --silent -o /dev/null localhost:8080/metrics; done
    # Compare the output of metrics to ensure traffic was mirrored
    a=`kubectl exec -n mirror svc/service-a -- wget -qO- localhost:8080/metrics | grep http_requests_total`
    b=`kubectl exec -n mirror svc/service-b -- wget -qO- localhost:8080/metrics | grep http_requests_total`
    if [ "$a" = "$b" ]; then
      echo "output is equal"
      echo "$a"
      exit 0
    else
      echo "output not equal"
      exit 1
    fi
}

function setup_cluster() {
  kind create cluster --name jsonnet-test
  kubectl create ns mirror
  kubectl -n mirror apply -f examples/
};


function deploy_test_services() {
  for x in {a..b}
  do
    cat <<EOF | kubectl apply -f -
kind: Service
apiVersion: v1
metadata:
  name: service-$x
  labels:
    tier: frontend-$x
  namespace: mirror
spec:
  selector:
    app.kubernetes.io/name: example-app-$x
  ports:
  - name: web
    protocol: TCP
    port: 8080
    targetPort: web
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app-$x
  namespace: mirror
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: example-app-$x
  replicas: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: example-app-$x
    spec:
      containers:
      - name: example-app-$x
        image: quay.io/fabxc/prometheus_demo_service
        ports:
        - name: web
          containerPort: 8080
          protocol: TCP
EOF
  done
kubectl wait -n mirror --for condition=Available --timeout=90s --all deployments
};

run
