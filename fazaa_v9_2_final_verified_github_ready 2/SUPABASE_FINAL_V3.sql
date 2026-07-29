-- فزعة: التحديث النهائي V3
-- شغّل هذا الملف مرة واحدة داخل Supabase SQL Editor.

-- المتاجر والنسب
insert into public.stores (name, fee_type, fee_value, active)
select x.name,'percent',x.fee,true
from (values
 ('نون',15::numeric),
 ('بتول',15::numeric),
 ('تكامل نون',15::numeric),
 ('أمازون',8::numeric),
 ('شي إن',8::numeric),
 ('سيفي',8::numeric),
 ('أخرى',8::numeric)
) x(name,fee)
where not exists (select 1 from public.stores s where s.name=x.name);

update public.stores
set fee_type='percent',fee_value=15,active=true
where name in ('نون','بتول','تكامل نون');

update public.stores
set fee_type='percent',fee_value=8,active=true
where name not in ('نون','بتول','تكامل نون');

-- طرق الدفع
alter table public.orders
add column if not exists payment_method text;

update public.orders
set payment_method='إمكان'
where payment_method is null;

alter table public.orders
alter column payment_method set default 'إمكان';

alter table public.orders
alter column payment_method set not null;

alter table public.orders
drop constraint if exists orders_payment_method_check;

alter table public.orders
add constraint orders_payment_method_check
check (payment_method in ('إمكان','تابي','تمارا','نيو','تكامل نون','مدفوع'));

-- العروض
insert into public.offers (name,active)
select x.name,true
from (values ('طلب جديد'),('عرض الطفرة'),('عرض يومي'),('عرض مسابقة')) x(name)
where not exists (select 1 from public.offers o where o.name=x.name);

-- الباقات
insert into public.packages (package_value,installments_total,active)
select x.package_value,x.installments_total,true
from (values
 (2000::numeric,3199::numeric),(1800,2800),(1700,2550),(1200,2000),
 (1000,1632),(900,1500),(800,1350),(700,1150),(600,1000),
 (500,845),(400,684),(300,555),(225,425)
) x(package_value,installments_total)
where not exists (
 select 1 from public.packages p
 where p.package_value=x.package_value and p.installments_total=x.installments_total
);

-- حسبة الرسوم والأرباح
create or replace function public.calculate_order_financials()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fee_type public.fee_type;
  v_fee_value numeric(12,2);
begin
  select fee_type, fee_value
  into v_fee_type, v_fee_value
  from public.stores
  where id = new.store_id and active = true;

  if not found then
    raise exception 'Store is not active or does not exist';
  end if;

  if new.has_first_payment = false then
    new.first_payment_amount := 0;
    new.supervisor := null;
  end if;

  new.transfer_amount := greatest(
    0,
    coalesce(new.package_value,0)
    - coalesce(new.first_payment_amount,0)
    + coalesce(new.cashback_amount,0)
  );

  if new.payment_method = 'مدفوع' then
    new.service_fee := 100;
  elsif v_fee_type = 'percent' then
    new.service_fee := round(new.order_amount * v_fee_value / 100,2);
  else
    new.service_fee := v_fee_value;
  end if;

  new.net_profit := round(
    new.order_amount
    - new.transfer_amount
    - new.first_payment_amount
    - new.cashback_amount
    - new.service_fee,
    2
  );

  return new;
end;
$$;

drop trigger if exists orders_calculate_financials on public.orders;
create trigger orders_calculate_financials
before insert or update of
  order_amount,package_value,has_first_payment,first_payment_amount,
  cashback_amount,store_id,payment_method
on public.orders
for each row execute function public.calculate_order_financials();

select 'FAZAA FINAL V3 READY' as result;
