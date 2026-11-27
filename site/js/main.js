// Tema (escuro por padrão, salvo no localStorage), relógio da barra de menus e troca das capturas.
(function () {
  var root = document.documentElement;
  var ICON_SUN = 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4';
  var ICON_MOON = 'M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z';

  function theme() { return root.dataset.theme === 'light' ? 'light' : 'dark'; }

  function paint() {
    var dark = theme() === 'dark';
    var btn = document.getElementById('themeBtn');
    btn.setAttribute('aria-label', dark ? 'Mudar para tema claro' : 'Mudar para tema escuro');
    btn.title = btn.getAttribute('aria-label');
    document.getElementById('themeIcon').setAttribute('d', dark ? ICON_SUN : ICON_MOON);
    document.getElementById('heroShot').src = 'assets/visao-geral-' + (dark ? 'escuro' : 'claro') + '.png';
    window.dispatchEvent(new CustomEvent('themechange', { detail: theme() }));
  }

  window.setSiteTheme = function (v) {
    root.dataset.theme = v;
    try { localStorage.setItem('mastersync-theme', v); } catch (e) {}
    paint();
  };
  window.getSiteTheme = theme;

  document.getElementById('themeBtn').addEventListener('click', function () {
    window.setSiteTheme(theme() === 'dark' ? 'light' : 'dark');
  });

  var DAYS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  var MON = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  function pad(n) { return String(n).padStart(2, '0'); }
  function tick() {
    var d = new Date();
    document.getElementById('clock').textContent =
      DAYS[d.getDay()] + ' ' + d.getDate() + ' ' + MON[d.getMonth()] + '  ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  tick();
  setInterval(tick, 15000);
  paint();
})();
