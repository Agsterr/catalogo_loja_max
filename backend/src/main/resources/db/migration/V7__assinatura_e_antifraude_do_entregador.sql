-- Frete pago direto ao entregador (a plataforma não passa dinheiro): valor cheio e quem paga.
alter table orders add column courier_freight numeric(10, 2);
alter table delivery_job add column freight_payer varchar(10) not null default 'CUSTOMER';

-- Antifraude do entregador: CPF único (guardado cifrado + impressão digital para comparar) e entregas grátis por CPF/aparelho.
alter table courier add column cpf_hash varchar(64);
alter table courier add column cpf_enc varchar(300);
alter table courier add column free_used integer not null default 0;
create unique index uq_courier_cpf on courier (cpf_hash) where cpf_hash is not null;

-- Aparelho (impressão digital do ID do aparelho): as entregas grátis valem por aparelho, mesmo com e-mail/CPF novos.
create table courier_device (
    device_hash    varchar(64) primary key,
    free_used      integer   not null default 0,
    first_seen_at  timestamp not null default now(),
    last_seen_at   timestamp not null default now()
);
create table courier_device_link (
    courier_id     bigint      not null references courier (user_id) on delete cascade,
    device_hash    varchar(64) not null references courier_device (device_hash),
    first_seen_at  timestamp   not null default now(),
    primary key (courier_id, device_hash)
);
create index idx_device_link_device on courier_device_link (device_hash);

-- Assinatura mensal do entregador (depois das entregas grátis) e os pagamentos que a estendem.
create table courier_subscription (
    courier_id  bigint primary key references courier (user_id) on delete cascade,
    paid_until  timestamp not null
);
create table courier_payment (
    id            bigserial primary key,
    courier_id    bigint         not null references courier (user_id) on delete cascade,
    amount        numeric(10, 2) not null,
    reference     varchar(40)    not null unique,
    status        varchar(20)    not null default 'PENDING',
    method        varchar(20)    not null default 'PIX_MANUAL',
    period_days   integer        not null default 30,
    created_at    timestamp      not null default now(),
    confirmed_at  timestamp,
    confirmed_by  bigint
);
create index idx_courier_payment_status on courier_payment (status, created_at);
