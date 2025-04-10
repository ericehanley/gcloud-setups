# Original Demo for v6e: https://cloud.google.com/kubernetes-engine/docs/tutorials/serve-vllm-tpu

# Set variables
# ALTERED: reservation name variable
gcloud config set project <project_id> && \
export PROJECT_ID=$(gcloud config get project) && \
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)") && \
export CLUSTER_NAME=<cluster_name> && \
export ZONE=<zone> && \
export REGION=<region> && \
export HF_TOKEN=<hf_token> && \
export CLUSTER_VERSION=1.32.2-gke.1182001 && \
export GSBUCKET=<gs_bucket> && \
export KSA_NAME=<ksa_name> && \
export NAMESPACE=<namespace>

# Create cluster
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --region=${REGION} \
    --node-locations=${ZONE} \
    --cluster-version=${CLUSTER_VERSION} \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --addons GcsFuseCsiDriver

# Create v5e Node Pool
# ALTERED: machine type, zonal, added reservation variables.
gcloud container node-pools create ct5lp-hightpu-8t-pool \
    --region=${REGION} \
    --node-locations=${ZONE} \
    --num-nodes=1 \
    --machine-type=ct5lp-hightpu-8t	 \
    --cluster=${CLUSTER_NAME} \
    --reservation-affinity=specific \
    --reservation=${RESERVATION_NAME} \
    --enable-autoscaling --total-min-nodes=1 --total-max-nodes=2

# Get credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}

# Create k8s secret for HF
kubectl create namespace ${NAMESPACE}
kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --namespace ${NAMESPACE}

# Create bucket for Cloud Storage Fuse
gcloud storage buckets create gs://${GSBUCKET} \
    --uniform-bucket-level-access

# Service account creation
kubectl create serviceaccount ${KSA_NAME} --namespace ${NAMESPACE}

# Grant read/write permissions to service account
gcloud storage buckets add-iam-policy-binding gs://${GSBUCKET} \
  --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}" \
  --role "roles/storage.objectUser"

# Update manifest with service account and bucket manually.

# Launch deployment
kubectl apply -f vllm-qwen2.5-30b.yaml -n ${NAMESPACE}

# Monitor deployment
kubectl logs -f -l app=vllm-tpu -n ${NAMESPACE}

# INFERENCE
# New terminal
export NAMESPACE=<namespace>
export CLUSTER_NAME=<cluster_name>
export ZONE=<zone>

# Get k8s credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}

# Get Service IP Address
export vllm_service=$(kubectl get service vllm-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ${NAMESPACE})

# Send prompt to endpoint
curl http://$vllm_service:8000/v1/completions \
-H "Content-Type: application/json" \
-d '{
    "model": "Qwen/Qwen2.5-32B",
    "prompt": "San Francisco is a",
    "max_tokens": 7,
    "temperature": 0
}'

# Custom Metrics Stack Driver
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml

# Add monitoring viewer role to Custom Metrics Stack Driver SA
gcloud projects add-iam-policy-binding projects/${PROJECT_ID} \
    --role roles/monitoring.viewer \
    --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/custom-metrics/sa/custom-metrics-stackdriver-adapter

# Deploy monitoring pod
kubectl apply -f vllm_pod_monitor.yaml -n ${NAMESPACE}

# Run load
chmod +x load.sh
nohup ./load.sh &

# Deploy HPA auto scaling
kubectl apply -f vllm-hpa.yaml -n ${NAMESPACE}

# Watch HPA
kubectl get hpa --watch -n ${NAMESPACE}

# Clean up
ps -ef | grep load.sh | awk '{print $2}' | xargs -n1 kill -9
gcloud container clusters delete ${CLUSTER_NAME} \
  --region=${REGION}