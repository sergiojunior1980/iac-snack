# Primeira instalação da VPS

Leva a VPS de recém-criada até Traefik e Portainer no ar, com SSH endurecido.

Roda **uma vez**, como `root`. É a única etapa manual do projeto — não dá para automatizar o primeiro acesso a uma máquina que ainda não te conhece. Quem quiser eliminar até isso pode colar o `bootstrap.sh` no *cloud-init* na criação da VPS.

O script é **idempotente**: se falhar no meio, corrija a causa e rode de novo. Nenhum passo quebra ao repetir.

## 1. O que ter em mãos

| Item | Observação |
|---|---|
| IP público da VPS | |
| Senha do `root` | Guarde no cofre: é a saída de emergência |
| Ubuntu 22.04, 24.04 ou 26.04 | O script recusa outras distros |
| 2 GB de RAM ou mais | Traefik, Portainer e o Snack Station |
| Portas 22, 80 e 443 abertas | No firewall **do provedor**, não no da VPS |
| Acesso ao painel DNS | o domínio do Snack Station |
| E-mail para o Let's Encrypt | Recebe avisos de expiração |

## 2. DNS

Três registros, todos apontando para a mesma VPS:

| Tipo | Nome | Conteúdo | Usado por |
|---|---|---|---|
| A | `manager` | `IP_DA_VPS` | base dos demais |
| CNAME | `portainer` | `manager.seudominio.com` | painel |
| CNAME | `snack` | `manager.seudominio.com` | Snack Station (fase 2) |

Na Cloudflare, os três em **DNS only** (nuvem cinza). Com o proxy ligado (nuvem laranja) o desafio HTTP do Let's Encrypt não fecha e o Traefik não emite certificado.

Confira antes de continuar:

```powershell
Resolve-DnsName manager.seudominio.com
Resolve-DnsName portainer.seudominio.com
```

Só siga quando ambos terminarem no IP da VPS. Propagação pode levar minutos.

## 3. Chaves SSH

Uma chave **por dispositivo**. Assim, perder o notebook não obriga a revogar o acesso do desktop.

Em cada máquina que vai acessar a VPS:

```powershell
ssh-keygen -t ed25519 -C "lucas-desktop"
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

Use uma senha na chave privada. Copie a linha pública inteira de cada máquina — todas entram no bootstrap de uma vez, no passo 5.

Nunca copie a chave **privada** entre computadores: aí você perde a capacidade de revogar um dispositivo sozinho.

Cadastre todas as máquinas agora, de uma vez. Depois do bootstrap, liberar um computador novo exige usar um que já tenha acesso — ver [seção 13](#13-liberar-um-computador-novo).

## 4. Levar o repositório para a VPS

O repositório é o `iac-snack`. Duas formas:

**Se o repo já está no GitHub** (recomendado — evita o problema de CRLF do Windows):

```bash
ssh root@IP_DA_VPS
apt-get update && apt-get install -y git
git clone https://github.com/sergiojunior1980/iac-snack /opt/iac-snack
cd /opt/iac-snack
```

Repositório privado pede usuário e um PAT com escopo `repo`.

**Ou copiando do computador local**, se o repo ainda não foi publicado:

```powershell
scp -r "/Users/sergioalves/Documents/iac-snack" root@IP_DA_VPS:/opt/iac-snack
```

```bash
ssh root@IP_DA_VPS
cd /opt/iac-snack
ls -la    # devem aparecer: bootstrap, stacks, templates, docs
```

> O `.gitattributes` do repositório força LF nos scripts. Se você copiar de um clone antigo, feito antes dele existir, o `bootstrap.sh` pode chegar com quebras de linha do Windows e falhar de um jeito confuso. Confira com `head -1 bootstrap/bootstrap.sh | od -c | tail -2`: se aparecer `\r \n`, rode `sed -i 's/\r$//' bootstrap/bootstrap.sh`.

## 5. Variáveis do bootstrap

**Obrigatórias** — o script aborta sem elas:

| Variável | Exemplo |
|---|---|
| `SSH_PUBLIC_KEY` | a linha `ssh-ed25519 AAAA...` do passo 3; aceita várias, uma por linha |
| `ACME_EMAIL` | `voce@dominio.com` |
| `PORTAINER_HOST` | `portainer.seudominio.com` |

**Opcionais** — só informe se quiser fugir do padrão:

| Variável | Padrão | Quando mexer |
|---|---|---|
| `ADMIN_USER` | `admin` | outro nome de usuário |
| `HOSTNAME_VALUE` | `manager1` | outro hostname |
| `SWARM_ADVERTISE_ADDR` | vazio | **VPS com mais de um IP** — ver passo 8 |
| `NETWORK_PUBLIC` | `network_public` | raramente |
| `TRAEFIK_IMAGE` | `traefik:v3.7` | fixar outra versão |
| `PORTAINER_IMAGE` | `portainer/portainer-ce:lts` | fixar outra versão |
| `PORTAINER_AGENT_IMAGE` | `portainer/agent:lts` | fixar outra versão |

## 6. Executar

Com uma chave só:

```bash
sudo ADMIN_USER='admin' \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAAC3Nz... lucas-desktop' \
  ACME_EMAIL='voce@dominio.com' \
  PORTAINER_HOST='portainer.seudominio.com' \
  bash bootstrap/bootstrap.sh
