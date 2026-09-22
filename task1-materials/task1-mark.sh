#!/usr/bin/env bash
# 2026 전국기능경기대회 클라우드컴퓨팅 제1과제 학습용 자동 점검
# 조회 전용: AWS/Kubernetes 리소스를 생성·수정·삭제하지 않습니다.

set +e
export AWS_PAGER=""
REGION="${AWS_REGION:-ap-northeast-2}"
TOTAL="0"

green='\033[0;32m'; red='\033[0;31m'; cyan='\033[0;36m'; reset='\033[0m'

section() { printf "\n${cyan}========== %s ==========${reset}\n" "$1"; }
pass() { printf "${green}[PASS]${reset} %s (+%s)\n" "$1" "$2"; TOTAL=$(awk -v a="$TOTAL" -v b="$2" 'BEGIN{printf "%.1f",a+b}'); }
fail() { printf "${red}[FAIL]${reset} %s (+0/%s)\n" "$1" "$2"; }
exists() { [ -n "$1" ] && [ "$1" != "None" ] && [ "$1" != "null" ]; }
check() { local label="$1" points="$2"; shift 2; if "$@" >/dev/null 2>&1; then pass "$label" "$points"; else fail "$label" "$points"; fi; }

echo "AWS 제1과제 자동 채점 시작"
echo "제출시각: $(date -Iseconds)"
echo "리전: $REGION"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if ! exists "$ACCOUNT_ID"; then
  echo "[ERROR] AWS 인증 정보를 확인할 수 없습니다. CloudShell 또는 자격 증명이 설정된 환경에서 실행하세요."
  exit 1
fi
echo "ACCOUNT ID: $ACCOUNT_ID"

section "1. Networking / 2.0"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=tag:Name,Values=unicorn-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if exists "$VPC_ID"; then pass "unicorn-vpc 존재" 0.5; else fail "unicorn-vpc 존재" 0.5; fi
SUBNETS=$(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'length(Subnets)' --output text 2>/dev/null)
if [ "${SUBNETS:-0}" -ge 6 ] 2>/dev/null; then pass "Public/Private Subnet 6개 이상" 0.5; else fail "Public/Private Subnet 6개 이상" 0.5; fi
ENDPOINTS=$(aws ec2 describe-vpc-endpoints --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'length(VpcEndpoints)' --output text 2>/dev/null)
if [ "${ENDPOINTS:-0}" -ge 3 ] 2>/dev/null; then pass "S3/ECR VPC Endpoint" 0.5; else fail "S3/ECR VPC Endpoint" 0.5; fi
FLOWLOGS=$(aws ec2 describe-flow-logs --region "$REGION" --filter Name=resource-id,Values="$VPC_ID" --query 'length(FlowLogs)' --output text 2>/dev/null)
if [ "${FLOWLOGS:-0}" -ge 1 ] 2>/dev/null; then pass "VPC Flow Log" 0.5; else fail "VPC Flow Log" 0.5; fi

section "2. KMS / 1.0"
KMS_OK=0
for alias in app data platform; do
  KEY_ID=$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='alias/unicorn-kms-${alias}'].TargetKeyId|[0]" --output text 2>/dev/null)
  if exists "$KEY_ID"; then ROT=$(aws kms get-key-rotation-status --region "$REGION" --key-id "$KEY_ID" --query KeyRotationEnabled --output text 2>/dev/null); [ "$ROT" = "True" ] && KMS_OK=$((KMS_OK+1)); fi
done
if [ "$KMS_OK" -eq 3 ]; then pass "App/Data/Platform KMS 키와 자동 교체" 1.0; else fail "App/Data/Platform KMS 키와 자동 교체 ($KMS_OK/3)" 1.0; fi

