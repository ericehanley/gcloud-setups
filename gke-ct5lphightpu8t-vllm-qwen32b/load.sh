#!/bin/bash
N=<ENTER_PARALLEL_PROCESSES>
export vllm_service=$(kubectl get service vllm-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' -n ${NAMESPACE})
for i in $(seq 1 $N); do
  while true; do
    curl http://$vllm_service:8000/v1/completions -H "Content-Type: application/json" -d '{"model": "Qwen/Qwen2.5-32B", "prompt": "Write a story about san francisco", "max_tokens": 100, "temperature": 0}'
  done &  # Run in the background
done
wait