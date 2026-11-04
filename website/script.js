(() => {
  const demo = document.querySelector('.demo');
  const steps = [...document.querySelectorAll('[data-go]')];
  const playButton = document.getElementById('play-demo');
  const status = document.getElementById('demo-status');
  const descriptions = [
    'Step 1: Start dragging a file from Finder.',
    'Step 2: Drop the file onto Plupo while you find the destination.',
    'Step 3: Drag the file from Plupo into your project.'
  ];
  let current = 0;
  let timer;
  const stop = () => {
    window.clearInterval(timer);
    timer = undefined;
    playButton.innerHTML = 'Play demo <span aria-hidden="true">▶</span>';
    playButton.setAttribute('aria-label', 'Play walkthrough');
  };
  const showStep = (step) => {
    current = step;
    demo.dataset.step = String(step);
    steps.forEach((button, index) => {
      button.classList.toggle('active', index === step);
      button.setAttribute('aria-pressed', String(index === step));
    });
    status.textContent = descriptions[step];
  };
  steps.forEach((button) => button.addEventListener('click', () => {
    stop();
    showStep(Number(button.dataset.go));
  }));
  playButton.addEventListener('click', () => {
    if (timer) { stop(); return; }
    showStep(0);
    playButton.innerHTML = 'Pause <span aria-hidden="true">Ⅱ</span>';
    playButton.setAttribute('aria-label', 'Pause walkthrough');
    timer = window.setInterval(() => {
      if (current === 2) { stop(); return; }
      showStep(current + 1);
    }, 2300);
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });

  // An optional enhancement: downloads and release links work without JavaScript or the API.
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 5000);
  fetch('https://api.github.com/repos/planetic-labs/plupo/releases/latest', {
    headers: { Accept: 'application/vnd.github+json' },
    signal: controller.signal
  })
    .then((response) => { if (!response.ok) throw new Error('Release unavailable'); return response.json(); })
    .then((release) => {
      if (!release.draft && !release.prerelease && /^v\d+\.\d+\.\d+$/.test(release.tag_name)) {
        document.getElementById('latest-release').textContent = `${release.tag_name} · Release notes`;
      }
    })
    .catch(() => { /* Keep the permanent latest-release link when offline or rate limited. */ })
    .finally(() => window.clearTimeout(timeout));
})();
