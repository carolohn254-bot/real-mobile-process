# Setup and GitHub Pages deployment

This version contains **no PHP**. The customer and administrator interface uses HTML, CSS and JavaScript. Supabase provides authentication, PostgreSQL storage, row-level security and transaction functions. GitHub Pages hosts the static website.

## 1. Configure Supabase

The project credentials supplied earlier are prefilled in `config.js`:
- Project URL: `https://eadrnuxaddgdnddkyqtq.supabase.co`
- Publishable key: the `sb_publishable_...` value supplied for this project.

If Supabase shows a different Project URL or key in your dashboard, replace the values in `config.js` with the exact values from **Supabase Dashboard → Project Settings → API**. Use only the publishable/anon key in the browser. Never paste a `service_role` or secret key into `config.js`, GitHub, or a public repository.

1. Open the Supabase project `real-time-mobile-banking`.
2. Open **SQL Editor → New query**.
3. Open `supabase-schema.sql`, copy the complete contents, paste into SQL Editor and click **Run**.
4. Confirm the query completes without errors. This script creates the `mb_` tables, access policies, signup trigger and secure transaction function. It uses `mb_` table names so it can coexist with earlier tables from the PHP version.
5. In **Authentication → Providers → Email**, enable Email provider. For a classroom demonstration you may turn off email confirmation; for real users leave confirmation enabled.
6. In **Authentication → URL Configuration**, add your future GitHub Pages URL to Site URL and Redirect URLs after publishing (for example `https://YOUR-GITHUB-NAME.github.io/YOUR-REPOSITORY/`).

## 2. Create the administrator safely

Do not allow users to choose the administrator role on the public registration form.

1. In Supabase, open **Authentication → Users → Add user**.
2. Create the administrator with an email address you control and a strong password. Confirm the user if the dashboard offers that option.
3. Open **SQL Editor** and run the following statement, replacing the email with the exact admin email:

```sql
update public.mb_profiles
set role = 'admin'
where email = 'your-admin-email@example.com';
```

4. Confirm one row was updated. The administrator now signs in on the same login page as customers. The application checks the database role and opens the administrator dashboard.

Customer accounts are created from **Create account** on the website. The signup trigger automatically creates a customer profile and a zero-balance simulated account.

## 3. Test the system

1. Sign in as the administrator. The dashboard displays registered customers, total balances, transaction count, complaints, notifications, customer list, transactions and audit events.
2. Log out and create a customer account using a different email.
3. Sign in as that customer. The customer can view their own balance/history, submit a simulated deposit or withdrawal, transfer to another customer's account number, and submit a complaint.
4. Sign back in as administrator and refresh the dashboard to see the updated records.

**Important:** deposits and transfers are academic simulations. They do not connect to banks or move real money. Newly registered customers start with KSh 0.00. Use the customer deposit function to add simulated test funds.

## 4. Publish using GitHub Pages

1. Sign in to GitHub and create a new **Public** repository, for example `real-time-mobile-banking`.
2. Extract this ZIP on your computer.
3. Upload the files and folders in the extracted project root (`index.html`, `style.css`, `app.js`, `config.js`, `supabase-schema.sql`, this guide and README). Do not upload a PHP project or database passwords.
4. In the repository, open **Settings → Pages**.
5. Under **Build and deployment**, choose **Deploy from a branch**.
6. Select branch `main`, folder `/ (root)`, then click **Save**.
7. Wait for GitHub Pages to finish. Your site address will look like `https://YOUR-GITHUB-NAME.github.io/real-time-mobile-banking/`.
8. Copy that URL into Supabase **Authentication → URL Configuration** as the Site URL and add it to Redirect URLs.
9. Open the published URL on a phone and computer and test both roles.

GitHub Pages only hosts the static frontend. Supabase remains the backend and database. Do not expect PHP or MySQL files to run on GitHub Pages.

## 5. Security notes

- The Supabase publishable key is intended for browser use; database safety comes from Row Level Security and restricted SQL functions.
- Never publish a Supabase `service_role` key or database password.
- The administrator role must only be assigned in the trusted Supabase dashboard/SQL Editor.
- Review RLS policies before using real personal or financial information. This is a student demonstration, not a production banking platform.
- Use strong passwords and remove public demo accounts before sharing the site broadly.

## Troubleshooting

- **Invalid API key / failed connection:** verify that `config.js` contains the exact Project URL and matching publishable key from the same Supabase project. The URL must be the base URL only, without `/rest/v1/`.
- **Could not find table / relation missing:** run all of `supabase-schema.sql` in the intended Supabase project.
- **Account created but not signed in:** email confirmation may be enabled. Confirm the email, or turn confirmation off for a controlled classroom demo.
- **Profile missing after signup:** check Supabase SQL Editor logs and confirm the `mb_auth_user_created` trigger exists.
- **Customer sees no starting funds:** new accounts start at zero; sign in as the customer and use a simulated deposit.
- **Admin dashboard access denied:** verify that the admin user exists in Authentication → Users and that the matching `mb_profiles.email` row has role `admin` and status `active`.
