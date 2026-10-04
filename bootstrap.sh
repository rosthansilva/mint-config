#!/usr/bin/env bash
# shellcheck disable=SC2088  # "~/" nas mensagens é texto exibido, não caminho
# ==============================================================================
# Bootstrap da configuração do desktop (Linux Mint / Cinnamon)
# ------------------------------------------------------------------------------
# Instala o Ansible num ambiente isolado, pergunta os dados de quem está
# rodando (nome, e-mail, perfis git, componentes opcionais), cria as chaves
# SSH e executa o setup.yml.
#
# Uso:
#   ./bootstrap.sh                  # primeira vez ou reaproveitando respostas
#   ./bootstrap.sh --reconfigurar   # pergunta tudo de novo
#   ./bootstrap.sh -- --tags theme  # repassa argumentos ao ansible-playbook
#
# As respostas ficam em ~/.config/dotfiles/vars.json (permissão 600) e não
# vão para o repositório. Senhas e passphrases nunca são gravadas.
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
VARS_FILE="$CONFIG_DIR/vars.json"
VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/venv"

RECONFIGURAR=false
ANSIBLE_ARGS=()

# Preenchidos por coletar_dados (via printf -v em perguntar)
NOME=""
EMAIL=""
PERFIS_JSON="[]"

# --- Saída formatada -----------------------------------------------------------
if [[ -t 1 ]]; then
  C_AZUL=$'\e[1;34m'; C_VERDE=$'\e[1;32m'; C_AMARELO=$'\e[1;33m'; C_VERMELHO=$'\e[1;31m'; C_RESET=$'\e[0m'
else
  C_AZUL=""; C_VERDE=""; C_AMARELO=""; C_VERMELHO=""; C_RESET=""
fi
titulo() { printf '\n%s==> %s%s\n' "$C_AZUL" "$*" "$C_RESET"; }
info()   { printf '%s  ✔ %s%s\n' "$C_VERDE" "$*" "$C_RESET"; }
aviso()  { printf '%s  ! %s%s\n' "$C_AMARELO" "$*" "$C_RESET"; }
erro()   { printf '%s  ✘ %s%s\n' "$C_VERMELHO" "$*" "$C_RESET" >&2; }

uso() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Perguntas -----------------------------------------------------------------
# perguntar <variável> <texto> [padrão] [regex de validação] [mensagem de erro]
perguntar() {
  local __var="$1" texto="$2" padrao="${3:-}" regex="${4:-}" msg_erro="${5:-Valor inválido.}"
  local resposta
  while true; do
    if [[ -n "$padrao" ]]; then
      read -r -p "  $texto [$padrao]: " resposta
      resposta="${resposta:-$padrao}"
    else
      read -r -p "  $texto: " resposta
    fi
    if [[ -z "$resposta" ]]; then
      erro "Campo obrigatório."
    elif [[ -n "$regex" && ! "$resposta" =~ $regex ]]; then
      erro "$msg_erro"
    else
      printf -v "$__var" '%s' "$resposta"
      return 0
    fi
  done
}

# confirmar <texto> <padrão s|n>  → retorna 0 para sim
confirmar() {
  local texto="$1" padrao="${2:-s}" resposta opcoes
  [[ "$padrao" == "s" ]] && opcoes="S/n" || opcoes="s/N"
  while true; do
    read -r -p "  $texto [$opcoes]: " resposta
    resposta="${resposta:-$padrao}"
    case "${resposta,,}" in
      s|sim|y|yes) return 0 ;;
      n|nao|não|no) return 1 ;;
      *) erro "Responda s ou n." ;;
    esac
  done
}

REGEX_EMAIL='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
REGEX_SLUG='^[a-z0-9][a-z0-9_-]*$'
REGEX_PASTA='^[A-Za-z0-9._/-]+$'
REGEX_CHAVE='^[A-Za-z0-9._-]+$'

# --- Etapas --------------------------------------------------------------------
ler_argumentos() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--reconfigurar) RECONFIGURAR=true ;;
      -h|--help) uso; exit 0 ;;
      --) shift; ANSIBLE_ARGS=("$@"); break ;;
      *) erro "Opção desconhecida: $1"; uso; exit 1 ;;
    esac
    shift
  done
}

