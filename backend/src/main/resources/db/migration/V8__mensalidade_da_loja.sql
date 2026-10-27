-- Mensalidade da loja: teste grátis e acesso até uma data (o app do cliente é grátis; quem paga é a loja).
alter table store add column access_until timestamp;
-- lojas que já existem ganham o teste grátis a partir de hoje; as novas, a partir do cadastro (feito no código)
update store set access_until = now() + interval '30 days';
alter table store alter column access_until set not null;

create table store_payment (
    id            bigserial primary key,
    store_id      bigint         not null references store (id) on delete cascade,
    amount        numeric(10, 2) not null,
    reference     varchar(40)    not null unique,
    status        varchar(20)    not null default 'PENDING',
    method        varchar(20)    not null default 'PIX_MANUAL',
    period_days   integer        not null default 30,
    created_at    timestamp      not null default now(),
    confirmed_at  timestamp,
    confirmed_by  bigint
);
create index idx_store_payment_status on store_payment (status, created_at);
create index idx_store_payment_store on store_payment (store_id);
create index idx_store_access on store (access_until);
