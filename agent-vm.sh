# agent-vm — AI エージェント CLI を microsandbox の microVM 内で起動する
#
#   usage: agent-vm <agent> [name] [-r]
#
# このファイルの内容を ~/.zshrc（bash なら ~/.bashrc）に貼り付けるか、
# source /path/to/agent-vm.sh で読み込んでください。zsh / bash 用です。
#
# 環境変数（この関数より前に export してください）
#   AGENT_VM_HOME      雛形スナップショットの保存先   既定: ~/.agent-vm
#   AGENT_VM_CONF_DIR  エージェント定義の置き場       既定: $AGENT_VM_HOME/conf
#   AGENT_VM_MEM       メモリの上書き（例 2G）        既定: yaml の値
#   AGENT_VM_DISK      ルートディスクのサイズ         既定: 4G

: "${AGENT_VM_HOME:=$HOME/.agent-vm}"
: "${AGENT_VM_CONF_DIR:=$AGENT_VM_HOME/conf}"
: "${AGENT_VM_DISK:=4G}"

agent-vm() {
  local agent="" name="" force=0 arg
  local memflag=()

  for arg in "$@"; do
    case "$arg" in
      -r) force=1 ;;
      -*) echo "[agent-vm] 不明なオプション: $arg"; return 1 ;;
      *)  if [ -z "$agent" ]; then agent="$arg"; else name="$arg"; fi ;;
    esac
  done

  [ -n "$agent" ] || { echo "usage: agent-vm <agent> [name] [-r]"; return 1; }
  command -v msb >/dev/null || {
    echo "[agent-vm] msb が見つかりません。microsandbox をインストールしてください。"
    return 1
  }

  local conf="$AGENT_VM_CONF_DIR/$agent.yaml"
  local snap="$AGENT_VM_HOME/$agent.msb"
  local dir="${name:-$(basename "$PWD")}"
  local vm="${agent}-${dir}"
  local vol="${agent}-auth"
  local base="${agent}-base"

  [ -f "$conf" ] || { echo "[agent-vm] 設定がありません: $conf"; return 1; }
  [ -n "$AGENT_VM_MEM" ] && memflag=(--memory "$AGENT_VM_MEM")

  # 認証情報の保存先。yaml の「# agent-vm: auth-dir=...」から読む。
  local authdir
  authdir="$(sed -n 's/^#[[:space:]]*agent-vm:[[:space:]]*auth-dir=//p' "$conf" | head -1)"
  : "${authdir:=/root/.$agent}"

  # ── 雛形（インストール済みイメージ）。認証は含めない。
  if [ "$force" = 1 ] || [ ! -f "$snap" ]; then
    echo "[agent-vm] 雛形を作成します。数分かかります。"
    mkdir -p "$AGENT_VM_HOME"
    msb run --name "$base" --replace \
      --conf "$conf" "${memflag[@]}" --root-disk "$AGENT_VM_DISK" \
      -- setup || return 1
    msb snap create --sandbox "$base" -o "$snap" -f || return 1
    msb rm -f "$base" >/dev/null
    echo "[agent-vm] 雛形を保存しました: $snap"
  fi

  # ── 認証ボリューム。全 VM で共有し、ホスト側に実体が残る。
  msb volume ls 2>/dev/null | grep -q "\b${vol}\b" || {
    msb volume create "$vol" >/dev/null || return 1
  }

  # ── プロジェクト用 VM
  if ! msb ls | grep -q "\b${vm}\b"; then
    msb snap restore "$snap" --name "$vm" \
      -v "$PWD:/workspace/$dir" \
      -v "$vol:$authdir" || return 1
  fi

  msb exec -t "$vm" -w "/workspace/$dir" -- agent-start
}
