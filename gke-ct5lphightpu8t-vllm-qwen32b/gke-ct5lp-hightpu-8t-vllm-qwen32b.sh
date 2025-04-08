# Set variables
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
export RESERVATION_NAME=<reservation_name>

# Create (zonal for simplicity) cluster
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --cluster-version=${CLUSTER_VERSION} \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --addons GcsFuseCsiDriver

# Create v5e Node Pool
gcloud container node-pools create ct5lp-hightpu-8t-pool \
    --zone=${ZONE} \
    --num-nodes=1 \
    --machine-type=ct5lp-hightpu-8t	 \
    --cluster=${CLUSTER_NAME} \
    --reservation-affinity=specific \
    --reservation=${RESERVATION_NAME}
    --enable-autoscaling --total-min-nodes=1 --total-max-nodes=2

# Get credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION}

# Create k8s secret for HF
kubectl create namespace ${NAMESPACE}
kubectl create secret generic hf-secret \
    --from-literal=hf_api_token=${HF_TOKEN} \
    --namespace ${NAMESPACE}

# Create bucket
gcloud storage buckets create gs://${GSBUCKET} \
    --uniform-bucket-level-access

# Service account creation
kubectl create serviceaccount ${KSA_NAME} --namespace ${NAMESPACE}

# Grant permissions to service account
gcloud storage buckets add-iam-policy-binding gs://${GSBUCKET} \
  --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${KSA_NAME}" \
  --role "roles/storage.objectUser"

# Update manifest with service account and bucket
sed -i 's/KSA_NAME/$KSA_NAME/g' v5e-gke-deploy.yaml
sed -i 's/GSBUCKET/$GSBUCKET/g' v5e-gke-deploy.yaml

# New terminal
export NAMESPACE=<namespace>
export CLUSTER_NAME=<cluster_name>
export ZONE=<zone>
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}
export vllm_service=$(kubectl get service vllm-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ${NAMESPACE})
curl http://$vllm_service:8000/v1/completions \
-H "Content-Type: application/json" \
-d '{
    "model": "Qwen/Qwen2.5-32B",
    "prompt": "San Francisco is a",
    "max_tokens": 7,
    "temperature": 0
}'