section "3. S3 · DynamoDB · ECR / 3.0"
BUCKET="unicorn-web-${ACCOUNT_ID}"
check "S3 버킷 $BUCKET" 0.5 aws s3api head-bucket --bucket "$BUCKET"
S3_ENC=$(aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
if [ "$S3_ENC" = "aws:kms" ]; then pass "S3 KMS 암호화" 0.5; else fail "S3 KMS 암호화" 0.5; fi
TABLE_STATUS=$(aws dynamodb describe-table --region "$REGION" --table-name unicorn-concert-db --query 'Table.TableStatus' --output text 2>/dev/null)
if [ "$TABLE_STATUS" = "ACTIVE" ]; then pass "DynamoDB unicorn-concert-db" 0.5; else fail "DynamoDB unicorn-concert-db" 0.5; fi
PITR=$(aws dynamodb describe-continuous-backups --region "$REGION" --table-name unicorn-concert-db --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' --output text 2>/dev/null)
if [ "$PITR" = "ENABLED" ]; then pass "DynamoDB PITR" 0.5; else fail "DynamoDB PITR" 0.5; fi
check "ECR unicorn-concert-app" 0.5 aws ecr describe-repositories --region "$REGION" --repository-names unicorn-concert-app
IMAGE_COUNT=$(aws ecr describe-images --region "$REGION" --repository-name unicorn-concert-app --query 'length(imageDetails)' --output text 2>/dev/null)
if [ "${IMAGE_COUNT:-0}" -ge 1 ] 2>/dev/null; then pass "ECR 이미지 업로드" 0.5; else fail "ECR 이미지 업로드" 0.5; fi

section "4. EKS / 3.0"
CLUSTER_STATUS=$(aws eks describe-cluster --region "$REGION" --name unicorn-eks-cluster --query 'cluster.status' --output text 2>/dev/null)
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then pass "EKS 클러스터 ACTIVE" 1.0; else fail "EKS 클러스터 ACTIVE" 1.0; fi
PUBLIC_ACCESS=$(aws eks describe-cluster --region "$REGION" --name unicorn-eks-cluster --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null)
if [ "$PUBLIC_ACCESS" = "False" ]; then pass "EKS Private Control Plane" 0.5; else fail "EKS Private Control Plane" 0.5; fi
NODEGROUPS=$(aws eks list-nodegroups --region "$REGION" --cluster-name unicorn-eks-cluster --query 'length(nodegroups)' --output text 2>/dev/null)
if [ "${NODEGROUPS:-0}" -ge 2 ] 2>/dev/null; then pass "App/Addon NodeGroup" 0.5; else fail "App/Addon NodeGroup" 0.5; fi
if kubectl -n unicorn get deploy unicorn-book-app-deploy >/dev/null 2>&1 && kubectl -n unicorn get svc unicorn-book-app-svc >/dev/null 2>&1; then pass "Book App Deployment/Service" 1.0; else fail "Book App Deployment/Service" 1.0; fi

section "5. Lambda / 1.0"
LAMBDA_STATE=$(aws lambda get-function-configuration --region "$REGION" --function-name unicorn-get-booking-func --query State --output text 2>/dev/null)
if [ "$LAMBDA_STATE" = "Active" ]; then pass "unicorn-get-booking-func Active" 1.0; else fail "unicorn-get-booking-func Active" 1.0; fi

section "6. Service Endpoint / 5.5"
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" --names unicorn-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if exists "$ALB_ARN"; then pass "Internal ALB unicorn-alb" 1.0; else fail "Internal ALB unicorn-alb" 1.0; fi
LISTENERS=$(aws elbv2 describe-listeners --region "$REGION" --load-balancer-arn "$ALB_ARN" --query 'length(Listeners)' --output text 2>/dev/null)
if [ "${LISTENERS:-0}" -ge 1 ] 2>/dev/null; then pass "ALB Listener/Rules" 0.5; else fail "ALB Listener/Rules" 0.5; fi
CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].Id|[0]" --output text 2>/dev/null)
CF_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='unicorn-svc-cf'].DomainName|[0]" --output text 2>/dev/null)
if exists "$CF_ID"; then pass "CloudFront unicorn-svc-cf" 1.5; else fail "CloudFront unicorn-svc-cf" 1.5; fi
WAF_ARN=$(aws cloudfront get-distribution --id "$CF_ID" --query 'Distribution.DistributionConfig.WebACLId' --output text 2>/dev/null)
if exists "$WAF_ARN"; then pass "CloudFront WAF 연결" 1.0; else fail "CloudFront WAF 연결" 1.0; fi
if exists "$CF_DOMAIN" && curl -fsS --max-time 12 "https://${CF_DOMAIN}/health" >/dev/null 2>&1; then pass "CloudFront /health 응답" 1.5; else fail "CloudFront /health 응답" 1.5; fi

