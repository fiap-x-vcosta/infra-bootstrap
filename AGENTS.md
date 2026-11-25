# Guia para agentes — `infra-bootstrap` (FIAP X)

Terraform da camada **persistente** do projeto na GCP: APIs, bucket de state, Workload Identity Federation, service accounts, VPC/subnet/PSA, Artifact Registry e Cloud DNS (zona de `vcosta-fiap.online`). Org [`fiap-x-vcosta`](https://github.com/fiap-x-vcosta).

Cloud SQL fica no Terraform de cada serviço; cluster, Gateway e records DNS da janela em `infra-k8s`; Memorystore do `bff` no Terraform de `consultas-service`; buckets de mídia no TF de `upload` / `processamento` ([ADR 001](https://github.com/fiap-x-vcosta/docs/blob/main/adrs/001-storage-multi-tier.md) no `docs`).

## Antes de mudar código

1. Ler o [README](README.md) e as decisões de custo/demo já tomadas
2. Espelhar o layout flat em `terraform/` (`apis.tf`, `network.tf`, …); não inventar layout paralelo
3. Não rodar `apply`/`destroy` sem confirmação explícita do usuário
4. **Git:** nunca commit/push direto em `main` — branch → PR → merge humano (ver [`.cursor/rules/git-workflow.mdc`](.cursor/rules/git-workflow.mdc))
5. Naming: proibida a string que combina o produto com “videos” em camel/kebab/snake

## Responsabilidade

| Peça | Papel |
|------|--------|
| Terraform | APIs (incl. Redis API), state, WIF, SAs e roles, VPC/subnet/PSA, Artifact Registry, zona DNS |
| Apply | **Local, por humano com owner** — nunca por CI |
| Ciclo de vida | Recursos ~zero idle; **não** entram no `tf-destroy` da demo |
| Fora de escopo | Cloud SQL, GKE, manifests, records DNS da janela, Memorystore, buckets de mídia, código dos serviços |

## Regras canônicas (resumo)

- Este stack concede IAM: se a CI o aplicasse, a SA de CI poderia se auto-promover
- Nada aqui morre no ciclo de demo; os outros stacks referenciam estes recursos
- Workload Identity do CI é por repositório (`ci_repositories`), não por org
- Binding KSA → SA de runtime não cabe aqui (pool `svc.id.goog` só com cluster vivo — mora no `infra-k8s`)
- CI só `fmt`/`validate` via `fiap-x-vcosta/actions`; sem workflow de apply nem de destroy
- Sem secrets no Git; README autocontido na org

## Comandos

```bash
cd terraform
terraform fmt -check
terraform init -backend=false
terraform validate
# init/plan/apply reais: só local, com ADC de owner e confirmação humana
```
