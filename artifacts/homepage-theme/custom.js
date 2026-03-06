(() => {
  const title = 'Ashar Command';
  const favicon = '/images/local/ashar-command.svg';
  const themeColor = '#101112';

  const decorateSections = () => {
    document.querySelectorAll('section').forEach((section) => {
      const heading = section.querySelector('h2');
      if (!heading) return;
      const slug = heading.textContent.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-');
      section.classList.forEach((name) => {
        if (name.startsWith('section-')) section.classList.remove(name);
      });
      section.classList.add(`section-${slug}`);
    });
  };

  const applyBrand = () => {
    document.title = title;

    for (const selector of ['link[rel="shortcut icon"]', 'link[rel="icon"]', 'link[rel="mask-icon"]']) {
      document.querySelectorAll(selector).forEach((node) => node.remove());
    }

    const icon = document.createElement('link');
    icon.rel = 'icon';
    icon.type = 'image/svg+xml';
    icon.href = favicon;
    document.head.appendChild(icon);

    let themeMeta = document.querySelector('meta[name="theme-color"]');
    if (!themeMeta) {
      themeMeta = document.createElement('meta');
      themeMeta.name = 'theme-color';
      document.head.appendChild(themeMeta);
    }
    themeMeta.content = themeColor;

    decorateSections();
    document.body.classList.add('ashar-command-ready');
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', applyBrand, { once: true });
  } else {
    applyBrand();
  }

  const observer = new MutationObserver(() => decorateSections());
  observer.observe(document.documentElement, { childList: true, subtree: true });
})();
