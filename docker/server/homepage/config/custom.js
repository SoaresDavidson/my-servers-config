// Em casa (dashboard aberto pelo IP da LAN) os links do Tailscale viram
// http://<IP>:<porta>, acessando o app direto pela porta publicada no host.
// Fora de casa (aberto por homepage.<tailnet>.ts.net) nada muda.
(() => {
  const host = location.hostname;
  if (host.endsWith(".ts.net")) return;

  // Subdomínio no tailnet -> porta publicada no host (ver docker-compose de cada app).
  // Apps sem porta na LAN (ex.: OnlyOffice) ficam fora e seguem pelo Tailscale.
  const LAN_PORTS = {
    jellyfin: 8096,
    jellyseerr: 5055,
    sonarr: 8989,
    radarr: 7878,
    bazarr: 6767,
    prowlarr: 9696,
    profilarr: 6868,
    calibre: 8082,
    shelfarr: 5056,
    nextcloud: 7580,
    dozzle: 8888,
    adguard: 3080,
  };

  const rewrite = (a) => {
    let url;
    try {
      url = new URL(a.href);
    } catch {
      return;
    }
    if (url.protocol !== "https:" || !url.hostname.endsWith(".ts.net")) return;
    const port = LAN_PORTS[url.hostname.split(".")[0]];
    if (!port) return;
    a.href = `http://${host}:${port}${url.pathname}${url.search}${url.hash}`;
  };

  const scan = (root) => root.querySelectorAll?.("a[href^='https://']").forEach(rewrite);

  // O dashboard é renderizado pelo React depois do custom.js; observa o DOM
  // para pegar os cards que aparecem depois.
  scan(document);
  new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.type === "attributes") rewrite(m.target);
      else m.addedNodes.forEach((n) => (n.tagName === "A" ? rewrite(n) : scan(n)));
    }
  }).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["href"],
  });
})();
