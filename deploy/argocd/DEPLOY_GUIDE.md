# Jovies ArgoCD 배포 가이드 (2GB RAM 환경)

## 전제조건

- ✅ ArgoCD 설치됨
- ✅ K3s 클러스터 실행 중
- ✅ GHCR에 이미지 푸시 권한

## 현재 리소스 설정 (2GB 최적화)

```yaml
Jovies Pod:
  replicas: 1
  resources:
    requests:
      memory: 100Mi
      cpu: 50m
    limits:
      memory: 200Mi
      cpu: 150m
```

### 예상 메모리 사용량

```
시스템:              ~300Mi
K3s:                 ~300Mi
ArgoCD:              ~800Mi
Traefik:             ~50Mi
Jovies:              ~100Mi (최대 200Mi)
────────────────────────────
총합:                ~1,550Mi
여유:                ~500Mi  ✅
```

## 배포 단계

### 1. ArgoCD에 Application 등록

```bash
cd /Users/minjo/home/mayne/projects/jovies

# Application 생성
kubectl apply -f deploy/argocd/application.yaml
```

### 2. 배포 상태 확인

```bash
# Application 상태 확인
kubectl get application jovies -n argocd

# 출력 예시:
# NAME     SYNC STATUS   HEALTH STATUS
# jovies   Synced        Healthy
```

### 3. Pod 상태 확인

```bash
# Jovies namespace의 Pod 확인
kubectl get pods -n jovies

# 상세 로그 확인
kubectl logs -n jovies -l app=jovies-app -f
```

### 4. Service 확인

```bash
# Service 정보 확인
kubectl get svc -n jovies

# 출력:
# NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
# jovies-service   ClusterIP   10.43.xxx.xxx   <none>        80/TCP
```

## ArgoCD UI 접근

### 포트포워딩으로 접근

```bash
# ArgoCD 서버 포트포워딩
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 브라우저에서 https://localhost:8080 접속
```

### 초기 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

- **Username**: `admin`
- **Password**: 위 명령어 출력값

## 배포 워크플로우

```
1. 개발자가 코드 변경 후 main 브랜치에 push
   ↓
2. GitHub Actions가 Docker 이미지 빌드 & GHCR에 푸시
   (태그: latest, main, main-{sha})
   ↓
3. ArgoCD가 매니페스트 변경 감지 (3분마다)
   ↓
4. 자동으로 Kubernetes에 배포 (selfHeal: true)
   ↓
5. Rolling Update로 무중단 배포
```

## 수동 동기화

필요 시 수동으로 동기화:

```bash
# kubectl 사용
kubectl patch app jovies -n argocd --type merge -p '{"operation":{"sync":{}}}'

# 또는 ArgoCD CLI 사용 (설치되어 있다면)
argocd app sync jovies
```

## 이미지 업데이트

### 방법 1: GitHub Actions (자동)

```yaml
# .github/workflows/build.yml이 자동으로:
# 1. 이미지 빌드
# 2. GHCR에 푸시 (latest 태그)
# 3. ArgoCD가 자동 감지하여 배포
```

### 방법 2: 수동 이미지 태그 변경

```bash
# kustomization.yaml 수정
cd deploy/k8s/overlays/prod
vi kustomization.yaml

# newTag를 원하는 버전으로 변경
images:
  - name: ghcr.io/mayne0213/jovies
    newTag: main-abc1234  # ← 변경

# Git에 커밋 & 푸시
git add .
git commit -m "Update jovies to main-abc1234"
git push

# ArgoCD가 자동으로 감지하여 배포
```

## 트러블슈팅

### Pod가 CrashLoopBackOff 상태

```bash
# Pod 로그 확인
kubectl logs -n jovies -l app=jovies-app --tail=100

# Pod 상세 정보
kubectl describe pod -n jovies -l app=jovies-app

# 일반적인 원인:
# 1. 이미지를 찾을 수 없음 → GHCR 권한 확인
# 2. 환경변수 누락 → ConfigMap/Secret 확인
# 3. Health check 실패 → 포트 3000 확인
```

### ArgoCD Sync 실패

```bash
# Application 상태 확인
kubectl get app jovies -n argocd -o yaml

# ArgoCD 로그 확인
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

### 메모리 부족 (OOMKilled)

```bash
# Pod 상태 확인
kubectl get pod -n jovies -l app=jovies-app

# 마지막 종료 이유 확인
kubectl describe pod -n jovies -l app=jovies-app | grep -A 5 "Last State"

# OOMKilled가 보이면 리소스 증가 필요:
# deploy/k8s/overlays/prod/deployment-patch.yaml 수정
resources:
  limits:
    memory: "300Mi"  # 200Mi → 300Mi로 증가
```

## 롤백

### ArgoCD UI에서 롤백

1. ArgoCD UI 접속
2. `jovies` 애플리케이션 클릭
3. `HISTORY` 탭
4. 이전 버전 선택 후 `ROLLBACK` 클릭

### CLI로 롤백

```bash
# 히스토리 확인
kubectl get app jovies -n argocd -o yaml | grep -A 10 "history:"

# 특정 리비전으로 롤백 (예: revision 3)
argocd app rollback jovies 3
```

## 모니터링

### 리소스 사용량 확인

```bash
# Pod 리소스 사용량
kubectl top pod -n jovies

# Node 전체 리소스 사용량
kubectl top node

# 출력 예시:
# NAME                CPU(cores)   MEMORY(bytes)
# jovies-app-xxx      10m          120Mi
```

### 메모리 압박 확인

```bash
# 전체 메모리 사용량 모니터링
watch -n 5 'kubectl top node && echo "---" && kubectl top pod -A | head -20'
```

### 로그 스트리밍

```bash
# 실시간 로그 확인
kubectl logs -n jovies -l app=jovies-app -f --tail=100

# 여러 Pod의 로그를 모두 보기
kubectl logs -n jovies -l app=jovies-app --all-containers=true -f
```

## 정리 (삭제)

```bash
# ArgoCD Application 삭제 (리소스도 함께 삭제됨)
kubectl delete -f deploy/argocd/application.yaml

# 또는 직접 삭제
kubectl delete app jovies -n argocd

# Namespace도 삭제하려면
kubectl delete namespace jovies
```

## 다음 단계

메모리가 충분해지면 (4GB+):

1. **Replica 증가**
   ```yaml
   spec:
     replicas: 2  # 고가용성
   ```

2. **리소스 증가**
   ```yaml
   resources:
     requests:
       memory: "256Mi"
     limits:
       memory: "512Mi"
   ```

3. **ArgoCD Image Updater 추가**
   - 자동으로 새 이미지 감지
   - Git 커밋 없이 배포 가능

4. **Monitoring Stack 추가**
   - Prometheus
   - Grafana
   - Alert Manager