section "7. Security · Application / 3.0"
check "unicorn-audit-role" 1.0 aws iam get-role --role-name unicorn-audit-role
if kubectl -n unicorn get pods --no-headers 2>/dev/null | awk '{print $2,$3}' | grep -Eq '^[1-9][0-9]*/[1-9][0-9]* Running$'; then pass "Book App Pod Running/Ready" 1.0; else fail "Book App Pod Running/Ready" 1.0; fi
if exists "$CF_DOMAIN" && curl -fsS --max-time 12 "https://${CF_DOMAIN}/health" | grep -Eqi 'ok|healthy|success'; then pass "애플리케이션 Health 정상" 1.0; else fail "애플리케이션 Health 정상" 1.0; fi

section "8. Observability · Runtime · Grafana / 5.5"
check "Book App CloudWatch Log Group" 1.0 aws logs describe-log-groups --region "$REGION" --log-group-name-prefix /unicorn/eks/book-app
if kubectl -n monitoring get pods >/dev/null 2>&1; then pass "monitoring Namespace/Pods" 1.5; else fail "monitoring Namespace/Pods" 1.5; fi
if kubectl -n monitoring get pods 2>/dev/null | grep -qi prometheus; then pass "Prometheus" 1.0; else fail "Prometheus" 1.0; fi
if kubectl -n monitoring get pods 2>/dev/null | grep -qi grafana; then pass "Grafana" 1.0; else fail "Grafana" 1.0; fi
check "Grafana ALB" 1.0 aws elbv2 describe-load-balancers --region "$REGION" --names unicorn-grafana-alb

section "9. DynamoDB Stream 추가과제 / 6.0"
SRC_STREAM=$(aws dynamodb describe-table --region "$REGION" --table-name source-db --query 'Table.LatestStreamArn' --output text 2>/dev/null)
if exists "$SRC_STREAM"; then pass "source-db Stream 활성화" 1.5; else fail "source-db Stream 활성화" 1.5; fi
TTL=$(aws dynamodb describe-time-to-live --region "$REGION" --table-name source-db --query 'TimeToLiveDescription.TimeToLiveStatus' --output text 2>/dev/null)
if [ "$TTL" = "ENABLED" ]; then pass "source-db TTL 활성화" 1.0; else fail "source-db TTL 활성화" 1.0; fi
check "destination-db" 1.0 aws dynamodb describe-table --region "$REGION" --table-name destination-db
PROCESSOR=$(aws lambda get-function-configuration --region "$REGION" --function-name ticket-processor --query State --output text 2>/dev/null)
if [ "$PROCESSOR" = "Active" ]; then pass "ticket-processor Lambda" 1.5; else fail "ticket-processor Lambda" 1.5; fi
MAPPINGS=$(aws lambda list-event-source-mappings --region "$REGION" --function-name ticket-processor --query 'length(EventSourceMappings)' --output text 2>/dev/null)
if [ "${MAPPINGS:-0}" -ge 1 ] 2>/dev/null; then pass "DynamoDB Stream Event Source Mapping" 1.0; else fail "DynamoDB Stream Event Source Mapping" 1.0; fi

section "최종 결과"
echo "TOTAL_SCORE=${TOTAL}/30.0"
echo "RESULT_END"
echo "※ 자동 채점은 학습용 사전 점검입니다. 최종 점수는 공식 채점기준표와 교사 확인을 따릅니다."
