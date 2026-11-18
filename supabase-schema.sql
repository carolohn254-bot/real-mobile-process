-- Real-Time Mobile Banking (GitHub Pages + Supabase)
-- Run this complete script in Supabase Dashboard > SQL Editor > New query.
-- Uses mb_ table names so it does not collide with earlier project tables.
create extension if not exists pgcrypto;

create table if not exists public.mb_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  role text not null default 'customer' check (role in ('customer','admin')),
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now()
);
create table if not exists public.mb_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.mb_profiles(id) on delete cascade,
  account_number text not null unique,
  balance numeric(14,2) not null default 0 check (balance >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.mb_transactions (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  account_id uuid not null references public.mb_accounts(id),
  user_id uuid not null references public.mb_profiles(id),
  type text not null check (type in ('deposit','withdrawal','transfer')),
  direction text not null check (direction in ('credit','debit')),
  amount numeric(14,2) not null check (amount > 0),
  balance_after numeric(14,2) not null check (balance_after >= 0),
  counterparty_account text,
  description text,
  created_at timestamptz not null default now()
);
create table if not exists public.mb_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.mb_profiles(id) on delete cascade,
  transaction_id uuid references public.mb_transactions(id) on delete set null,
  message text not null,
  channel text not null default 'APP',
  status text not null default 'sent' check (status in ('sent','failed','pending')),
  created_at timestamptz not null default now()
);
create table if not exists public.mb_complaints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.mb_profiles(id) on delete cascade,
  issue_type text not null,
  description text not null,
  status text not null default 'open' check (status in ('open','in progress','resolved')),
  admin_response text,
  created_at timestamptz not null default now()
);
create table if not exists public.mb_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.mb_profiles(id) on delete set null,
  action text not null,
  details text,
  created_at timestamptz not null default now()
);
create index if not exists mb_tx_user_date_idx on public.mb_transactions(user_id,created_at desc);
create index if not exists mb_notice_user_date_idx on public.mb_notifications(user_id,created_at desc);
create index if not exists mb_complaint_status_idx on public.mb_complaints(status);

create or replace function public.mb_is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.mb_profiles where id=auth.uid() and role='admin' and status='active'); $$;

create or replace function public.mb_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_name text; v_phone text; v_account text;
begin
  v_name := coalesce(nullif(new.raw_user_meta_data->>'full_name',''), split_part(new.email,'@',1));
  v_phone := new.raw_user_meta_data->>'phone';
  insert into public.mb_profiles(id,full_name,phone,email) values(new.id,v_name,v_phone,new.email)
  on conflict(id) do nothing;
  v_account := 'MB' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into public.mb_accounts(user_id,account_number,balance) values(new.id,v_account,0)
  on conflict(user_id) do nothing;
  return new;
end; $$;
drop trigger if exists mb_auth_user_created on auth.users;
create trigger mb_auth_user_created after insert on auth.users for each row execute procedure public.mb_new_user();

