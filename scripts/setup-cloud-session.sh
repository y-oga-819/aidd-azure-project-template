#!/usr/bin/env bash
# クラウドの Claude Code セッション(claude.ai/code)で、CI と同じ mise の環境を用意する。
# 何度実行してもよい(入っているものは入れ直さない)。
#
# - mise は CI(.github/workflows/ci.yml)と同じ版にそろえる
# - bicep は az CLI を入れずに、infra/mise.toml の BICEP_VERSION の版を ~/.azure/bin に直接置く
#   (infra のタスクは、この版の bicep があれば az を呼ばない)
set -euo pipefail

MISE_VERSION="2026.11.7"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

export PATH="$HOME/.local/bin:$PATH"
export MISE_TRUSTED_CONFIG_PATHS="$repo_root"
export MISE_YES=1

if [ "$(mise --version 2>/dev/null | cut -d' ' -f1)" != "$MISE_VERSION" ]; then
  curl -fsSL https://mise.run | MISE_VERSION="v$MISE_VERSION" sh
fi

bicep_version="$(sed -n 's/^BICEP_VERSION = "\(.*\)"/\1/p' infra/mise.toml)"
bicep="$HOME/.azure/bin/bicep"
if ! "$bicep" --version 2>/dev/null | grep -q "$bicep_version"; then
  mkdir -p "$(dirname "$bicep")"
  curl -fsSL -o "$bicep" "https://github.com/Azure/bicep/releases/download/v${bicep_version}/bicep-linux-x64"
  chmod +x "$bicep"
fi

# ルートと各コンポーネントの mise.toml を信頼し(以降のセッションで確認を求められないように)、
# ツールと依存関係を入れる
for config in mise.toml */mise.toml; do
  mise trust --quiet "$config"
  (cd "$(dirname "$config")" && mise install --quiet)
done
mise run --quiet setup
