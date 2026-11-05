create sequence if not exists public.customer_code_sequence;

create table if not exists public.customer_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  customer_code text not null unique,
  created_at timestamptz not null default now()
);

create or replace function public.create_customer_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.customer_profiles (user_id, customer_code)
  values (new.id, 'KBH' || lpad(nextval('public.customer_code_sequence')::text, 3, '0') || 'X')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_customer_profile on auth.users;
create trigger auth_user_customer_profile
  after insert on auth.users
  for each row execute function public.create_customer_profile();

insert into public.customer_profiles (user_id, customer_code)
select existing_users.id, 'KBH' || lpad(nextval('public.customer_code_sequence')::text, 3, '0') || 'X'
from (
  select users.id
  from auth.users users
  left join public.customer_profiles profiles on profiles.user_id = users.id
  where profiles.user_id is null
  order by users.created_at, users.id
) as existing_users
on conflict (user_id) do nothing;

select setval(
  'public.customer_code_sequence',
  coalesce(max(substring(customer_code from '^KBH([0-9]+)[A-Z]$')::bigint), 1),
  coalesce(max(substring(customer_code from '^KBH([0-9]+)[A-Z]$')::bigint), 0) > 0
)
from public.customer_profiles
where customer_code ~ '^KBH[0-9]+[A-Z]$';

update public.customer_profiles
set customer_code = 'KBH' || lpad(nextval('public.customer_code_sequence')::text, 3, '0') || 'X'
where customer_code !~ '^KBH[0-9]+[A-Z]$';

alter table public.orders
  add column if not exists customer_user_id uuid references auth.users (id) on delete set null;

create index if not exists orders_customer_user_id_created_at_idx
  on public.orders (customer_user_id, created_at desc);

alter table public.customer_profiles enable row level security;

grant select on public.customer_profiles to authenticated;
grant select on public.orders, public.order_items to authenticated;

drop policy if exists "Customers can read their own profile" on public.customer_profiles;
create policy "Customers can read their own profile"
  on public.customer_profiles for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Customers can view their own orders" on public.orders;
create policy "Customers can view their own orders"
  on public.orders for select to authenticated
  using (customer_user_id = auth.uid());

drop policy if exists "Customers can view their own order items" on public.order_items;
create policy "Customers can view their own order items"
  on public.order_items for select to authenticated
  using (exists (
    select 1
    from public.orders
    where orders.id = order_items.order_id
      and orders.customer_user_id = auth.uid()
  ));

drop function if exists public.get_customer_orders(text, text);

create or replace function public.get_customer_orders_by_code(p_customer_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if upper(trim(coalesce(p_customer_code, ''))) !~ '^KBH[0-9]{3,}[A-Z]$' then
    return '[]'::jsonb;
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'order_code', o.order_code,
      'customer_room', o.customer_room,
      'payment_method', o.payment_method,
      'payment_status', o.payment_status,
      'order_status', o.order_status,
      'total', o.total,
      'created_at', o.created_at,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'product_name', item.product_name,
          'unit_price', item.unit_price,
          'quantity', item.quantity,
          'line_total', item.line_total
        ) order by item.created_at)
        from public.order_items item
        where item.order_id = o.id
      ), '[]'::jsonb)
    ) order by o.created_at desc
  )
  into result
  from public.orders o
  join public.customer_profiles profile on profile.user_id = o.customer_user_id
  where profile.customer_code = upper(trim(p_customer_code));

  return coalesce(result, '[]'::jsonb);
end;
$$;

revoke all on function public.get_customer_orders_by_code(text) from public, anon, authenticated;
grant execute on function public.get_customer_orders_by_code(text) to authenticated;