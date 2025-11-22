#!/bin/bash

# Jovies Kubernetes 정리 스크립트
# 공통 유틸리티 함수 로드
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 스크립트 설정
setup_script

print_usage() {
    echo ""
    echo "사용법: $(basename "$0") [-n NAMESPACE] [--context CONTEXT] [--delete-namespace] [--delete-images] [--force]"
    echo "  -n, --namespace        정리할 네임스페이스 (기본: jovies)"
    echo "      --context          kubectl 컨텍스트 지정"
    echo "      --delete-namespace 네임스페이스 자체를 삭제 (주의)"
    echo "      --delete-images    로컬 Docker의 jovies 관련 이미지 삭제"
    echo "      --force            확인 프롬프트 없이 진행"
    echo ""
}

# 기본값
K8S_NAMESPACE="jovies"
KUBE_CONTEXT=""
DELETE_NAMESPACE="true"
DELETE_IMAGES="true"
FORCE="false"

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            K8S_NAMESPACE="$2"; shift; shift ;;
        --context)
            KUBE_CONTEXT="$2"; shift; shift ;;
        --delete-namespace)
            DELETE_NAMESPACE="true"; shift ;;
        --delete-images)
            DELETE_IMAGES="true"; shift ;;
        --force)
            FORCE="true"; shift ;;
        -h|--help)
            print_usage; exit 0 ;;
        *)
            log_warn "알 수 없는 인자: $1"; print_usage; exit 1 ;;
    esac
done

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

# 네임스페이스 존재 확인
if ! kubectl get namespace "$K8S_NAMESPACE" >/dev/null 2>&1; then
    log_warn "네임스페이스가 존재하지 않습니다: $K8S_NAMESPACE"
    if [[ "$DELETE_IMAGES" == "false" ]]; then
        exit 0
    fi
fi

echo ""
log_info "🧹 정리 대상 요약:"
echo "  - 네임스페이스: $K8S_NAMESPACE"
if [[ "$DELETE_NAMESPACE" == "true" ]]; then echo "  - 동작: 네임스페이스 삭제"; else echo "  - 동작: 네임스페이스 내부 리소스 삭제"; fi
if [[ "$DELETE_IMAGES" == "true" ]]; then echo "  - 로컬 이미지 삭제: 활성화"; fi

# 확인 프롬프트
if [[ "$FORCE" != "true" ]]; then
    if ! confirm_action "정리를 진행하시겠습니까?" "N"; then
        log_warn "사용자에 의해 취소되었습니다."
        exit 0
    fi
fi

# 리소스 삭제
if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    log_info "🔻 네임스페이스 삭제: $K8S_NAMESPACE"
    kubectl delete namespace "$K8S_NAMESPACE" --wait=false || true
else
    log_info "🗑️ 네임스페이스 내부 리소스 삭제: $K8S_NAMESPACE"
    # 기본 리소스 (배포/서비스/ConfigMap/Secret/Job/CronJob 등) 일괄 삭제
    kubectl -n "$K8S_NAMESPACE" delete all --all || true
    # PVC 및 PV 삭제 (주의: 데이터 손실)
    kubectl -n "$K8S_NAMESPACE" delete pvc --all || true
    # 바운드 PV 중 네임스페이스 연관 PVC가 삭제된 경우 고아 PV 제거 시도
    for pv in $(kubectl get pv -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        claim_ns=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.namespace}' 2>/dev/null || echo "")
        if [[ "$claim_ns" == "$K8S_NAMESPACE" ]]; then
            log_info "📦 PV 삭제: $pv"
            kubectl delete pv "$pv" || true
        fi
    done
    # 남아있는 네임스페이스 스코프 리소스 정리
    kubectl -n "$K8S_NAMESPACE" delete configmap --all || true
    kubectl -n "$K8S_NAMESPACE" delete secret --all || true
fi

# 로컬 Docker 이미지 삭제
if [[ "$DELETE_IMAGES" == "true" ]]; then
    log_info "🧽 로컬 Docker 이미지 정리: jovies-app 관련 태그"
    docker rmi -f $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^jovies-app:local|^jovies-app:' || true) 2>/dev/null || true
fi

log_info "✅ 정리 작업 완료"
