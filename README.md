# infra-bootstrap

Terraform da camada **persistente** da infraestrutura GCP do FIAP X ([`fiap-x-vcosta`](https://github.com/fiap-x-vcosta)). São os recursos gratuitos (ou de centavos) que os outros stacks consomem e que **não** entram no ciclo de subir/derrubar a demo.

Canon de produto: [`docs`](https://github.com/fiap-x-vcosta/docs).

## Escopo

- Habilitação das APIs usadas pelos stacks (`disable_on_destroy = false`), incluindo `redis.googleapis.com`
- Bucket GCS do backend de state (`fiap-x-vcosta-tfstate`)
- Workload Identity Federation: pool/provider `github` + service account `github-actions` e roles
- VPC `fiap-x-vpc`, subnet regional com ranges secundários do cluster e range/peering do Private Service Access
- Artifact Registry Docker `fiap-x` (cleanup: DELETE versões com mais de 1 dia + KEEP as 2 mais recentes por pacote)
- Service accounts de runtime (account id = nome do repositório): `autenticacao-service`, `upload-service`, `processamento-service`, `consultas-service`, `notificacao-service`. `roles/cloudsql.client` onde há PostgreSQL
- Cloud DNS managed zone pública `fiap-x` para `vcosta-fiap.online` (records da demo ficam no `infra-k8s`)
- Outputs: `network_id`, `subnet_id`, `pods_range_name`, `services_range_name`, `runtime_service_account_emails`, `dns_managed_zone_name`, `dns_name`, `dns_name_servers`
- Região `us-central1`, projeto `fiap-x-vcosta`

Root module: [`terraform/`](terraform/). Pin Terraform: **1.16.1** (alinhado a [`actions`](https://github.com/fiap-x-vcosta/actions)).

## Fora deste repo

- Cloud SQL, GKE, manifests, records DNS da janela
- Buckets de mídia (TF de `upload` / `processamento`)
- **Memorystore Redis** — API habilitada aqui; o recurso sobe no Terraform de `consultas-service` (`bff`) com a demo ([ADR 002](https://github.com/fiap-x-vcosta/docs/blob/main/adrs/002-progresso-cache-bff.md) no `docs`)
- Firestore (não usado neste produto)

## Plano de endereçamento

| Range | CIDR | Uso |
|-------|------|-----|
| Primário da subnet | `10.10.0.0/24` | Nós do cluster |
| Secundário `pods` | `10.60.0.0/16` | Pods do cluster |
| Secundário `services` | `10.61.0.0/20` | Services do cluster |
| Private Service Access | `10.100.0.0/16` | IP privado do Cloud SQL / Memorystore |

O range do PSA é **fixo** de propósito: com alocação automática a GCP escolhe um `/16` RFC1918 qualquer, que pode colidir com os ranges do cluster.

## State

| Item | Valor |
|------|--------|
| Bucket | `fiap-x-vcosta-tfstate` |
| Prefix deste repo | `infra-bootstrap` |
| Outros prefixes | `infra-k8s`, `infra-events`, prefixo de cada serviço |

O bucket é gerenciado por este stack e guarda o próprio state. Como este stack **não** tem rotina de destroy, não há risco de ele apagar o state embaixo de si.

### Primeiro apply (bucket ainda não existe)

O backend GCS exige o bucket já criado. Na **primeira** vez:

```bash
gcloud auth application-default login
cd terraform
terraform init -backend=false
terraform plan -out=tfplan
terraform apply tfplan
terraform init -migrate-state
```

Nas vezes seguintes: `terraform init` (com backend) → `plan` → `apply`.

## Apply é local, nunca por CI

Este stack concede IAM. Se a service account de CI o aplicasse, ela precisaria de IAM admin sobre si mesma e poderia se auto-promover. Por isso:

- **CI:** só `fmt` + `validate` via [`actions`](https://github.com/fiap-x-vcosta/actions) `ci-terraform` (`run_plan: false`) — não fala com a GCP
- **Apply/destroy:** local, com ADC de um humano com owner
- **Sem** workflows `tf-apply` / `tf-destroy` neste repositório

```bash
gcloud auth application-default login
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Todo `plan` deste stack merece leitura linha a linha: os recursos aqui sustentam o OIDC do CI e o acesso ao state.

## Quem pode assumir a service account de CI

O binding de `roles/iam.workloadIdentityUser` é **por repositório** (`attribute.repository`), não por org. Repos habilitados em `ci_repositories`:

`autenticacao-service`, `consultas-service`, `e2e`, `infra-events`, `infra-k8s`, `notificacao-service`, `processamento-service`, `upload-service`, `web`.

Este repositório **não** entra na lista. Também ficam de fora: `actions`, `building-blocks`, `docs`.

## Roles da service account de CI

Least-privilege, sem `roles/editor`:

- `roles/viewer`
- `roles/cloudsql.admin`
- `roles/compute.networkAdmin`
- `roles/container.admin`
- `roles/artifactregistry.writer`
- `roles/secretmanager.admin`
- `roles/redis.admin` — Memorystore no TF do `bff`
- `roles/apigateway.admin` / `roles/servicemanagement.admin` — API Gateway no `infra-k8s`
- `roles/dns.admin` — records DNS da demo no `infra-k8s`
- `roles/storage.objectAdmin` no bucket de state
- `roles/iam.serviceAccountUser` na service account padrão de compute
- Role customizada `serviceAccountIamPolicyWriter` em cada SA de runtime (Workload Identity no `infra-k8s`)
- Role customizada `gatewayEntryLb` (NEG serverless + `sslCertificates`)
- Role customizada `ciPubSubAdmin` (tópicos/subscriptions + IAM; sem `publish`/`consume`)

## Contrato com outros repos

| Valor | Consumido por |
|-------|---------------|
| Outputs de rede | Serviços (Cloud SQL privado) e `infra-k8s` (cluster), via `terraform_remote_state` |
| `runtime_service_account_emails` | `infra-k8s` (Workload Identity KSA→GSA). Chave = account id (= nome do repo) |
| Outputs DNS | `infra-k8s` (records); nameservers vão uma vez no registrador |
| `us-central1-docker.pkg.dev/fiap-x-vcosta/fiap-x` | workflows `build-push` / `deploy` (org var `GCP_AR_REPOSITORY` = `fiap-x`) |

## Domínio e nameservers

A zona Cloud DNS é **persistente** (~US$ 0,20/mês), com **DNSSEC** (`state = on`). Depois do `apply` local:

```bash
cd terraform
terraform output -json dns_name_servers
```

No registrador:

1. Troque os nameservers de `vcosta-fiap.online` pelos NS Google dessa saída.
2. Publique o registro **DS** (Digest) da KSK — no Console GCP: Cloud DNS → zona `fiap-x` → DNSSEC → copiar DS → colar no registrador.

Sem o DS no registrador, a zona assina mas a cadeia de confiança não fecha para resolvedores validadores. Records da janela (`api`, apex, front) **não** moram aqui.

## Workload Identity de runtime mora no `infra-k8s`

O pool `svc.id.goog` só existe com cluster vivo. Este stack só cria as SAs de runtime e `roles/cloudsql.client` onde há PostgreSQL. O binding KSA → GSA é criado pelo `infra-k8s` e morre com o cluster. Publisher/subscriber Pub/Sub e IAM de Storage não são concedidos aqui.

## Agentes

Ver [AGENTS.md](AGENTS.md).