```

Com várias chaves, use aspas simples e uma quebra de linha real entre elas:

```bash
sudo ADMIN_USER='admin' \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAAC3Nz... lucas-desktop
ssh-ed25519 AAAAC3Nz... lucas-notebook' \
  ACME_EMAIL='voce@dominio.com' \
  PORTAINER_HOST='portainer.seudominio.com' \
  bash bootstrap/bootstrap.sh
```

A segunda chave começa na coluna 0 de propósito: qualquer indentação vira parte da chave.

O que ele faz, em ordem:

1. valida as variáveis, que você é root e que a distro é Ubuntu;
2. instala `ca-certificates curl fail2ban sudo ufw unattended-upgrades`;
3. define o hostname;
4. cria o usuário administrativo e o coloca no grupo `sudo`;
5. instala suas chaves públicas e **valida o arquivo** com `ssh-keygen -l`;
6. dá `sudo` sem senha ao usuário, validando com `visudo -cf`;
7. desliga login de `root` e autenticação por senha no SSH, validando com `sshd -t` antes de recarregar;
8. configura UFW (libera SSH, 80 e 443) e ativa o Fail2ban;
9. instala Docker pelo repositório oficial e põe o usuário no grupo `docker`;
10. inicializa o Swarm;
11. cria a rede `network_public` e os volumes iniciais;
12. sobe Traefik e Portainer.

A ordem não é acidental: a chave é validada **antes** do SSH endurecer, e o UFW libera a porta 22 **antes** de ser ativado. Não existe ponto de falha que te tranque fora — desde que a chave privada correspondente esteja com você.

O bootstrap para aqui de propósito. O Snack Station entra depois, pelo Portainer, a partir de `stacks/snack-station/stack.yml`.

## 7. Validar antes de fechar a sessão root

**Mantenha a sessão `root` aberta.** Em outro terminal:

```powershell
ssh admin@IP_DA_VPS
```

Já dentro:

```bash
sudo whoami      # root
docker node ls   # um nó, STATUS Ready, MANAGER STATUS Leader
docker stack ls  # traefik e portainer
docker service ls
```

Em `docker service ls`, ambos os serviços precisam mostrar `1/1` em REPLICAS. `0/1` significa que o container não subiu — veja `docker service logs traefik_traefik`.

Se o login como `admin` falhar, **não feche a sessão root**. Corrija a chave em `/home/admin/.ssh/authorized_keys` e teste de novo.

## 8. Quando dá errado

| Sintoma | Causa | Solução |
|---|---|---|
| `Erro: defina X antes de executar` | variável obrigatória faltando | passo 5 |
| `useradd: group admin exists` | imagem do provedor já traz o grupo (Contabo) | o script reaproveita o grupo; se aparecer, seu `bootstrap.sh` está desatualizado |
| `could not choose an IP address to advertise` | VPS com IP público e privado | rode de novo com `SWARM_ADVERTISE_ADDR='IP_PUBLICO'` |
| `bash\r: command not found` ou heredoc sem fim | arquivo com CRLF | fim do passo 4 |
| Tela roxa "Which services should be restarted?" | needrestart interativo | o script já define `NEEDRESTART_MODE=a`; se aparecer, é versão antiga do script |
| Travou no `apt-get` | rede do provedor | `Ctrl+C` e rode de novo |
| Portainer não abre em HTTPS | DNS ainda propagando, ou proxy da Cloudflare ligado | passo 2; veja `docker service logs traefik_traefik` |
| `docker node ls` diz "not a swarm manager" | swarm não inicializou | rode o bootstrap de novo |

Em qualquer caso: **corrija e rode o bootstrap de novo**. Ele é idempotente.

**Perdeu o acesso SSH?** O painel do provedor tem console web (VNC ou serial). O `sshd_config` só governa SSH — o login pelo console com a senha do `root` continua funcionando. É por isso que essa senha vai para o cofre.

## 9. Inicializar o Portainer

```text
https://portainer.seudominio.com
```

A tela pede usuário, senha (mínimo 12 caracteres) e um **setup token**. O token é gerado no boot e sai nos logs do serviço:

```bash
docker service logs portainer_portainer 2>&1 | grep -i token
```

Se não retornar nada, a janela de criação expirou. Reinicie para gerar outro:

```bash
docker service update --force portainer_portainer
sleep 15
docker service logs portainer_portainer 2>&1 | grep -i token
```

O token existe porque o painel nasce exposto e sem dono: sem ele, quem descobrisse a URL primeiro viraria administrador. Por isso o Portainer também fecha a janela sozinho após alguns minutos.

Senha longa e única, guardada no cofre.

Confirme que o ambiente Docker Swarm aparece e que `traefik` e `portainer` estão saudáveis.

## 10. Credenciais do Portainer

Ainda no Portainer, deixe prontas as credenciais que as próximas fases usam:

- **Registries → Add registry → Custom registry**: `ghcr.io`, seu usuário do GitHub, e um Personal Access Token **classic** com escopo `read:packages`. Necessário se o pacote do `snack-station` for privado.
- **Credencial de Git**: para stacks do tipo Repository, alcançando `sergiojunior1980/iac-snack`. É de lá que o Portainer lê todos os `stack.yml`.

## 11. Onde cada credencial fica

| Credencial | Local |
|---|---|
| Senha do root | Cofre; uso emergencial pelo console do provedor |
| Chave SSH privada | Cada computador, individualmente |
| Chave SSH pública | VPS (`authorized_keys`) |
| Senha do Portainer | Cofre |
| Token do GitHub | Portainer |
| Credencial do GHCR | Portainer (Registries) |
| `NEXT_PUBLIC_SUPABASE_*` | GitHub Actions do repositório `snack-station` |
| Nomes das variáveis | YAML no GitHub |

Valor nenhum de segredo entra no repositório.

## 12. Uso diário

Depois desta fase, você não mexe mais na VPS por SSH no dia a dia:

```text
alterar stack no GitHub
        ↓
