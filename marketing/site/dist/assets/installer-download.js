// Track the click without waiting before the browser follows the installer link.
document.querySelector('[data-installer-version]')?.addEventListener('click', ({ currentTarget }) => {
  const { installerVersion, installerLanguage } = currentTarget.dataset;
  window.umami?.track('installer_download_click', {
    version: installerVersion,
    language: installerLanguage,
  });
});
