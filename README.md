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
- Região `us-central1`, projeto `fiap-x-vcosta`

Root module: [`terraform/`](terraform/) (a partir do PR de Terraform). Pin Terraform: **1.16.1** (alinhado a [`actions`](https://github.com/fiap-x-vcosta/actions)).

## Fora deste repo

- Cloud SQL, GKE, manifests, records DNS da janela
- Buckets de mídia (TF de `upload` / `processamento`)
- **Memorystore Redis** — API habilitada aqui; o recurso sobe no Terraform de `consultas-service` (`bff`) com a demo ([ADR 002](https://github.com/fiap-x-vcosta/docs/blob/main/adrs/002-progresso-cache-bff.md) no `docs`)
- Firestore (não usado neste produto)

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

## Domínio e nameservers

A zona Cloud DNS é **persistente** (~US$ 0,20/mês). Depois do `apply` local:

```bash
cd terraform
terraform output -json dns_name_servers
```

No registrador, troque os nameservers de `vcosta-fiap.online` pelos NS Google dessa saída. Records da janela (`api`, apex, front) **não** moram aqui.

## Contrato com outros repos

| Valor | Consumido por |
|-------|---------------|
| Outputs de rede | Serviços (Cloud SQL privado) e `infra-k8s` (cluster), via `terraform_remote_state` |
| `runtime_service_account_emails` | `infra-k8s` (Workload Identity KSA→GSA) |
| Outputs DNS | `infra-k8s` (records); nameservers vão uma vez no registrador |
| `us-central1-docker.pkg.dev/fiap-x-vcosta/fiap-x` | workflows `build-push` / `deploy` (org var `GCP_AR_REPOSITORY` = `fiap-x`) |

Este repositório **não** entra em `ci_repositories`. Também ficam de fora: `actions`, `building-blocks`, `docs`.

## Agentes

Ver [AGENTS.md](AGENTS.md).