revisar e fazer merge
        ↓
Portainer atualiza a stack
        ↓
Traefik publica o serviço
```

Não altere o YAML no editor web do Portainer. Mudança emergencial feita pela interface deve ser reproduzida no repositório em seguida, senão o próximo deploy a desfaz.

O clone em `/opt/iac-snack` serviu só para o bootstrap; daqui em diante o Portainer puxa as stacks direto do GitHub.

## 13. Liberar um computador novo

O servidor só confia em quem já está na lista. Um computador novo **não consegue se autorizar sozinho** — é justamente disso que vem a segurança do esquema. Quem libera é uma máquina que já entra.

```text
PC que já entra  ──cola a chave pública do novo──►  VPS
                                                     │
                                                     ▼
                                               PC novo passa a entrar
```

**No computador novo**, gere o par de chaves e copie a linha pública:

```powershell
ssh-keygen -t ed25519 -C "lucas-notebook"
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

É `ssh-keygen`, que já vem no Windows — não `openssl`, que é outra ferramenta. A chave **privada** nunca sai desse computador; só a linha `.pub` é copiada.

**De um computador que já entra**, cole essa linha:

```bash
ssh admin@IP_DA_VPS
sudo bash /opt/iac-snack/bootstrap/add-ssh-key.sh 'ssh-ed25519 AAAA... lucas-notebook'
```

O script valida a chave antes de gravar, não duplica se ela já existir, corrige as permissões e lista no fim todas as máquinas autorizadas. Aceita várias chaves de uma vez.

Teste o acesso do computador novo **sem fechar** a sessão atual.

Para revogar uma máquina, apague a linha dela de `/home/admin/.ssh/authorized_keys`. O comentário no fim de cada chave (`lucas-notebook`) existe para você saber qual é qual.

### Se você não tem acesso de nenhum computador

Use o **console web do provedor** (VNC ou serial). Ele não passa por SSH, então `PermitRootLogin no` e `PasswordAuthentication no` não valem lá: entra com `root` e a senha do cofre.

Digitar uma chave de 80 caracteres num console VNC é sofrido. O caminho mais fácil é reabrir a senha por alguns minutos:

```bash
# 1. no console do provedor
echo 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-temp.conf
passwd admin
systemctl reload ssh

# 2. agora entre por SSH de qualquer computador e cadastre a chave nova
#    ssh admin@IP  →  sudo bash /opt/iac-snack/bootstrap/add-ssh-key.sh '...'

# 3. feche de novo
rm /etc/ssh/sshd_config.d/99-temp.conf
systemctl reload ssh
```

O arquivo `99-temp` vem depois de `99-vps-hardening` na ordem de leitura, então prevalece enquanto existir. Apagá-lo devolve o estado endurecido sem editar nada do original.

Esse cenário é evitável: cadastre desktop e notebook já no passo 6 e ele nunca acontece.

## 14. Próximo passo

Com Traefik e Portainer no ar, o próximo passo é o Snack Station: [`02-snack-station.md`](02-snack-station.md).
