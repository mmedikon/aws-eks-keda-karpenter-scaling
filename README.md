**EKS Autoscaling with Karpenter + KEDA
**
Event-driven pod autoscaling (KEDA) combined with fast, cost-optimized node autoscaling (Karpenter) on Amazon EKS.

Karpenter watches for unschedulable pods and provisions right-sized EC2 nodes (on-demand or spot) in seconds, then consolidates/removes them when no longer needed.
KEDA scales workloads based on external event sources (SQS queue depth, Kafka lag, Prometheus queries, cron schedules, etc.) instead of just CPU/memory.

Together: KEDA decides when to scale pods based on real signals, and Karpenter makes sure there's always capacity to run them.

Event source (SQS/Kafka/Prometheus)
        │
        ▼
   KEDA ScaledObject ──► HPA ──► Deployment scales pods
                                       │
                                       ▼
                         Pending pods (no capacity)
                                       │
                                       ▼
                          Karpenter provisions nodes
                                       │
                                       ▼
                              Pods scheduled & running

                              
