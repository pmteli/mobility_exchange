// Native disclosure menus work without JS. Add Escape and outside-click dismissal.
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  document.querySelectorAll('.public-menu[open], .portal-menu[open]').forEach((menu) => {
    menu.removeAttribute('open');
    menu.querySelector('summary').focus();
  });
});
document.addEventListener('click', (event) => {
  document.querySelectorAll('.public-menu[open], .portal-menu[open]').forEach((menu) => {
    if (!menu.contains(event.target)) menu.removeAttribute('open');
  });
});
