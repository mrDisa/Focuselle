const presets = document.querySelectorAll('.rhythm-tabs button');
for (const button of presets) {
  button.addEventListener('click', () => {
    for (const preset of presets) {
      const selected = preset === button;
      preset.classList.toggle('active', selected);
      preset.setAttribute('aria-pressed', String(selected));
    }
    document.getElementById('demo-time').textContent = button.dataset.work + ':00';
    document.getElementById('demo-copy').textContent = `${button.dataset.work} минут на главное. ${button.dataset.rest} минут на себя.`;
  });
}
