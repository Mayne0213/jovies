#!/bin/bash

# Jovies Kubernetes 배포 스크립트
# 공통 유틸리티 함수 로드
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 스크립트 설정
setup_script

print_usage() {
    echo ""
    echo "사용법: $(basename "$0") [-n NAMESPACE] [-c CONTEXT] [--app-image IMAGE[:TAG]] [--build|--no-build] [--tag TAG] [--dry-run] [--yes]"
    echo "  -n, --namespace   Kubernetes 네임스페이스 (기본: jovies)"
    echo "  -c, --context     kubectl 컨텍스트 지정 (kubectl config current-context 기본)"
    echo "      --app-image   app 디플로이먼트에 사용할 이미지 레퍼런스(예: your/repo:jovies)"
    echo "      --build       배포 전에 Dockerfile로 로컬 이미지를 빌드 (기본)"
    echo "      --no-build    빌드 생략"
    echo "      --tag         --build 시 사용할 이미지 태그 (기본: jovies-app:local-<timestamp>)"
    echo "      --dry-run     실제 적용 대신 미리보기 수행"
    echo "  -y, --yes         확인 프롬프트 건너뛰기"
    echo ""
}

# 기본값
K8S_NAMESPACE="jovies"
KUBE_CONTEXT=""
DRY_RUN="false"
APP_IMAGE=""
DO_BUILD="true"
IMAGE_TAG=""
SKIP_CONFIRM="false"

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            K8S_NAMESPACE="$2"; shift; shift ;;
        -c|--context)
            KUBE_CONTEXT="$2"; shift; shift ;;
        --dry-run)
            DRY_RUN="true"; shift ;;
        --app-image)
            APP_IMAGE="$2"; shift; shift ;;
        --build)
            DO_BUILD="true"; shift ;;
        --no-build)
            DO_BUILD="false"; shift ;;
        --tag)
            IMAGE_TAG="$2"; shift; shift ;;
        -y|--yes)
            SKIP_CONFIRM="true"; shift ;;
        -h|--help)
            print_usage; exit 0 ;;
        *)
            log_warn "알 수 없는 인자: $1"; print_usage; exit 1 ;;
    esac
done

# 사전 점검
check_required_dirs "deploy/k8s"

if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl 이 설치되어 있지 않습니다. 설치 후 다시 시도하세요."
    exit 1
fi

if ! command -v kompose >/dev/null 2>&1; then
    log_warn "kompose 가 설치되어 있지 않습니다. 기존 생성된 매니페스트만 적용합니다."
fi

# K8S 디렉토리 설정 (prod 설정만 사용)
K8S_DIR="deploy/k8s"

# 컨텍스트 설정
if [[ -n "$KUBE_CONTEXT" ]]; then
    log_info "kubectl 컨텍스트 설정: $KUBE_CONTEXT"
    kubectl config use-context "$KUBE_CONTEXT"
else
    CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -n "$CURRENT_CTX" ]]; then
        log_info "현재 kubectl 컨텍스트: $CURRENT_CTX"
    else
        log_warn "kubectl 컨텍스트가 설정되어 있지 않습니다. kubeconfig 를 확인하세요."
    fi
fi

# 네임스페이스 보장
if [[ "$K8S_NAMESPACE" != "default" ]]; then
    if ! kubectl get namespace "$K8S_NAMESPACE" >/dev/null 2>&1; then
        log_info "네임스페이스 생성: $K8S_NAMESPACE"
        kubectl create namespace "$K8S_NAMESPACE"
    fi
fi

# 빌드가 필요한 경우 로컬 이미지 빌드
if [[ "$DO_BUILD" == "true" && "$DRY_RUN" != "true" ]]; then
    BUILD_CONTEXT="."
    DOCKERFILE_PATH="deploy/docker/Dockerfile.prod"
    if [[ -z "$IMAGE_TAG" ]]; then
        IMAGE_TAG="jovies-app:local-$(date +%Y%m%d%H%M%S)"
    fi
    log_info "🔨 Docker 이미지 빌드: $IMAGE_TAG"
    docker build -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT"
    # 빌드 결과를 배포 이미지로 기본 설정 (명시적으로 --app-image 주면 그 값이 우선)
    if [[ -z "$APP_IMAGE" ]]; then
        APP_IMAGE="$IMAGE_TAG"
    fi
fi

echo ""
log_info "📦 적용 대상 디렉토리: $K8S_DIR"
log_info "🧭 네임스페이스: $K8S_NAMESPACE"
if [[ -n "$APP_IMAGE" ]]; then
    log_info "🖼️ 적용할 앱 이미지: $APP_IMAGE"
fi

# Dry-run 플래그 구성
APPLY_FLAGS=(apply -f "$K8S_DIR" -n "$K8S_NAMESPACE")
if [[ "$DRY_RUN" == "true" ]]; then
    APPLY_FLAGS+=(--dry-run=client)
fi

# 적용 전 요약 및 사전 검증
log_info "📝 적용 요약:"
echo "  - 디렉토리: $K8S_DIR"
echo "  - 네임스페이스: $K8S_NAMESPACE"
if [[ -n "$KUBE_CONTEXT" ]]; then echo "  - 컨텍스트: $KUBE_CONTEXT"; fi
if [[ "$DRY_RUN" == "true" ]]; then echo "  - 모드: Dry Run"; fi
if grep -qE "^\s*image:\s*app(\s|$)" "$K8S_DIR/app-deployment.yaml" 2>/dev/null; then
    if [[ -z "$APP_IMAGE" ]]; then
        log_warn "app-deployment.yaml 에 image: app 이 설정되어 있습니다. 실제 레지스트리 이미지를 --app-image 로 지정하는 것을 권장합니다."
    fi
fi

# 확인 후 진행
if [[ "$SKIP_CONFIRM" != "true" ]]; then
    if ! confirm_action "계속 진행하시겠습니까?" "Y"; then
        log_warn "사용자에 의해 취소되었습니다."
        exit 0
    fi
fi

echo ""
log_info "🚀 Kubernetes 리소스 적용 중..."
kubectl "${APPLY_FLAGS[@]}"

# 필요 시 이미지 오버라이드
if [[ -n "$APP_IMAGE" ]]; then
    log_info "🔄 앱 디플로이먼트 이미지 업데이트: $APP_IMAGE"
    kubectl -n "$K8S_NAMESPACE" set image deployment/jovies-app jovies-app="$APP_IMAGE"
    # latest 태그나 기본 정책으로 인한 강제 Pull 방지
    log_info "🛠️ 이미지 Pull 정책 패치: IfNotPresent"
    kubectl -n "$K8S_NAMESPACE" patch deployment jovies-app \
      --type='json' \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]' || true
fi

echo ""
log_info "📊 리소스 상태:" 
kubectl get all -n "$K8S_NAMESPACE"

echo ""
log_info "📄 유용한 명령어:"
echo "  - 삭제: kubectl delete -f $K8S_DIR -n $K8S_NAMESPACE"
echo "  - 로그: kubectl logs deploy/jovies-app -n $K8S_NAMESPACE -f"
echo "  - 상세: kubectl describe deploy/jovies-app -n $K8S_NAMESPACE"
echo "  - 포트 포워드: kubectl port-forward -n $K8S_NAMESPACE deploy/jovies-app 3002:3000"

log_info "✅ Kubernetes 배포 작업 완료"
