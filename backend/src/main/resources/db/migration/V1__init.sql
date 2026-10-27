-- Loja Max: uma loja (roupas, calçados e bijuterias), equipe e clientes no mesmo cadastro de usuários.

create table app_user (
    id              bigserial primary key,
    name            varchar(120) not null,
    email           varchar(180) not null unique,
    phone           varchar(30),
    password_hash   varchar(100) not null,
    -- OWNER (dono), STAFF (funcionário), CUSTOMER (cliente do app)
    role            varchar(20)  not null,
    active          boolean      not null default true,
    blocked         boolean      not null default false,
    blocked_reason  varchar(300),
    blocked_at      timestamp,
    -- Aumenta na troca de senha, no "sair de todos os aparelhos" e no bloqueio: tokens antigos param de valer
    token_version   integer      not null default 0,
    failed_logins   integer      not null default 0,
    locked_until    timestamp,
    created_at      timestamp    not null default now()
);

create table password_reset (
    id          bigserial primary key,
    user_id     bigint      not null references app_user (id) on delete cascade,
    token_hash  varchar(64) not null unique,
    expires_at  timestamp   not null,
    used_at     timestamp,
    created_at  timestamp   not null default now()
);

-- Dados da loja (uma linha só)
create table store_settings (
    id                  bigint primary key default 1 check (id = 1),
    name                varchar(120)  not null default 'Loja Max',
    whatsapp            varchar(30),
    instagram           varchar(80),
    pickup_address      varchar(300),
    pickup_enabled      boolean       not null default true,
    delivery_enabled    boolean       not null default true,
    delivery_fee        numeric(10, 2) not null default 0,
    free_delivery_from  numeric(10, 2)
);
insert into store_settings (id) values (1);

create table category (
    id          bigserial primary key,
    -- ROUPAS, CALCADOS, BIJUTERIAS
    department  varchar(20)  not null,
    name        varchar(80)  not null,
    position    integer      not null default 0,
    active      boolean      not null default true,
    unique (department, name)
);

create table product (
    id           bigserial primary key,
    name         varchar(150)   not null,
    description  text,
    department   varchar(20)    not null,
    category_id  bigint references category (id),
    brand        varchar(80),
    price        numeric(10, 2) not null check (price > 0),
    -- preço "de/por" fixo do produto; promoções por período ficam em promotion
    sale_price   numeric(10, 2) check (sale_price > 0),
    min_stock    integer        not null default 1,
    active       boolean        not null default true,
    featured     boolean        not null default false,
    created_at   timestamp      not null default now(),
    updated_at   timestamp      not null default now()
);
create index idx_product_department on product (department) where active;
create index idx_product_category on product (category_id);

-- Tamanho/cor com estoque próprio (P/M/G, 36/37/38, tamanho único...)
create table product_variant (
    id          bigserial primary key,
    product_id  bigint      not null references product (id) on delete cascade,
    size        varchar(20) not null,
    color       varchar(40) not null default '',
    sku         varchar(60) unique,
    stock       integer     not null default 0 check (stock >= 0),
    active      boolean     not null default true,
    unique (product_id, size, color)
);

create table product_photo (
    id           bigserial primary key,
    product_id   bigint       not null references product (id) on delete cascade,
    storage_key  varchar(200) not null,
    url          varchar(500) not null,
    thumb_key    varchar(200) not null,
    thumb_url    varchar(500) not null,
    width        integer      not null,
    height       integer      not null,
    position     integer      not null default 0,
    created_at   timestamp    not null default now()
);
create index idx_photo_product on product_photo (product_id, position);

create table orders (
    id               bigserial primary key,
    code             varchar(12)    not null unique,
    customer_id      bigint         not null references app_user (id),
    -- PENDING, CONFIRMED, READY, SHIPPED, DELIVERED, CANCELED
    status           varchar(20)    not null,
    -- PICKUP (retirar na loja) ou DELIVERY (entrega)
    delivery_method  varchar(20)    not null,
    -- PIX, CARD, CASH (pago na entrega/retirada ou combinado pelo WhatsApp)
    payment_method   varchar(20)    not null,
    paid             boolean        not null default false,
    address          varchar(400),
    notes            varchar(500),
    subtotal         numeric(10, 2) not null,
    discount         numeric(10, 2) not null default 0,
    delivery_fee     numeric(10, 2) not null default 0,
    total            numeric(10, 2) not null,
    cancel_reason    varchar(300),
    created_at       timestamp      not null default now(),
    updated_at       timestamp      not null default now()
);
create index idx_orders_customer on orders (customer_id, created_at desc);
create index idx_orders_status on orders (status, created_at desc);

