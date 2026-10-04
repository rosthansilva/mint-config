# Desktop Linux Mint — configuração automática

Transforma uma instalação nova do **Linux Mint 22 (Cinnamon)** num desktop
pronto: tema Nord, terminal com Zsh/Tmux, ferramentas de desenvolvimento,
apps de criação, áudio profissional para o Bitwig Studio e jogos.
Tudo é feito com Ansible e pode ser rodado de novo quantas vezes quiser.

## Começo rápido

Num **terminal aberto dentro do desktop** (não por SSH, porque tema, Plank e
atalhos só podem ser aplicados de dentro da sessão gráfica):

```bash
git clone <url-deste-repositorio> ~/config
cd ~/config
./bootstrap.sh
```

O `bootstrap.sh`:

1. confere se o sistema é Linux Mint e se você não está rodando como root;
2. instala a versão mais recente do Ansible num ambiente isolado
   (`~/.local/share/dotfiles/venv`), sem mexer no Python do sistema;
3. pergunta **nome**, **e-mail** e, se quiser, **perfis git** (ex.: um e-mail
   e uma chave SSH só para os repositórios da empresa);
4. mostra o que vai ser instalado (definido no `setup.yml`) e deixa você
   editar antes de continuar;
5. cria as chaves SSH com o `ssh-keygen`; a passphrase é digitada direto nele
   e não é salva em lugar nenhum;
6. aplica a configuração. A senha do sudo é pedida duas vezes: pelo script
   e pelo Ansible ("BECOME password").

No final, **faça logout e login** (tema, shell, grupos de áudio) e **reinicie**
se ativou os ajustes de latência do kernel.

### Rodando de novo

```bash
./bootstrap.sh                   # reaproveita as respostas salvas
./bootstrap.sh --reconfigurar    # pergunta tudo de novo
./bootstrap.sh -- --tags theme   # aplica só uma parte (veja as tags abaixo)
```

As respostas ficam em `~/.config/dotfiles/vars.json` (permissão 600, fora do
repositório). Não coloque senhas nesse arquivo.

## Escolhendo o que instalar

Abra o `setup.yml`: cada item tem uma linha `instalar_*: true` com um
comentário explicando o que é. Troque para `false` o que não quiser. O dock
(Plank) só mostra os apps que foram instalados.

| Grupo | Itens |
|---|---|
| Terminal | zsh (Oh My Zsh + Starship), tmux, wezterm, fastfetch |
| Desenvolvimento | VS Code, Podman + podman-compose, template de devcontainer, Godot (+ export templates e integração com o VS Code) |
| Desktop | Plank, Flameshot (tecla Print), tema do Firefox, Brave, Timeshift, Free Download Manager e JDownloader (Flatpak) |
| Criação | Krita, Kdenlive, OBS Studio, GIMP, Inkscape, VLC, Aseprite (compilado do código-fonte) |
| Áudio | PipeWire profissional, ajustes de latência do kernel, CPU em modo performance, Bitwig Studio, plugins VST3/CLAP grátis, ToneLib-Zoom (via Distrobox) |
| Jogos | Steam, Heroic Games Launcher |

Sempre aplicados (base): tema Nord do Cinnamon, ícones, cursor, fontes
(JetBrains Mono Nerd Font), git (`.gitconfig`, perfis, delta), perfil Nord do
GNOME Terminal e ferramentas de linha de comando (ripgrep, fd, bat, fzf, btop,
jq, tldr, neovim).

Ajustes finos (tema, lista de ferramentas base, latência do áudio) ficam em
`roles/dotfiles/defaults/main.yml`.

### Atenção

- **Podman** remove o Docker (`docker.io`/`docker-ce`) se estiver instalado.
  O comando `docker` passa a usar o Podman.
- **cpu_performance** deixa a CPU sempre na frequência máxima: bom para áudio,
  ruim para bateria de notebook.
- **Bitwig Studio**: a licença é ativada dentro do próprio app.
- **Aseprite**: é compilado na sua máquina a partir do código-fonte oficial
  (10–30 min na primeira vez e a cada versão nova). A licença do Aseprite
  permite compilar para uso pessoal, mas não redistribuir o programa
  compilado — não copie o binário para outras pessoas.

## Áudio para o Bitwig

Com `configurar_audio_pro: true`:

- apps JACK (como o Bitwig) usam o PipeWire diretamente, sem `jackd`.
  No Bitwig, em *Settings → Audio*, escolha o driver **JACK**;
- seu usuário entra nos grupos `pipewire` e `audio` (prioridade de tempo real);
- latência padrão: buffer de 256 a 48 kHz (≈ 5,3 ms), ajustável em
  `pipewire_quantum` / `pipewire_sample_rate`;
- **qpwgraph** para ligar entradas e saídas de áudio e MIDI visualmente.

Com `otimizar_latencia_audio: true`, o kernel recebe `preempt=full threadirqs
usbcore.autosuspend=-1` (vale após reiniciar).

### Plugins (VST3/CLAP)

O Bitwig não carrega LV2, então só entram plugins com versão nativa para
Linux em VST3 ou CLAP. Cada um tem um toggle `vst_*` no `setup.yml`;
`instalar_plugins_audio: false` desliga todos. Os plugins vêm sempre da última
versão publicada e são atualizados ao rodar o playbook de novo.

