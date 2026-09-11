**EKS Autoscaling using KEDA and Karpenter**

Event-driven pod autoscaling (KEDA) combined with fast, cost-optimized node autoscaling (Karpenter) on Amazon EKS.

**Karpenter** watches for unschedulable pods and provisions right-sized EC2 nodes (on-demand or spot) in seconds, then consolidates/removes them when no longer needed.
 **KEDA** scales workloads based on external event sources (SQS queue depth, Kafka lag, Prometheus queries, cron schedules, etc.) instead of just CPU/memory.

Together: KEDA decides when to scale pods based on real signals, and Karpenter makes sure there's always capacity to run them.



Event source (SQS/Kafka/Prometheus)
       |
       |
       |
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

                              
****Installation****

           _terraform init__

           __terffaform plan__
  
           _terraform apply__
**
**Deploy Nodeclass and Nodepools object for Karpenter****

            __kubectl apply -f default-nodeclass.yaml_

           _kubectl apply -f default_nodepool.yaml__

****Deploy ScaledObject and Trigger Authentication for KEDA****

           _Kubectl apply -f kedascal.yaml_

**Uninstallation**

          _ terraform destroy_
