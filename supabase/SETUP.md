# Supabase setup

## 1. Create the Supabase project

Create a project in the Supabase dashboard and keep its database password private. It is not needed in this app.

## 2. Create the tables and policies

Open **SQL Editor**, paste the contents of `supabase/schema.sql`, and run it. This creates the products, approved-admin, pickup-settings, and product-image storage setup.
For an existing project, run `supabase/store-availability-migration.sql` if you have not already added store availability. Then run `supabase/checkout-payments-migration.sql` to add payment toggles, private order tables, and order Realtime updates, followed by `supabase/upi-checkout-migration.sql` for UPI settings and `supabase/customer-accounts-migration.sql` for complex customer IDs, per-customer access, and ID-based order lookup. Rerun the customer migration after updating this app.

## 3. Create and approve the first admin

In **Authentication → Users**, add a user with your admin email and password. Then run this in the SQL Editor, replacing the email with that account's email:

```sql
insert into public.admin_users (user_id)
select id from auth.users where email = 'admin@example.com'
on conflict (user_id) do nothing;
```

Only users listed in `admin_users` can change products, upload images, or update store settings. The app has no public admin signup form.

## 4. Connect the local app

In **Authentication → Sign In / Providers**, enable **Allow anonymous sign-ins**. The storefront creates a persistent anonymous session and a sequential customer ID automatically, such as `KBH001X`. After the first successful order, the final character becomes the first letter of the customer's name, such as `KBH001A`. Customers can search order history using this ID. It stays in that browser; clearing site data or using another device creates a different ID.

In **Project Settings → API**, copy the Project URL and the public anon/publishable key. Never use the `service_role` or secret key in this frontend.

From the project folder run:

```powershell
Copy-Item .env.example .env.local
```

Fill the values in `.env.local`:

```env
VITE_SUPABASE_URL=https://your-project-id.supabase.co
VITE_SUPABASE_ANON_KEY=your-public-anon-key
```

Restart the Vite server after changing environment values. Run `npm run dev`, then open `/#admin` and sign in with the approved account.

## 5. Deploy the order Edge Function

In Vercel, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` under **Project Settings → Environment Variables**, then redeploy the site. These are build-time variables, so changing them requires a new deployment.

Deploy `supabase/functions/create-order/index.ts` as the `create-order` Edge Function using the Supabase dashboard editor or CLI. Configure `ORDER_RATE_LIMIT_SECRET` and `PUBLIC_SITE_ORIGIN` as function secrets. Set `PUBLIC_SITE_ORIGIN` to `https://kbhnights.vercel.app` so checkout requests from the deployed site pass the function's CORS allowlist. Supabase provides `SUPABASE_URL` and its server key at runtime. After changing function code or secrets, redeploy the Edge Function.

## Orders and payment behavior

- Checkout requires a name, room block (A–E), and room number (1–600); phone number is not collected.
- Each visitor gets a persistent Supabase anonymous account and a sequential customer code. Orders are linked to that account and appear with live status updates in its order list. Clearing browser storage or switching devices creates a different anonymous account.
- Cash-at-pickup orders are saved as unpaid. UPI orders are saved as pending before opening the configured UPI app link. Admins can mark either payment as received and update order fulfillment status.
- Configure the UPI ID in the admin panel before enabling UPI payments. The UPI app opens with the saved ID and the order total calculated by the order service.
- Order creation validates current prices and availability on the server and is rate-limited. Never trust a browser subtotal as the charge amount.

## Security and scope

- Public visitors can read available products, pickup details, store status, payment availability, and UPI payment details needed to start checkout.
- Product writes and image uploads/deletes require an approved admin session, enforced by database policies.
- Customers can read only their own profile, orders, and order items; approved admins retain order-management access. Order writes are server-only and linked to a verified Supabase session.
- Product images are public to display on the storefront; only admins can upload or delete them.
- UPI redirects do not report payment completion automatically. Verify incoming payments and mark their orders paid in the admin panel.