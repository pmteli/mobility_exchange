# Modern website design → Rails views

The Rails application now uses the newer **Modern (Design 02)** website direction selected for this project: navy hero and partner sections, blue actions, lime highlights, white cards, and responsive operations screens.

## Design sources

The project’s latest saved alternative is `mobility-prototype/template/modern.css`, layered over the revised `Mobility-Exchange-Preview.html` template. The existing published website was inspected for its logo, page structure, equipment illustrations, forms, and workspace layout.

The supplied logo is preserved as `public/design/mobility-exchange-logo.jpg`. Equipment SVG illustrations are extracted from the supplied template and labeled as illustrations rather than product photographs. All assets are local; no external font or image service is required.

## View structure

- `app/views/layouts/application.html.erb`: public website layout.
- `app/views/layouts/operations.html.erb`: shared sidebar, desktop toolbar, and mobile workspace menu.
- `app/views/design`: logo, header, footer, hero artwork, authentication illustration, flash messages, and SVG icons.
- `app/views/catalog`: homepage, searchable catalog, shared cards, and equipment details.
- `app/views/donations`, `equipment_requests`, `accounts`, and `volunteer_applications`: redesigned public forms and account/record views.
- `app/views/staff`: all staff views inherit the operations design; the dashboard uses actual inventory totals.
- `public/app.css`: reusable design tokens, components, and responsive breakpoints.
- `app/helpers/design_helper.rb`: equipment illustrations, icons, and permission-aware workspace navigation.

The homepage shows up to three available items and links to the full `/equipment` catalog. Existing query URLs at the root continue to work. Rails forms still submit to their existing controllers with CSRF protection, permitted parameters, ownership checks, and database-backed workflows.

## Responsive behavior

The public navigation scrolls horizontally on narrow phones. Forms and cards stack into one column; sign-in uses a split illustration/form layout on desktop. The staff sidebar becomes a native expandable menu on mobile, and tables scroll inside keyboard-focusable containers. Typography, form controls, and touch targets scale without changing the workflow rules.

## Browser verification

Visual checks were performed with an isolated sample-data Rails server:

- Desktop, 1280px: homepage, operations dashboard, and inventory workspace.
- Phone, 390px: homepage, donation form, dashboard, expandable workspace menu, and inventory table.
- Small phone, 320px: filtered equipment catalog.
- Tablet, 768px: equipment details.

Measured document width matched viewport width in the checked mobile/tablet pages. Equipment illustrations loaded successfully. Catalog filtering and mobile workspace navigation were exercised in the browser. The existing Rails test suite also passed: **16 tests, 148 assertions, no failures or errors**.

No prototype demo-login shortcuts or mock JavaScript API were copied into the Rails app. Public links correspond to implemented Rails routes. Broader feature coverage remains documented in `FEATURES.md`.