checar_sistema() {
  titulo "Verificando o sistema"

  if [[ $EUID -eq 0 ]]; then
    erro "Não rode como root. Rode com seu usuário normal; o sudo será pedido quando necessário."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  # /etc/linuxmint/info existe em todo Mint, mesmo quando o os-release vem
  # do Ubuntu base (caso das imagens de container do Mint).
  if [[ "${ID:-}" == "linuxmint" || -f /etc/linuxmint/info ]]; then
    local mint_release
    mint_release="$(sed -n 's/^RELEASE=//p' /etc/linuxmint/info 2>/dev/null || true)"
    info "Linux Mint ${mint_release:-${VERSION_ID:-}} detectado."
  elif [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]]; then
    aviso "Sistema baseado em Ubuntu, mas não é o Linux Mint (${PRETTY_NAME:-$ID})."
    aviso "As partes de tema/Cinnamon/Plank assumem o desktop Cinnamon e podem falhar."
    confirmar "Continuar mesmo assim?" n || exit 1
  else
    erro "Sistema não suportado (${PRETTY_NAME:-desconhecido}). Este setup é para Linux Mint."
    exit 1
  fi

  # Tema, ícones, Plank e terminal são aplicados via dconf/gsettings, que só
  # funcionam dentro da sessão gráfica (ex.: rodando por SSH eles falham).
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    aviso "Nenhuma sessão gráfica detectada (DBUS_SESSION_BUS_ADDRESS vazio)."
    aviso "Rode este script num terminal aberto dentro do desktop Cinnamon."
    confirmar "Continuar mesmo assim? (tema/Plank/terminal vão falhar)" n || exit 1
  fi
}

instalar_ansible() {
  titulo "Preparando o Ansible"
  echo "  O sudo pode pedir sua senha para instalar as dependências do sistema."
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-venv python3-pip git openssh-client >/dev/null
  info "Dependências do sistema instaladas."

  # Ambiente isolado: não mexe no Python do sistema e sempre usa a versão
  # mais recente do ansible-core (o pacote do apt costuma estar atrasado).
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet --upgrade ansible-core
  info "$("$VENV_DIR/bin/ansible" --version | head -1)"

  "$VENV_DIR/bin/ansible-galaxy" collection install --upgrade \
    -r "$REPO_DIR/roles/dotfiles/requirements.yml" >/dev/null
  info "Coleções do Ansible instaladas."
}

coletar_dados() {
  titulo "Seus dados"
  echo "  Usados no ~/.gitconfig e nas chaves SSH. Ficam só nesta máquina, em:"
  echo "  $VARS_FILE"

  local nome_padrao email_padrao
  nome_padrao="$(git config --global user.name 2>/dev/null || true)"
  [[ -z "$nome_padrao" ]] && nome_padrao="$(getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1)"
  email_padrao="$(git config --global user.email 2>/dev/null || true)"

  perguntar NOME "Nome completo" "$nome_padrao"
  perguntar EMAIL "E-mail principal (git)" "$email_padrao" "$REGEX_EMAIL" "E-mail inválido."

  # --- Perfis git ---
  titulo "Perfis git (opcional)"
  cat <<'EOF'
  Cada perfil usa um e-mail e uma chave SSH próprios para os repositórios
  dentro de uma pasta. Ex.: perfil "empresa" para tudo em ~/workspace/empresa.
  Fora dessas pastas vale o e-mail principal acima.
EOF
  PERFIS_JSON="[]"
  local perfis=() nome_perfil email_perfil pasta chave
  if confirmar "Configurar perfis git separados (trabalho/pessoal)?" n; then
    while true; do
      echo
      perguntar nome_perfil "Nome do perfil (ex.: empresa, pessoal)" "" "$REGEX_SLUG" \
        "Use letras minúsculas, números, - ou _."
      perguntar email_perfil "E-mail do perfil '$nome_perfil'" "" "$REGEX_EMAIL" "E-mail inválido."
      perguntar pasta "Pasta dos repositórios (relativa à sua home)" "workspace/$nome_perfil" \
        "$REGEX_PASTA" "Use só letras, números, ., _, - e /."
      pasta="${pasta#/}"; pasta="${pasta%/}"
      perguntar chave "Nome da chave SSH em ~/.ssh" "id_${nome_perfil}_ed25519" \
        "$REGEX_CHAVE" "Use só letras, números, ., _ e -."
      perfis+=("$nome_perfil" "$email_perfil" "$pasta" "$chave")
      confirmar "Adicionar outro perfil?" n || break
    done
    PERFIS_JSON="$(python3 - "${perfis[@]}" <<'PY'
import json, sys
a = sys.argv[1:]
print(json.dumps([
    {"name": a[i], "email": a[i + 1], "workspace": a[i + 2], "ssh_key": a[i + 3]}
    for i in range(0, len(a), 4)
]))
PY
)"
  fi


  salvar_dados
}

