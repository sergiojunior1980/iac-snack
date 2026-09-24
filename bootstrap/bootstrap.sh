#!/usr/bin/env bash
set -Eeuo pipefail

ADMIN_USER="${ADMIN_USER:-admin}"
HOSTNAME_VALUE="${HOSTNAME_VALUE:-manager1}"
# Informe quando a VPS tiver mais de um IP (rede privada do provedor, por
# exemplo). Sem isso o `docker swarm init` aborta sem saber qual anunciar.
SWARM_ADVERTISE_ADDR="${SWARM_ADVERTISE_ADDR:-}"
NETWORK_PUBLIC="${NETWORK_PUBLIC:-network_public}"
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:v3.7}"
PORTAINER_IMAGE="${PORTAINER_IMAGE:-portainer/portainer-ce:lts}"
PORTAINER_AGENT_IMAGE="${PORTAINER_AGENT_IMAGE:-portainer/agent:lts}"

required=(SSH_PUBLIC_KEY ACME_EMAIL PORTAINER_HOST)
for variable in "${required[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Erro: defina ${variable} antes de executar." >&2
    exit 1
  fi
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erro: execute com sudo ou como root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  echo "Erro: este bootstrap suporta Ubuntu; detectado: ${ID}." >&2
  exit 1
fi

# NEEDRESTART_MODE=a: sem ele o Ubuntu 22.04+ abre a tela "Which services should
# be restarted?" no meio do apt e o script trava esperando input.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt-get update
apt-get install -y ca-certificates curl fail2ban sudo ufw unattended-upgrades

hostnamectl set-hostname "${HOSTNAME_VALUE}"

if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
  # Alguns provedores (Contabo, por exemplo) ja entregam a imagem com um grupo
  # chamado `admin`. Sem --gid, o useradd tentaria criar o grupo homonimo,
  # esbarraria no existente e abortaria.
  if getent group "${ADMIN_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --gid "${ADMIN_USER}" "${ADMIN_USER}"
  else
    useradd --create-home --shell /bin/bash "${ADMIN_USER}"
  fi
fi
usermod -aG sudo "${ADMIN_USER}"

install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
AUTHORIZED_KEYS="/home/${ADMIN_USER}/.ssh/authorized_keys"
touch "${AUTHORIZED_KEYS}"
# SSH_PUBLIC_KEY aceita varias chaves, uma por linha: uma por dispositivo, para
# que perder um notebook nao obrigue a revogar o acesso dos outros.
while IFS= read -r ssh_key; do
  if [[ -z "${ssh_key//[[:space:]]/}" ]]; then
    continue
  fi
  if ! grep -Fqx -- "${ssh_key}" "${AUTHORIZED_KEYS}"; then
    printf '%s\n' "${ssh_key}" >> "${AUTHORIZED_KEYS}"
  fi
done <<< "${SSH_PUBLIC_KEY}"
chown "${ADMIN_USER}:${ADMIN_USER}" "${AUTHORIZED_KEYS}"
chmod 0600 "${AUTHORIZED_KEYS}"
ssh-keygen -l -f "${AUTHORIZED_KEYS}" >/dev/null

printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "${ADMIN_USER}" > "/etc/sudoers.d/90-${ADMIN_USER}"
chmod 0440 "/etc/sudoers.d/90-${ADMIN_USER}"
visudo -cf "/etc/sudoers.d/90-${ADMIN_USER}"

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-vps-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sshd -t
systemctl reload ssh || systemctl reload sshd

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

systemctl enable --now fail2ban

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "${ADMIN_USER}"

if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]]; then
  if [[ -n "${SWARM_ADVERTISE_ADDR}" ]]; then
    docker swarm init --advertise-addr "${SWARM_ADVERTISE_ADDR}"
  else
    docker swarm init
  fi
fi

if ! docker network inspect "${NETWORK_PUBLIC}" >/dev/null 2>&1; then
  docker network create --driver overlay --attachable "${NETWORK_PUBLIC}"
fi

docker volume inspect volume_swarm_certificates >/dev/null 2>&1 || docker volume create volume_swarm_certificates
docker volume inspect portainer_data >/dev/null 2>&1 || docker volume create portainer_data

export NETWORK_PUBLIC TRAEFIK_IMAGE PORTAINER_IMAGE PORTAINER_AGENT_IMAGE ACME_EMAIL PORTAINER_HOST
docker stack deploy --prune --resolve-image always -c "${REPO_DIR}/stacks/traefik/stack.yml" traefik
docker stack deploy --prune --resolve-image always -c "${REPO_DIR}/stacks/portainer/stack.yml" portainer

echo
echo "Bootstrap concluído."
echo "Teste agora: ssh ${ADMIN_USER}@IP_DA_VPS"
echo "Portainer: https://${PORTAINER_HOST}"
echo "Não encerre esta sessão antes de validar o novo acesso SSH."
