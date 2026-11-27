#!/usr/bin/env bash
# Gera as imagens e GIFs do README a partir das telas renderizadas pelos testes (dados de exemplo, nada de aparelho real).
#
#   NEXUS_RENDER_SCALE=2 swift test --package-path macOS --filter "ShellRenderTests|MiniPlayerRenderTests|OnboardingFlowTests"
#   scripts/make-readme-media.sh [pasta-das-capturas]
#
# Precisa do ffmpeg. Os arquivos saem em docs/media/.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shots="${1:-/private/tmp/claude-501/redesign}"
out="$repo/docs/media"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

W=1000; H=640
# Corta o topo da captura (no máximo a proporção do quadro), ajusta à largura e completa com a cor da janela.
frame() { # entrada saída cor
  ffmpeg -v error -y -i "$1" -vf "crop=iw:min(ih\,iw*$H/$W):0:0,scale=$W:-1,pad=$W:$H:(ow-iw)/2:0:color=$3" "$2"
}
gif() { # saída delay_por_quadro quadros...
  local name="$1" delay="$2"; shift 2
  local i=0
  rm -f "$work"/g_*.png
  for f in "$@"; do i=$((i + 1)); cp "$f" "$work/g_$(printf '%02d' $i).png"; done
  ffmpeg -v error -y -framerate "$(awk "BEGIN{print 1/$delay}")" -i "$work/g_%02d.png" \
    -vf "split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" -loop 0 "$out/$name"
}

tour() { # tema cor
  local theme="$1" color="$2" n=0
  local files=()
  for s in visao-geral-conectado sms fotos arquivos-transferencias arquivos-pixel apps-com-apps; do
    n=$((n + 1)); frame "$shots/$s-$theme.png" "$work/t_${theme}_${n}.png" "$color"; files+=("$work/t_${theme}_${n}.png")
  done
  gif "tour-$theme.gif" 2.6 "${files[@]}"
}

tour escuro 0x161820
tour claro 0xF4F6F9

# Escuro e claro lado a lado no tempo, tela por tela.
pair() { # nome tela
  frame "$shots/$2-escuro.png" "$work/p_a.png" 0x161820
  frame "$shots/$2-claro.png" "$work/p_b.png" 0xF4F6F9
  gif "$1.gif" 1.8 "$work/p_a.png" "$work/p_b.png"
}
pair visao-geral visao-geral-conectado
pair sms sms
pair fotos fotos
pair arquivos arquivos-transferencias

# Mini player: recolhido e expandido.
for t in escuro claro; do
  ffmpeg -v error -y -i "$shots/mini-player-$t-mini.png" -vf "scale=560:-1" "$out/mini-player-$t-recolhido.png"
  ffmpeg -v error -y -i "$shots/mini-player-$t-completo.png" -vf "scale=420:-1" "$out/mini-player-$t-expandido.png"
done

# Imagens estáticas para a página.
for pair in "visao-geral:visao-geral-conectado" "sms:sms" "fotos:fotos" "arquivos:arquivos-transferencias" "armazenamento:arquivos-pixel" "apps:apps-com-apps"; do
  name="${pair%%:*}"; src="${pair##*:}"
  for t in escuro claro; do
    ffmpeg -v error -y -i "$shots/$src-$t.png" -vf "crop=iw:min(ih\,iw*0.75):0:0,scale=1100:-1" "$out/$name-$t.png"
  done
done
# Primeiro uso (boas-vindas e escolha de recursos).
for t in escuro claro; do
  ffmpeg -v error -y -i "$shots/onboarding-welcome-$t.png" -vf "scale=420:-1" "$out/onboarding-boas-vindas-$t.png"
  ffmpeg -v error -y -i "$shots/onboarding-features-$t.png" -vf "scale=420:-1" "$out/onboarding-recursos-$t.png"
done
echo "Pronto: $out"
ls -la "$out" | awk '{print $5, $9}'
