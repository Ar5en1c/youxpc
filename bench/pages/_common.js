/* Same-origin helper: reports user actions to the local recorder. */
(function () {
  var page = document.body.getAttribute('data-page');
  window.rec = function (ev) {
    ev.page = page;
    ev.client_ts = Date.now();
    try {
      return fetch('/record', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(ev),
        keepalive: true
      }).catch(function () {});
    } catch (e) { /* ignore */ }
  };
  window.addEventListener('load', function () { window.rec({ event: 'load' }); });
})();
