-- Etapa 3 do entregador: bônus (a loja paga a mais quando ninguém aceita), rastreio ao vivo e avaliação.
alter table delivery_job add column bonus numeric(10, 2) not null default 0;
alter table delivery_job add column courier_lat double precision;
alter table delivery_job add column courier_lng double precision;
alter table delivery_job add column courier_at timestamp;

alter table courier add column rating_sum integer not null default 0;
alter table courier add column rating_count integer not null default 0;

-- Avaliação do entregador pelo cliente (uma por pedido).
create table courier_rating (
    id          bigserial primary key,
    order_id    bigint      not null unique,
    courier_id  bigint      not null references courier (user_id) on delete cascade,
    store_id    bigint      not null,
    customer_id bigint      not null,
    stars       integer     not null check (stars between 1 and 5),
    comment     varchar(300),
    created_at  timestamp   not null default now()
);
create index idx_courier_rating_courier on courier_rating (courier_id, created_at desc);
