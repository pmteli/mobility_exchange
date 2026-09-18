# Material 3 application theme

All Rails browser screens load the Material 3 visual layer from the shared head
partial. Both public and operations layouts use it. The implementation translates
Material 3 design guidance into semantic HTML and CSS; it is not a Figma file
import and does not depend on Google's maintenance-mode Material Web package.

## Design system

- `public/material3.css`: named Material color, shape, typography, elevation and
  motion tokens; component styles and responsive overrides.
- `public/app.css`: existing page layout foundations. Add theme changes to the
  Material layer, which loads after this file.
- `public/fonts/Roboto-Variable.ttf`: self-hosted Roboto with its SIL OFL license.
  No external font or script CDN is required.
- `public/material3.js`: optional Escape/outside-click behavior for disclosure
  navigation. Native menus and forms also work without JavaScript.
- `app/views/design/_navigation_links.html.erb`: shared public menu destinations
  and current-page indication for desktop and compact layouts.

The blue primary, green tertiary and light tonal surfaces retain Mobility
Exchange's identity. Components include filled/tonal/outlined buttons, outlined
fields, selection controls, cards, chips, feedback banners, data tables, location
tabs, app bars and navigation drawers. The existing hero and logo are preserved.

Public navigation changes to a native disclosure menu at 960px. Staff navigation
uses the existing compact workspace menu at that breakpoint. Content grids stack
at narrow widths; tables scroll within their own containers. The theme includes
visible keyboard focus, reduced-motion support, 48px action targets, and
forced-color rules. Form labels remain visible while entering values.

Coverage includes authentication, account/profile, equipment catalog/details,
equipment and monetary donations, requests/signing/booking, volunteer application
and shifts, content pages, and staff dashboard/inventory/reviews/schedules/content/
reports. Email templates and Stripe-hosted checkout have separate renderers and
are outside this browser stylesheet.

## Verification

Existing Rails suite: 44 tests, 488 assertions, passing. Chrome responsive checks
cover home, catalog, signup, login and password-reset request pages at 320, 390,
768 and 1440px. Read-only render fixtures cover the staff dashboard, inventory,
equipment form, and money/equipment donation forms at those widths. Visual
fixtures are not routes and do not create users or permission grants.

Sources:
- https://m3.material.io/styles/color/roles
- https://m3.material.io/components/navigation-drawer/overview
- https://github.com/material-components/material-web/blob/main/docs/theming/typography.md
- https://github.com/material-components/material-web (maintenance status)
