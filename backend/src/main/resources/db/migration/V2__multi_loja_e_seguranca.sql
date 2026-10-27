-- Plataforma com várias lojas (multi-tenant por coluna tenant_id, como no Gerenciamento Max),
-- auditoria de segurança, limite de tentativas no banco e verificação em duas etapas.

-- Lojas (o tenant). A loja que já existia vira a loja 1 ("loja-max").
create table store (
    id                  bigserial primary key,
    slug                varchar(60)    not null unique,
    name                varchar(120)   not null,
    whatsapp            varchar(30),
    instagram           varchar(80),
    pickup_address      varchar(300),
    pickup_enabled      boolean        not null default true,
    delivery_enabled    boolean        not null default true,
    delivery_fee        numeric(10, 2) not null default 0,
    free_delivery_from  numeric(10, 2),
    -- Bloqueada pelo administrador da plataforma: some da vitrine e a equipe não entra
    blocked             boolean        not null default false,
    blocked_reason      varchar(300),
    blocked_at          timestamp,
    created_at          timestamp      not null default now()
);
insert into store (id, slug, name, whatsapp, instagram, pickup_address, pickup_enabled, delivery_enabled, delivery_fee,
                   free_delivery_from)
select 1, 'loja-max', name, whatsapp, instagram, pickup_address, pickup_enabled, delivery_enabled, delivery_fee,
       free_delivery_from
from store_settings;
select setval(pg_get_serial_sequence('store', 'id'), greatest((select max(id) from store), 1));
drop table store_settings;

-- Equipe pertence a uma loja; cliente (conta única para todas as lojas) e admin da plataforma não.
alter table app_user add column store_id bigint references store (id);
update app_user set store_id = 1 where role in ('OWNER', 'STAFF');
alter table app_user add constraint chk_team_has_store check ((role in ('OWNER', 'STAFF')) = (store_id is not null));
create index idx_user_store on app_user (store_id);

-- Verificação em duas etapas (TOTP, app autenticador). O segredo fica cifrado (AES-GCM).
alter table app_user add column totp_secret varchar(200);
alter table app_user add column totp_enabled boolean not null default false;

-- tenant_id em tudo que é da loja (preenchido e filtrado pelo Hibernate: @TenantId)
alter table category add column tenant_id bigint not null default 1 references store (id);
alter table product add column tenant_id bigint not null default 1 references store (id);
alter table product_variant add column tenant_id bigint not null default 1 references store (id);
alter table product_photo add column tenant_id bigint not null default 1 references store (id);
alter table orders add column tenant_id bigint not null default 1 references store (id);
alter table order_item add column tenant_id bigint not null default 1 references store (id);
alter table order_event add column tenant_id bigint not null default 1 references store (id);
alter table stock_movement add column tenant_id bigint not null default 1 references store (id);
alter table promotion add column tenant_id bigint not null default 1 references store (id);
alter table category alter column tenant_id drop default;
alter table product alter column tenant_id drop default;
alter table product_variant alter column tenant_id drop default;
alter table product_photo alter column tenant_id drop default;
alter table orders alter column tenant_id drop default;
alter table order_item alter column tenant_id drop default;
alter table order_event alter column tenant_id drop default;
alter table stock_movement alter column tenant_id drop default;
alter table promotion alter column tenant_id drop default;

create index idx_category_tenant on category (tenant_id);
create index idx_product_tenant on product (tenant_id, created_at desc);
create index idx_variant_tenant on product_variant (tenant_id);
create index idx_photo_tenant on product_photo (tenant_id);
create index idx_orders_tenant on orders (tenant_id, created_at desc);
create index idx_orders_tenant_status on orders (tenant_id, status, created_at desc);
create index idx_item_tenant on order_item (tenant_id);
create index idx_event_tenant on order_event (tenant_id);
create index idx_movement_tenant on stock_movement (tenant_id);
create index idx_promotion_tenant on promotion (tenant_id, starts_at, ends_at);

-- nomes de categoria e códigos (SKU) são únicos dentro de cada loja
alter table category drop constraint category_department_name_key;
alter table category add constraint uq_category_name unique (tenant_id, department, name);
alter table product_variant drop constraint product_variant_sku_key;
alter table product_variant add constraint uq_variant_sku unique (tenant_id, sku);

-- Sino: aviso de uma loja; user_id nulo = equipe daquela loja, preenchido = aquele usuário (o cliente vê os de todas)
alter table notification add column store_id bigint references store (id) on delete cascade;
update notification set store_id = 1;
alter table notification alter column store_id set not null;
create index idx_notification_store on notification (store_id, created_at desc);

-- Lojas que cada celular acompanha (promoções); equipe e avisos de pedido vêm do usuário
create table push_device_store (
    device_id   bigint    not null references push_device (id) on delete cascade,
    tenant_id   bigint    not null references store (id) on delete cascade,
    created_at  timestamp not null default now(),
    primary key (device_id, tenant_id)
);
create index idx_device_store_tenant on push_device_store (tenant_id);
insert into push_device_store (device_id, tenant_id) select id, 1 from push_device where app = 'CLIENT';
alter table push_outbox add column tenant_id bigint;

-- Cliente bloqueado por uma loja (não compra nela); bloqueio geral só pelo admin da plataforma
create table store_customer_block (
    tenant_id   bigint       not null references store (id) on delete cascade,
    user_id     bigint       not null references app_user (id) on delete cascade,
    reason      varchar(300),
    created_at  timestamp    not null default now(),
    primary key (tenant_id, user_id)
);

-- Auditoria: entradas, falhas, trocas de senha, bloqueios, ações da equipe
create table security_event (
    id          bigserial primary key,
    tenant_id   bigint,
    user_id     bigint,
    type        varchar(40)  not null,
    detail      varchar(300),
    ip          varchar(64),
    created_at  timestamp    not null default now()
);
create index idx_security_user on security_event (user_id, id desc);
create index idx_security_tenant on security_event (tenant_id, id desc);

-- Limite de tentativas no banco: vale com várias instâncias da API
create table rate_limit_hit (
    id          bigserial primary key,
    key         varchar(200) not null,
    created_at  timestamp    not null default now()
);
create index idx_rate_limit on rate_limit_hit (key, created_at);