| Uso | Plugins |
|---|---|
| Sintetizadores e samplers | Surge XT, Odin 2, OB-Xd, Podolski e TyrellN6 (u-he), Nils' K1v, Cardinal (rack modular, ~1,1 GB), ChowKick (bumbo), DecentSampler |
| Guitarra: **NAM** e **IR** | Ratatouille (`.nam`/AIDA-X + 2 IRs mixáveis) e NeuralRack (pedal + EQ + amp `.nam` + IR estéreo), ambos CLAP; LSP Impulse Responses (IR avulso, qualquer faixa) |
| Guitarra: pedais | BYOD (monta cadeias de overdrive/fuzz/amp), ChowCentaur (Klon), Proteus (capturas GuitarML), TAL-Chorus-LX, TAL-Dub-X, ChowPhaser, Flying Phaser, ChowTapeModel |
| Mix e master | Airwindows Consolidated (300+ processadores, com interface), LSP Plugins, ZL Equalizer 2, ZL Spectrum Equalizer, ZL Compressor, ZL Splitter, ChowMultiTool, Dragonfly Reverb, Reevr, QDelay, Time-12, ZAM |
| Voz | Graillon 3 Free (afinação/pitch, CLAP) |
| Criativos | Gate-12, Filtr, TAL-Reverb-4 |

Depois de instalar: no Bitwig, *Settings → Plug-ins → Rescan*.

Vindo dos Waves: F6/Q10 → ZL Equalizer 2; C6 → LSP Multiband; L1/L2 →
LSP Limiter; CLA/SSL → ZL Compressor e Airwindows; J37/Kramer → ChowTapeModel e
Airwindows ToTape; NLS/consoles → Airwindows Console; PAZ/WLM → LSP Analyzer e
Loudness Meter; S1/Center → ZL Splitter (M/S).

### Atualizações e limite do GitHub

Plugins, Godot e Distrobox são baixados sempre na última versão, mas a busca
por versão nova acontece **no máximo uma vez por dia** (`atualizacoes_intervalo_horas`
em `roles/dotfiles/defaults/main.yml`). Rodar o playbook várias vezes no mesmo
dia não acessa a internet de novo para eles.

```bash
./bootstrap.sh -- -e dotfiles_forcar_atualizacao=true   # verificar tudo agora
```

A API do GitHub permite 60 consultas por hora sem login (uma instalação
completa usa umas 30). Se o limite estourar, o que já está instalado continua
como está; para instalar algo novo antes disso, aguarde ou rode com
`GITHUB_TOKEN` definido no ambiente (um token sem permissões extras, guardado
num gerenciador de senhas — nunca no repositório).

Não incluídos (dá para baixar à mão):
- **Vital**: grátis, mas o download exige login no site;
- **Zebralette**: no Linux só vem dentro do Zebra2 (pago, roda como demo);
- **LoudMax**: no Linux só existe em LADSPA, que o Bitwig não carrega;
- **fircomp 2**: build Linux marcado pelo autor como "só para testes";
- **GVST GTune** e **OS-251**: sem download direto automatizável;
- **yabridge** (plugins de Windows): hoje só funciona com o Wine 9.21, uma
  versão antiga e sem correções de segurança.

Os plugins da u-he (Podolski, TyrellN6) usam o instalador oficial deles:
os dados ficam em `~/.u-he` e o VST3 em `~/.vst3`.

## Tags

Para aplicar só uma parte: `./bootstrap.sh -- --tags <tag>[,<tag>]`.

`theme` `icons` `cursors` `cinnamon` `ui` · `terminal` `terminal_theme` `zsh`
`tmux` `wezterm` `fastfetch` · `git` `git_profiles` · `vscode` `podman`
`devcontainer` `godot` · `apps` `aseprite` `flameshot` `firefox` `brave` `timeshift`
`plank` `flatpak` · `audio` `latencia` `bitwig` `plugins` `tonelib_zoom` · `steam` `heroic`

As tasks `nala`, `git` e `fonts` rodam sempre.

## Estrutura

```
bootstrap.sh              instalação guiada (comece por aqui)
setup.yml                 playbook principal + o que instalar
roles/dotfiles/
  defaults/main.yml       valores padrão de todas as opções
  tasks/main.yml          ordem de execução e condições de cada componente
  tasks/*.yml             uma tarefa por componente
  files/launchers/        atalhos do Plank
  molecule/default/       testes em container
_arquivo/                 arquivos antigos, fora de uso
```

## Testes (para quem for alterar o projeto)

A role é testada com [Molecule](https://ansible.readthedocs.io/projects/molecule/)
num container do Linux Mint 22.3, usando Podman e sem tocar na sua máquina:

```bash
python3 -m venv .venv-test && .venv-test/bin/pip install -r requirements-test.txt
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
cd roles/dotfiles
../../.venv-test/bin/molecule converge                  # aplica tudo no container
../../.venv-test/bin/molecule converge -- --tags godot  # só uma parte
../../.venv-test/bin/molecule verify                    # checagens em molecule/default/verify.yml
```

Os dados pessoais usados nos testes são fictícios (`example.com`).
