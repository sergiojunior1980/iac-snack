#!/usr/bin/env bash
set -Eeuo pipefail

# Libera um computador novo a acessar a VPS.
#
# Rode a partir de um computador que JA tem acesso — o servidor so confia em
# quem ja esta na lista, entao uma maquina nova nao consegue se autorizar.
#
#   ssh admin@IP_DA_VPS
#   sudo bash /opt/iac-snack/bootstrap/add-ssh-key.sh 'ssh-ed25519 AAAA... notebook'
#
# Aceita varias chaves de uma vez. Para gerar a chave no computador novo:
#
#   ssh-keygen -t ed25519 -C "apelido-da-maquina"
#   Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub    (PowerShell)
#   cat ~/.ssh/id_ed25519.pub                           (Linux/macOS)
#
# Cole aqui a linha PUBLICA (.pub). A chave privada nunca sai do computador.

ADMIN_USER="${ADMIN_USER:-admin}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erro: execute com sudo." >&2
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  echo "Uso: sudo bash $0 'ssh-ed25519 AAAA... apelido' ['outra chave' ...]" >&2
  exit 1
fi

if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
  echo "Erro: usuario ${ADMIN_USER} nao existe. Informe ADMIN_USER=<nome>." >&2
  exit 1
fi

# Valida TODAS as chaves antes de escrever qualquer uma: um erro de copiar e
# colar nao pode deixar o authorized_keys pela metade.
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

for key in "$@"; do
  printf '%s\n' "${key}" > "${scratch}/candidate"
  if ! ssh-keygen -l -f "${scratch}/candidate" >/dev/null 2>&1; then
    echo "Erro: isto nao e uma chave publica valida:" >&2
    echo "  ${key}" >&2
    echo "Confira se copiou a linha inteira do arquivo .pub." >&2
    exit 1
  fi
done

install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"
AUTHORIZED_KEYS="/home/${ADMIN_USER}/.ssh/authorized_keys"
touch "${AUTHORIZED_KEYS}"

added=0
for key in "$@"; do
  if grep -Fqx -- "${key}" "${AUTHORIZED_KEYS}"; then
    echo "ja existia: ${key:0:40}..."
  else
    printf '%s\n' "${key}" >> "${AUTHORIZED_KEYS}"
    echo "adicionada: ${key:0:40}..."
    added=$((added + 1))
  fi
done

chown "${ADMIN_USER}:${ADMIN_USER}" "${AUTHORIZED_KEYS}"
chmod 0600 "${AUTHORIZED_KEYS}"

echo
echo "${added} chave(s) nova(s). Maquinas autorizadas em ${ADMIN_USER}:"
ssh-keygen -l -f "${AUTHORIZED_KEYS}"
echo
echo "Teste do computador novo, sem fechar esta sessao: ssh ${ADMIN_USER}@IP_DA_VPS"
