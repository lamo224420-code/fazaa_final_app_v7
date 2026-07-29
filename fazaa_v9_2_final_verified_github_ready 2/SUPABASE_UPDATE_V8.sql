-- فزعة V8: إدارة الخيارات + تاريخ ووقت الطلب المرن
-- شغّلي هذا الملف مرة واحدة فقط في Supabase > SQL Editor

-- 1) تاريخ الطلب الفعلي، مستقل عن وقت إدخاله للنظام
alter table public.orders add column if not exists order_at timestamptz;
update public.orders set order_at = created_at where order_at is null;
alter table public.orders alter column order_at set default now();
alter table public.orders alter column order_at set not null;
create index if not exists orders_order_at_idx on public.orders(order_at desc);

-- 2) جدول طرق الدفع القابلة للتفعيل والتعطيل
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

insert into public.payment_methods(name,active,sort_order)
values
 ('إمكان',true,10),('تابي',true,20),('تمارا',true,30),
 ('نيو',true,40),('تكامل نون',true,50),('مدفوع',true,60)
on conflict (name) do nothing;

-- السماح بإضافة طرق دفع جديدة من لوحة الإدارة
alter table public.orders drop constraint if exists orders_payment_method_check;

-- 3) التحقق من صلاحية المدير
create or replace function public.fazaa_is_admin()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles
    where id=auth.uid() and role='admin' and active=true
  );
$$;

grant execute on function public.fazaa_is_admin() to authenticated;

-- 4) صلاحيات جدول طرق الدفع
alter table public.payment_methods enable row level security;
drop policy if exists "payment_methods_read" on public.payment_methods;
drop policy if exists "payment_methods_admin_manage" on public.payment_methods;
create policy "payment_methods_read" on public.payment_methods
for select to authenticated
using (active=true or public.fazaa_is_admin());
create policy "payment_methods_admin_manage" on public.payment_methods
for all to authenticated
using (public.fazaa_is_admin())
with check (public.fazaa_is_admin());

grant select,insert,update on public.payment_methods to authenticated;

-- 5) حذف آمن/استعادة: يخفي العنصر من الطلبات الجديدة ويحفظ التاريخ
create or replace function public.admin_set_active(
  p_entity text,
  p_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.fazaa_is_admin() then
    raise exception 'غير مصرح لك بهذه العملية';
  end if;

  case p_entity
    when 'employee' then
      update public.profiles set active=p_active
      where id=p_id and role='employee';
    when 'store' then
      update public.stores set active=p_active where id=p_id;
    when 'offer' then
      update public.offers set active=p_active where id=p_id;
    when 'package' then
      update public.packages set active=p_active where id=p_id;
    when 'payment_method' then
      update public.payment_methods set active=p_active where id=p_id;
    else
      raise exception 'نوع غير صالح';
  end case;
end;
$$;

grant execute on function public.admin_set_active(text,uuid,boolean) to authenticated;

select 'FAZAA V8 READY' as result;
