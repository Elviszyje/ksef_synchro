/* Pokazuje przycisk App Store, gdy w config.js jest ustawiony APP_STORE_URL. */
(function () {
  var url = typeof APP_STORE_URL === "string" ? APP_STORE_URL.trim() : "";
  if (!/^https:\/\//.test(url)) return;
  document.querySelectorAll("[data-app-store-link]").forEach(function (a) {
    a.href = url;
    a.hidden = false;
  });
  document.querySelectorAll("[data-app-store-soon]").forEach(function (el) {
    el.hidden = true;
  });
})();