create or replace function public.mb_perform_transaction(p_type text,p_amount numeric,p_destination_account text default null,p_description text default null)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_uid uuid:=auth.uid(); v_src public.mb_accounts%rowtype; v_dst public.mb_accounts%rowtype; v_ref text; v_src_tx uuid; v_dst_tx uuid; v_new_balance numeric(14,2); v_dest_balance numeric(14,2);
begin
 if v_uid is null then raise exception 'Please sign in first.'; end if;
 if p_type not in ('deposit','withdrawal','transfer') then raise exception 'Invalid transaction type.'; end if;
 if p_amount is null or p_amount<=0 or p_amount>1000000 then raise exception 'Enter an amount greater than zero and not above KSh 1,000,000.'; end if;
 if exists(select 1 from public.mb_profiles where id=v_uid and status<>'active') then raise exception 'Your account is suspended.'; end if;
 select * into v_src from public.mb_accounts where user_id=v_uid for update;
 if not found then raise exception 'Your account was not found.'; end if;
 v_ref := 'MB-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 if p_type='deposit' then
   update public.mb_accounts set balance=balance+p_amount where id=v_src.id returning balance into v_new_balance;
   insert into public.mb_transactions(reference,account_id,user_id,type,direction,amount,balance_after,description) values(v_ref,v_src.id,v_uid,p_type,'credit',p_amount,v_new_balance,coalesce(p_description,'Simulated deposit')) returning id into v_src_tx;
   insert into public.mb_notifications(user_id,transaction_id,message) values(v_uid,v_src_tx,'Deposit of KSh '||p_amount||' completed. New balance: KSh '||v_new_balance||'.');
 elsif p_type='withdrawal' then
   if v_src.balance<p_amount then raise exception 'Insufficient balance.'; end if;
   update public.mb_accounts set balance=balance-p_amount where id=v_src.id returning balance into v_new_balance;
   insert into public.mb_transactions(reference,account_id,user_id,type,direction,amount,balance_after,description) values(v_ref,v_src.id,v_uid,p_type,'debit',p_amount,v_new_balance,coalesce(p_description,'Simulated withdrawal')) returning id into v_src_tx;
   insert into public.mb_notifications(user_id,transaction_id,message) values(v_uid,v_src_tx,'Withdrawal of KSh '||p_amount||' completed. New balance: KSh '||v_new_balance||'.');
 else
   if p_destination_account is null or length(trim(p_destination_account))=0 then raise exception 'Enter the recipient account number.'; end if;
   if p_destination_account=v_src.account_number then raise exception 'You cannot transfer to your own account.'; end if;
   select * into v_dst from public.mb_accounts where account_number=trim(p_destination_account) for update;
   if not found then raise exception 'Recipient account was not found.'; end if;
   if v_src.balance<p_amount then raise exception 'Insufficient balance.'; end if;
   update public.mb_accounts set balance=balance-p_amount where id=v_src.id returning balance into v_new_balance;
   update public.mb_accounts set balance=balance+p_amount where id=v_dst.id returning balance into v_dest_balance;
   insert into public.mb_transactions(reference,account_id,user_id,type,direction,amount,balance_after,counterparty_account,description) values(v_ref,v_src.id,v_uid,'transfer','debit',p_amount,v_new_balance,v_dst.account_number,coalesce(p_description,'Transfer sent')) returning id into v_src_tx;
   insert into public.mb_transactions(reference,account_id,user_id,type,direction,amount,balance_after,counterparty_account,description) values(v_ref||'-R',v_dst.id,v_dst.user_id,'transfer','credit',p_amount,v_dest_balance,v_src.account_number,'Transfer received') returning id into v_dst_tx;
   insert into public.mb_notifications(user_id,transaction_id,message) values(v_uid,v_src_tx,'Transfer of KSh '||p_amount||' to '||v_dst.account_number||' completed. New balance: KSh '||v_new_balance||'.'),(v_dst.user_id,v_dst_tx,'You received KSh '||p_amount||' from account '||v_src.account_number||'.');
 end if;
 insert into public.mb_audit_logs(user_id,action,details) values(v_uid,'Transaction '||p_type,'Reference '||v_ref||'; amount KSh '||p_amount);
 return jsonb_build_object('reference',v_ref,'balance_after',v_new_balance,'type',p_type,'amount',p_amount);
end; $$;
revoke all on function public.mb_perform_transaction(text,numeric,text,text) from public;
grant execute on function public.mb_perform_transaction(text,numeric,text,text) to authenticated;
grant execute on function public.mb_is_admin() to authenticated;

alter table public.mb_profiles enable row level security;
alter table public.mb_accounts enable row level security;
alter table public.mb_transactions enable row level security;
alter table public.mb_notifications enable row level security;
alter table public.mb_complaints enable row level security;
alter table public.mb_audit_logs enable row level security;

drop policy if exists mb_profiles_read on public.mb_profiles;
create policy mb_profiles_read on public.mb_profiles for select to authenticated using (id=auth.uid() or public.mb_is_admin());
drop policy if exists mb_profiles_admin_update on public.mb_profiles;
create policy mb_profiles_admin_update on public.mb_profiles for update to authenticated using(public.mb_is_admin()) with check(public.mb_is_admin());
drop policy if exists mb_accounts_read on public.mb_accounts;
create policy mb_accounts_read on public.mb_accounts for select to authenticated using(user_id=auth.uid() or public.mb_is_admin());
drop policy if exists mb_transactions_read on public.mb_transactions;
create policy mb_transactions_read on public.mb_transactions for select to authenticated using(user_id=auth.uid() or public.mb_is_admin());
drop policy if exists mb_notifications_read on public.mb_notifications;
create policy mb_notifications_read on public.mb_notifications for select to authenticated using(user_id=auth.uid() or public.mb_is_admin());
drop policy if exists mb_complaints_read on public.mb_complaints;
create policy mb_complaints_read on public.mb_complaints for select to authenticated using(user_id=auth.uid() or public.mb_is_admin());
drop policy if exists mb_complaints_insert on public.mb_complaints;
create policy mb_complaints_insert on public.mb_complaints for insert to authenticated with check(user_id=auth.uid());
drop policy if exists mb_complaints_admin_update on public.mb_complaints;
create policy mb_complaints_admin_update on public.mb_complaints for update to authenticated using(public.mb_is_admin()) with check(public.mb_is_admin());
drop policy if exists mb_audit_admin_read on public.mb_audit_logs;
create policy mb_audit_admin_read on public.mb_audit_logs for select to authenticated using(public.mb_is_admin());

-- IMPORTANT: do not expose service_role keys in frontend files.
-- Create the admin user through Supabase Authentication first, then run the
-- one-time role assignment statement in SETUP_GUIDE.md using that user's email.

-- Explicit grants are still governed by the RLS policies above.
grant usage on schema public to authenticated;
grant select on public.mb_profiles, public.mb_accounts, public.mb_transactions, public.mb_notifications, public.mb_complaints, public.mb_audit_logs to authenticated;
grant insert on public.mb_complaints to authenticated;
grant update on public.mb_profiles, public.mb_complaints to authenticated;
