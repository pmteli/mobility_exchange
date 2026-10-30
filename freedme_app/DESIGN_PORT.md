# Prototype design port

Source: `../prototype/dist/index.html`, `style.css`, `app.js` render functions and `assets/`, reviewed at http://127.0.0.1:8767/#home.

The source CSS is preserved at the beginning of `app/assets/stylesheets/application.css`. Rails adapters follow it. Original logo, illustrations and SVG artwork are in `public/prototype-assets`. Header, footer, dialog and activity-tab partials are in `app/views/shared`.

Public pages use ERB templates, standard Rails URLs and the existing database catalog query. The catalog/detail views preserve the prototype card and split layout; missing real photographs use an explicit placeholder. No fictional equipment was inserted into the database.

`/design-preview` exposes nine immutable fictional screen examples: catalog, item details, donor activity, recipient activity, moderator activity, donation, edit, registration and sign-in. These render server-side partials. The prototype's localStorage simulator, account logic and lifecycle mutations are not loaded. Read-only UI examples are separate from the authentication-protected dashboard controllers.

Presentation JavaScript implements the mobile dropdown, accessible tabs (including keyboard navigation), image rotation/swipe, dialogs, and conditional Loan Until field. Forms and workflow actions show a preview notice rather than saving or sending information. Uploads are disabled. Actual authenticated workflows still need backend integration.

The How It Works text was reconciled with the user's later identity decisions: both gifts and loans require evidence; donors see verified name and ZIP, not street address. Homepage wording was preserved as requested; the broad “No ... other personal information” statement still needs content review because registration needs a display name and requesting equipment requires evidence. DEC01–DEC06 remain open. No policy gates were enabled.

Requirement mapping: FR007–008 public catalog/details, FR004 donation form, FR021–022 identity and limited disclosure, FR026 registration boundary, FR037 responsive/accessibility presentation, FR041 Q&A templates, FR042 dashboard tabs, FR036 separation of simulation and real services.

Validation: Rails suite passes with 13 tests / 656 assertions. Browser checks verified desktop homepage against the source, mobile layout at 390×844, menu expansion, donor tab switching, answer dialog/focus restoration, Loan Until visibility and image rotation. The original prototype and Lightsail deployment were not modified.
