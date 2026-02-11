# Font Source Guide

## Single Source of Truth

All font configuration for both the **Help Center (portal)** and the **Live Chat Widget** is controlled from one file:

```
app/javascript/shared/assets/fonts/font_variables.scss
```

This file contains:

1. **The font import** — a Google Fonts `@import` for Barlow (or whichever font you choose).
2. **The `$cw-font-family` SCSS variable** — the full font stack used everywhere.

## How to Change the Font

Edit `font_variables.scss` and update these two things:

1. Replace the `@import url(...)` with your new font source.
2. Update the `$cw-font-family` variable to list your new font first.

**Example — switching from Barlow to Inter:**

```scss
// Before
@import url('https://fonts.googleapis.com/css2?family=Barlow:ital,wght@0,100;0,300;0,400;0,500;0,600;0,700;1,400&display=swap');
$cw-font-family: 'Barlow', system-ui, 'Segoe UI', Roboto, Helvetica, Arial,
  sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol';

// After
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@100;300;400;500;600;700&display=swap');
$cw-font-family: 'Inter', system-ui, 'Segoe UI', Roboto, Helvetica, Arial,
  sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol';
```

No other files need to be changed.

## How It Flows

```
font_variables.scss   (single source — font import + $cw-font-family)
    │
    ├── widget_fonts.scss                  (re-exports font_variables)
    │       └── woot.scss                  (widget styles — uses $cw-font-family)
    │
    └── portal/application.scss            (help center styles — uses $cw-font-family)
```

### Widget (Live Chat)

- `app/javascript/shared/assets/fonts/widget_fonts.scss` imports `font_variables.scss`
- `app/javascript/widget/assets/scss/woot.scss` imports `widget_fonts.scss` and applies `$cw-font-family` to `html, body`

### Help Center (Portal)

- `app/javascript/portal/application.scss` imports `font_variables.scss` directly
- Applies `$cw-font-family` to `html, body` and to `#cw-article-content` (article body)

## Files Involved

| File | Role |
|------|------|
| `app/javascript/shared/assets/fonts/font_variables.scss` | **THE file to edit** — font import + variable |
| `app/javascript/shared/assets/fonts/widget_fonts.scss` | Re-exports font_variables for the widget |
| `app/javascript/widget/assets/scss/woot.scss` | Widget root styles — uses `$cw-font-family` |
| `app/javascript/portal/application.scss` | Portal root styles — uses `$cw-font-family` |
| `app/javascript/entrypoints/portal.js` | Portal JS entry — imports CKEditor CSS before portal SCSS so our font wins |
| `app/views/layouts/portal.html.erb` | Portal HTML layout |
