#!/usr/bin/env bash
# Phase 1 deployment helper: echo bot on a VM, Cloud Run and a Cloud Function (gen 2).
# Run from the repo root in Cloud Shell:   bash tools/phase1_deploy.sh
# Teardown is NOT done here: see TASKS.md Task 11 (only after a green CI run).
set -euo pipefail

export PROJECT=$(gcloud config get-value project)
export REGION=us-central1
export ZONE=us-central1-a
export IMAGE=$REGION-docker.pkg.dev/$PROJECT/eurecomgpt/echo-bot:v1
PNUM=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
SA="$PNUM-compute@developer.gserviceaccount.com"

step() { echo; echo "=== $* ==="; }

step "Task 1: enable APIs"
gcloud services enable artifactregistry.googleapis.com run.googleapis.com \
  cloudfunctions.googleapis.com cloudbuild.googleapis.com compute.googleapis.com \
  logging.googleapis.com

step "IAM: default compute SA can pull images and build functions"
for role in roles/artifactregistry.reader roles/cloudbuild.builds.builder \
            roles/logging.logWriter roles/storage.objectViewer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA" --role="$role" --condition=None --quiet >/dev/null
done

step "Task 3: Artifact Registry repo + image"
gcloud artifacts repositories describe eurecomgpt --location="$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create eurecomgpt --repository-format=docker \
    --location="$REGION" --description="EurecomGPT images"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker build -t "$IMAGE" phase-1-echo-bot
docker push "$IMAGE"
gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT/eurecomgpt" \
  --include-tags --format='table(package,tags,createTime,sizeBytes)'

step "Task 4: custom VPC echo-net / echo-subnet + firewall rules"
gcloud compute networks describe echo-net >/dev/null 2>&1 || \
  gcloud compute networks create echo-net --subnet-mode=custom
gcloud compute networks subnets describe echo-subnet --region="$REGION" >/dev/null 2>&1 || \
  gcloud compute networks subnets create echo-subnet --network=echo-net \
    --region="$REGION" --range=10.10.0.0/24
gcloud compute firewall-rules describe allow-echo-8080 >/dev/null 2>&1 || \
  gcloud compute firewall-rules create allow-echo-8080 --network=echo-net \
    --direction=INGRESS --allow=tcp:8080 --target-tags=echo-http --source-ranges=0.0.0.0/0
gcloud compute firewall-rules describe allow-echo-ssh >/dev/null 2>&1 || \
  gcloud compute firewall-rules create allow-echo-ssh --network=echo-net \
    --direction=INGRESS --allow=tcp:22 --target-tags=echo-http --source-ranges=0.0.0.0/0

step "Task 5: e2-micro VM running the container"
cat > /tmp/echo-startup.sh <<EOF
#!/bin/bash
set -e
if ! command -v docker >/dev/null; then
  apt-get update -y && apt-get install -y docker.io
fi
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet
docker rm -f echo-bot 2>/dev/null || true
docker pull $IMAGE
docker run -d --name echo-bot --restart=always -p 8080:8080 $IMAGE
EOF
gcloud compute instances describe echo-vm --zone="$ZONE" >/dev/null 2>&1 || \
  gcloud compute instances create echo-vm --zone="$ZONE" --machine-type=e2-micro \
    --subnet=echo-subnet --tags=echo-http \
    --image-family=debian-12 --image-project=debian-cloud \
    --service-account="$SA" --scopes=cloud-platform \
    --metadata-from-file=startup-script=/tmp/echo-startup.sh
VM_IP=$(gcloud compute instances describe echo-vm --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

step "Task 6: Cloud Run service echo-bot"
gcloud run deploy echo-bot --image="$IMAGE" --region="$REGION" --port=8080 \
  --allow-unauthenticated --min-instances=0 --max-instances=3 --quiet
RUN_URL=$(gcloud run services describe echo-bot --region="$REGION" --format='value(status.url)')

step "Task 7: Cloud Function (gen 2) echo"
gcloud functions deploy echo --gen2 --runtime=python311 --region="$REGION" \
  --source=phase-1-echo-bot --entry-point=echo --trigger-http \
  --allow-unauthenticated --quiet
FN_URL=$(gcloud functions describe echo --gen2 --region="$REGION" --format='value(serviceConfig.uri)')

step "Waiting for the VM container (startup script installs Docker)"
for i in $(seq 1 40); do
  if curl -sf "http://$VM_IP:8080/health" >/dev/null; then echo "VM up"; break; fi
  sleep 10
done

step "Correctness checks (GET + JSON POST)"
for u in "http://$VM_IP:8080" "$RUN_URL" "$FN_URL"; do
  echo "$u"
  echo "  GET : $(curl -s "$u/echo?msg=hi")"
  echo "  POST: $(curl -s -X POST "$u/echo" -H 'Content-Type: application/json' -d '{"message":"hello"}')"
done

cat > ~/phase1_urls.env <<EOF
VM_URL=http://$VM_IP:8080
RUN_URL=$RUN_URL
FN_URL=$FN_URL
EOF
step "URLs saved to ~/phase1_urls.env"
cat ~/phase1_urls.env
echo
echo "gcloud run services list:"
gcloud run services list --format='table(metadata.name,status.url,metadata.labels)'
echo
echo "NEXT: leave all three endpoints alone ~15 min, then run tools/phase1_measure.sh"
