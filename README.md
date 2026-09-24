# Infraestrutura da VPS do Snack Station

Fonte da verdade para o bootstrap da VPS e para as stacks Docker Swarm do Snack Station.

Uma VPS hospeda o Traefik, o Portainer e o Snack Station. O banco fica no Supabase. Esta VPS não roda Postgres, Redis, Chatwoot nem Evolution API.

## Modelo operacional

- GitHub guarda os YAMLs, scripts e histórico.
- Portainer guarda os valores das variáveis de cada stack.
- Traefik e Portainer são instalados pelo bootstrap inicial.
- O Snack Station tem repositório próprio (`sergiojunior1980/snack-station`) e vira a stack `stacks/snack-station/`.
- Não editar o YAML de produção diretamente no editor do Portainer.

## Estrutura

```text
bootstrap/                 preparação inicial da VPS
stacks/traefik/            proxy reverso
stacks/portainer/          painel operacional
stacks/snack-station/      aplicação (imagem vem do repo snack-station)
templates/app-swarm/       base se entrar outra aplicação nesta VPS
docs/                      roteiros de instalação
```

## Rede

| Rede | Função |
|---|---|
| `network_public` | Tráfego HTTP entre Traefik e os serviços expostos |

O bootstrap cria essa rede. O Snack Station fala com o Supabase pela internet e participa só dela.

## Roteiros

| Fase | Documento | Cobre |
|---|---|---|
| 1 | [`docs/01-primeira-instalacao.md`](docs/01-primeira-instalacao.md) | VPS nova até Traefik e Portainer no ar |
| 2 | [`docs/02-snack-station.md`](docs/02-snack-station.md) | Deploy do Snack Station |

## Primeiro acesso à VPS

Pré-requisitos:

- Ubuntu 22.04, 24.04 ou 26.04;
- acesso inicial como `root`;
- chave SSH pública local;
- registro A `manager.seudominio.com` apontando para a VPS;
- CNAME `portainer.seudominio.com` apontando para `manager.seudominio.com`;
- portas 22, 80 e 443 liberadas no firewall do provedor.

Leve este repositório para a VPS, por `git clone` ou `scp`:

```bash
ssh root@IP_DA_VPS
git clone https://github.com/sergiojunior1980/iac-snack /opt/iac-snack
cd /opt/iac-snack
```

Execute informando suas chaves públicas (uma por linha), e-mail do Let's Encrypt e hostname do Portainer:

```bash
sudo ADMIN_USER=admin \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAA...' \
  ACME_EMAIL='SEU_EMAIL' \
  PORTAINER_HOST='portainer.seudominio.com' \
  bash bootstrap/bootstrap.sh
```

Numa VPS com mais de um IP, acrescente `SWARM_ADVERTISE_ADDR='IP_PUBLICO'`.

O script é idempotente e pode ser executado novamente. Não feche a sessão root até confirmar, em outro terminal:

```bash
ssh admin@IP_DA_VPS
```

O usuário recebe `sudo` sem senha e acesso ao grupo `docker`; portanto, deve ser tratado como administrador total da VPS. O acesso é protegido pelas chaves SSH informadas.

Depois acesse `https://portainer.seudominio.com` e crie o administrador imediatamente — a tela inicial é primeiro-que-chegar.

O roteiro completo está em [`docs/01-primeira-instalacao.md`](docs/01-primeira-instalacao.md). O deploy da aplicação está em [`docs/02-snack-station.md`](docs/02-snack-station.md).

## O que permanece manual

- contratação da VPS e configuração do firewall do provedor;
- primeiro acesso SSH;
- apontamento inicial do DNS;
- criação do administrador do Portainer;
- cadastro dos valores nas variáveis de cada stack;
- configuração das credenciais do Git/registry no Portainer;
- variáveis `NEXT_PUBLIC_*` no GitHub Actions do repositório `snack-station`.

## Verificação

Na VPS:

```bash
docker node ls
docker network inspect network_public
docker stack ls
docker service ls
```
