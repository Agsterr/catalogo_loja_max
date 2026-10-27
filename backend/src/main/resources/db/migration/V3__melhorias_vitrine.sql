-- Busca sem acento ("calca" acha "Calça", "tenis" acha "Tênis")
create extension if not exists unaccent;

-- Loja com cara de loja: logo, capa, descrição e horário de funcionamento (JSON com os 7 dias)
alter table store add column description varchar(500);
alter table store add column logo_url varchar(500);
alter table store add column logo_key varchar(200);
alter table store add column cover_url varchar(500);
alter table store add column cover_key varchar(200);
alter table store add column opening_hours text;

-- Tabela de medidas do produto (roupas e calçados) e foto ligada a uma cor
alter table product add column size_chart text;
alter table product_photo add column color varchar(40);

-- Endereços salvos do cliente (valem em todas as lojas)
create table customer_address (
    id          bigserial primary key,
    user_id     bigint       not null references app_user (id) on delete cascade,
    label       varchar(40)  not null,
    address     varchar(400) not null,
    created_at  timestamp    not null default now()
);
create index idx_address_user on customer_address (user_id);
