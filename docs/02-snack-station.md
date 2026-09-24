# Deploy do Snack Station

Fase 2. Depende de Traefik e Portainer no ar ([`01-primeira-instalacao.md`](01-primeira-instalacao.md)).

O Snack Station usa Supabase. Não há Postgres, Redis, Chatwoot nem Evolution API nesta VPS.

A divisão é:

```text
repo snack-station   código, Dockerfile, workflow que publica a imagem
repo iac-snack       bootstrap e o stack.yml de tudo que roda na VPS
Portainer            valores das variáveis de todas as stacks
```

O código fica em `github.com/sergiojunior1980/snack-station`.

## 1. Deploy automático

O Swarm não faz build. A imagem precisa existir num registry antes do deploy. O repo do Snack Station traz `Dockerfile`, `.dockerignore` e o workflow `.github/workflows/cd-app.yml`.

Merge na `master` dispara tudo, sem passo manual:

```text
merge na master do snack-station
      ↓
quality: typecheck + lint
      ↓
image: build e push
      ghcr.io/sergiojunior1980/snack-station:sha-abc1234
      ↓
deploy: reescreve a linha `image` em stacks/snack-station/stack.yml
      e commita neste repositório
      ↓
POST no webhook de GitOps do Portainer
      ↓
Portainer sincroniza o git, vê a tag nova e recria o serviço
      ↓
Swarm espera ficar healthy; se não ficar, volta a versão anterior sozinho
```

Cada deploy grava no `stack.yml` a tag do commit. O Docker baixa a imagem porque a referência mudou. O `[skip ci]` na mensagem evita que esse commit dispare o CI daqui à toa.

A imagem roda o servidor Node do Next em modo `standalone`. Quem termina TLS é o Traefik, que fala HTTP direto na porta 3000.

### Segredos do CD

No repositório `snack-station`, em Settings → Secrets and variables → Actions:

| Aba | Nome | Para quê |
|---|---|---|
| Variables | `NEXT_PUBLIC_SUPABASE_URL` | congelada no bundle |
| Variables | `IAC_REPOSITORY` | `sergiojunior1980/iac-snack` |
| Secrets | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | congelada no bundle |
| Secrets | `IAC_REPO_TOKEN` | PAT com permissão de escrita neste repositório |
| Secrets | `PORTAINER_WEBHOOK_URL` | webhook de GitOps da stack |

O `IAC_REPO_TOKEN` é necessário porque o `GITHUB_TOKEN` padrão só alcança o próprio repositório. Use um fine-grained PAT restrito a este repositório, com `Contents: read and write`.

A URL do webhook é credencial de deploy: quem a tiver redeploya a stack. Pegue em Portainer → a stack → **GitOps updates** → Mechanism **Webhook**.

Não marque "Re-pull image" nem "Force redeployment".

### Variáveis de build vs. variáveis de runtime

| Quando | Quais | Onde ficam |
|---|---|---|
| Build | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Variables/Secrets do repositório no GitHub |
| Runtime | `APP_HOST` e limites da stack | Variáveis da stack no Portainer |

As `NEXT_PUBLIC_*` são congeladas dentro do bundle JavaScript do cliente durante o `next build`. Cadastrá-las no Portainer não tem efeito. Para trocá-las, é preciso refazer o build e gerar uma tag nova.

O workflow falha de propósito se `NEXT_PUBLIC_SUPABASE_URL` ou `NEXT_PUBLIC_SUPABASE_ANON_KEY` estiverem vazias.

## 2. O stack.yml

Fica em [`stacks/snack-station/`](../stacks/snack-station/) deste repositório. As variáveis a cadastrar estão em [`env.example`](../stacks/snack-station/env.example).

O healthcheck vem da imagem (`HEALTHCHECK` no Dockerfile, batendo em `/api/health`) e é o que o Swarm usa para liberar a versão nova no `start-first`.

## 3. Banco de dados

O Snack Station usa o Supabase do próprio projeto: Auth e dados. Não crie banco nesta VPS.

## 4. DNS

| Tipo | Nome | Conteúdo |
|---|---|---|
| CNAME | `snack` | `manager.seudominio.com` |

Em **DNS only** (nuvem cinza), como os demais. O valor de `APP_HOST` na stack é o hostname completo, por exemplo `snack.seudominio.com`.

## 5. Credencial do registry no Portainer

Se o pacote no GHCR for privado, o Portainer precisa autenticar antes de puxar a imagem.

Em **Registries → Add registry → Custom registry**:

| Campo | Valor |
|---|---|
| URL | `ghcr.io` |
| Username | seu usuário do GitHub |
| Password | Personal Access Token com escopo `read:packages` |

## 6. Criar a stack

Em **Stacks → Add stack → Repository**, apontando para este repositório e para o caminho `stacks/snack-station/stack.yml`.

Cadastre as variáveis de [`stacks/snack-station/env.example`](../stacks/snack-station/env.example), com `NETWORK_PUBLIC=network_public`.

O `stack.yml` versionado começa em `sha-0000000`, que não existe. Rode o CD do `snack-station` **antes** de criar a stack — ele publica a primeira imagem e já commita a tag real aqui.

## 7. Atualizar uma versão

Automático: merge na `master`. O fluxo completo está na seção 1.

`update_config: start-first` mantém a versão antiga no ar até a nova responder, e `failure_action: rollback` volta sozinho se o container novo não subir.

### Rollback

```bash
cd iac-snack
git log --oneline stacks/snack-station/stack.yml
git revert <commit-do-deploy-ruim>
git push
```

O Portainer sincroniza e volta à imagem anterior.

### Alterar o próprio stack.yml

Mudanças no `stack.yml` (limites de memória, labels do Traefik, variáveis novas) são feitas neste repositório. Habilite **GitOps updates** na stack para o Portainer acompanhar este git.
