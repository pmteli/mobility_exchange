import '@material/web/select/outlined-select.js';
import '@material/web/select/select-option.js';

function upgradeSelects() {
  document.querySelectorAll('select:not([multiple])').forEach(native => {
    const labels = [...native.labels];
    const text = labels.map(label => {
      const copy = label.cloneNode(true);
      copy.querySelectorAll('select, .required-field-star').forEach(node => node.remove());
      return copy.textContent.trim();
    }).join(' ') || native.getAttribute('aria-label') || 'Choose an option';
    const select = document.createElement('md-outlined-select');
    for (const attr of native.attributes) {
      if (!['class', 'style', 'size'].includes(attr.name)) select.setAttribute(attr.name, attr.value);
    }
    select.className = `material-select ${native.className}`;
    select.setAttribute('aria-label', text);
    select.noAsterisk = true;
    select.menuPositioning = 'popover';
    select.clampMenuWidth = true;
    for (const option of native.options) {
      if (!option.textContent.trim()) continue;
      const item = document.createElement('md-select-option');
      item.value = option.value;
      item.selected = option.selected;
      item.disabled = option.disabled || option.parentElement.disabled === true;
      const headline = document.createElement('div');
      headline.slot = 'headline';
      headline.textContent = option.textContent;
      item.append(headline);
      select.append(item);
    }
    labels.forEach(label => {
      label.hidden = false;
      label.classList.remove('material-select-wrapper');
    });
    native.replaceWith(select);
  });
}
upgradeSelects();
new MutationObserver(upgradeSelects).observe(document.body, {childList:true, subtree:true});
