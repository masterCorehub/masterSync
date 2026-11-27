# Site do masterSync

Página de apresentação do app de Mac e Android. HTML, CSS e JavaScript puros, sem build e sem dependências.

## Ver localmente

```bash
cd site
python3 -m http.server 4173
```

Abra http://localhost:4173.

## Estrutura

- `index.html`: a página (barra de menus do Mac, cena de desktop, blocos, privacidade, download).
- `css/style.css`: paleta e vidro (tokens em `:root`, tema claro em `[data-theme="light"]`) e todas as animações.
- `js/main.js`: tema (salvo no `localStorage`), relógio da barra de menus e troca das capturas.
- `js/demo.js`: simulador interativo do app de Mac, com dados de exemplo.
- `assets/`: logo e capturas de tela.

## A fazer

- Ligar os botões de download (`data-download="mac"` e `data-download="android"`) aos arquivos reais.