create table order_item (
    id            bigserial primary key,
    order_id      bigint         not null references orders (id) on delete cascade,
    product_id    bigint         not null references product (id),
    variant_id    bigint         not null references product_variant (id),
    product_name  varchar(150)   not null,
    size          varchar(20)    not null,
    color         varchar(40)    not null default '',
    unit_price    numeric(10, 2) not null,
    quantity      integer        not null check (quantity > 0),
    total         numeric(10, 2) not null
);
create index idx_item_order on order_item (order_id);

-- Linha do tempo do pedido (cada mudança de status, quem fez e quando)
create table order_event (
    id          bigserial primary key,
    order_id    bigint      not null references orders (id) on delete cascade,
    status      varchar(20) not null,
    note        varchar(300),
    user_id     bigint,
    created_at  timestamp   not null default now()
);
create index idx_order_event on order_event (order_id, id);

create table stock_movement (
    id          bigserial primary key,
    variant_id  bigint      not null references product_variant (id) on delete cascade,
    -- IN (entrada), SALE (venda), RETURN (pedido cancelado), ADJUST (acerto), LOSS (perda)
    type        varchar(20) not null,
    quantity    integer     not null,
    stock_after integer     not null,
    note        varchar(200),
    order_id    bigint,
    user_id     bigint,
    created_at  timestamp   not null default now()
);
create index idx_movement_variant on stock_movement (variant_id, created_at desc);

create table promotion (
    id                bigserial primary key,
    title             varchar(120) not null,
    description       varchar(500),
    discount_percent  integer      not null check (discount_percent between 1 and 90),
    -- Alcance: produto, ou categoria, ou departamento; tudo nulo = loja inteira
    department        varchar(20),
    category_id       bigint references category (id) on delete cascade,
    product_id        bigint references product (id) on delete cascade,
    starts_at         timestamp    not null,
    ends_at           timestamp    not null,
    active            boolean      not null default true,
    notify_customers  boolean      not null default true,
    notified_at       timestamp,
    created_at        timestamp    not null default now(),
    check (ends_at > starts_at)
);
create index idx_promotion_period on promotion (starts_at, ends_at) where active;

-- "Avise-me quando chegar": cliente quer saber quando o produto esgotado voltar
create table product_watch (
    user_id     bigint    not null references app_user (id) on delete cascade,
    product_id  bigint    not null references product (id) on delete cascade,
    created_at  timestamp not null default now(),
    primary key (user_id, product_id)
);
create index idx_watch_product on product_watch (product_id);

-- Sino do app: userId nulo = toda a equipe (dono e funcionários); preenchido = só aquele usuário (cliente ou equipe)
create table notification (
    id          bigserial primary key,
    type        varchar(30)  not null,
    title       varchar(200) not null,
    message     varchar(500) not null,
    order_id    bigint,
    product_id  bigint,
    user_id     bigint references app_user (id) on delete cascade,
    dedup_key   varchar(120) unique,
    created_at  timestamp    not null default now(),
    read_at     timestamp
);
create index idx_notification_user on notification (user_id, created_at desc);

-- Celulares que recebem push. user_id nulo = app do cliente sem login (só promoções).
create table push_device (
    id                   bigserial primary key,
    token                varchar(512) not null unique,
    user_id              bigint references app_user (id) on delete cascade,
    -- STAFF (equipe logada) ou CLIENT (cliente)
    app                  varchar(10)  not null,
    promo_notifications  boolean      not null default true,
    updated_at           timestamp    not null default now()
);
create index idx_push_device_user on push_device (user_id);

-- Fila de avisos (outbox): entra na mesma transação do fato; o worker entrega com tentativas e confirmação
create table push_outbox (
    id               bigserial primary key,
    public_id        varchar(64)  not null unique,
    device_id        bigint       not null,
    device_token     varchar(512) not null,
    title            varchar(200) not null,
    body             varchar(500) not null,
    data             text         not null default '{}',
    dedupe_key       varchar(200) not null unique,
    -- PENDING, SENT, RECEIVED, DEAD, INVALID, EXPIRED
    status           varchar(10)  not null default 'PENDING',
    attempts         integer      not null default 0,
    next_attempt_at  timestamp    not null default now(),
    last_error       varchar(300),
    created_at       timestamp    not null default now(),
    sent_at          timestamp,
    received_at      timestamp
);
create index idx_push_outbox_due on push_outbox (next_attempt_at) where status = 'PENDING';