salvar_dados() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  # JSON é YAML válido, então o arquivo entra direto no -e @arquivo do Ansible.
  # Montado pelo Python para escapar aspas/acentos corretamente.
  ( umask 077
    python3 - "$NOME" "$EMAIL" "$PERFIS_JSON" > "$VARS_FILE" <<'PY'
import json, sys
nome, email, perfis = sys.argv[1:4]
print(json.dumps({
    "nome_completo": nome,
    "email": email,
    "git_profiles": json.loads(perfis),
}, indent=2, ensure_ascii=False))
PY
  )
  info "Respostas salvas em $VARS_FILE"
}

carregar_ou_coletar() {
  if [[ -f "$VARS_FILE" && "$RECONFIGURAR" == false ]]; then
    titulo "Configuração existente encontrada"
    python3 - "$VARS_FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"  Nome:   {d['nome_completo']}")
print(f"  E-mail: {d['email']}")
for p in d.get("git_profiles", []):
    print(f"  Perfil: {p['name']} <{p['email']}> em ~/{p['workspace']} (chave {p['ssh_key']})")
PY
    if confirmar "Usar estas respostas?" s; then
      return 0
    fi
  fi
  coletar_dados
}

# Mostra os "instalar_*: true/false" do setup.yml e dá a chance de editar
# antes de aplicar. O setup.yml é a única fonte dessa escolha.
revisar_componentes() {
  titulo "O que será instalado (definido no setup.yml)"
  "$VENV_DIR/bin/python" - "$REPO_DIR/setup.yml" <<'PY'
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
# Toda opção true/false do setup.yml é um liga/desliga.
itens = {k.removeprefix("instalar_"): v for k, v in play.get("vars", {}).items()
         if isinstance(v, bool)}
sim = [k for k, v in itens.items() if v]
nao = [k for k, v in itens.items() if not v]
print("  Instalar:     " + (", ".join(sim) or "nada"))
print("  Não instalar: " + (", ".join(nao) or "nada"))
PY
  if ! confirmar "Continuar com esta seleção?" s; then
    echo "  Edite $REPO_DIR/setup.yml (troque para true/false) e salve."
    read -r -p "  Pressione Enter quando terminar... " _
    revisar_componentes   # mostra de novo a seleção já editada
  fi
}

criar_chaves_ssh() {
  local chaves
  chaves="$(python3 -c '
import json, sys
for p in json.load(open(sys.argv[1])).get("git_profiles", []):
    print(p["ssh_key"], p["email"])
' "$VARS_FILE")"
  [[ -z "$chaves" ]] && return 0

  titulo "Chaves SSH"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  local chave email
  while read -r chave email; do
    if [[ -f "$HOME/.ssh/$chave" ]]; then
      info "~/.ssh/$chave já existe, mantida."
      continue
    fi
    echo "  Criando ~/.ssh/$chave ($email)."
    echo "  O ssh-keygen vai pedir uma passphrase (recomendado). Ela não é salva em lugar nenhum."
    ssh-keygen -t ed25519 -C "$email" -f "$HOME/.ssh/$chave" </dev/tty
    info "~/.ssh/$chave criada."
  done <<< "$chaves"
}

rodar_playbook() {
  titulo "Aplicando a configuração"

  local cmd=("$VENV_DIR/bin/ansible-playbook" "$REPO_DIR/setup.yml"
             -e "@$VARS_FILE" --ask-become-pass)
  cmd+=("${ANSIBLE_ARGS[@]}")

  echo "  Quando aparecer \"BECOME password\", digite sua senha do sudo."
  cd "$REPO_DIR"
  ANSIBLE_ROLES_PATH="$REPO_DIR/roles" "${cmd[@]}"
}

main() {
  ler_argumentos "$@"
  checar_sistema
  instalar_ansible
  carregar_ou_coletar
  revisar_componentes
  criar_chaves_ssh
  rodar_playbook

  titulo "Pronto!"
  echo "  Adicione as chaves públicas exibidas acima no GitHub/GitLab de cada perfil."
  echo "  Faça logout/login para aplicar o tema, o shell (zsh) e o Plank."
  echo "  Para rodar de novo: $REPO_DIR/bootstrap.sh"
}

main "$@"
