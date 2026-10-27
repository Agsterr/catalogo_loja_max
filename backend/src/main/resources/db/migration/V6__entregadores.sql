-- Entregadores (etapa 1): cadastro, corridas e entrega por entregador da plataforma.
alter table store add column courier_delivery boolean not null default false;

alter table orders add column courier_delivery boolean not null default false;
alter table orders add column delivery_lat double precision;
alter table orders add column delivery_lng double precision;
alter table orders add column delivery_distance_km numeric(6, 1);

create table courier (
    user_id          bigint primary key references app_user (id) on delete cascade,
    phone            varchar(30)      not null,
    vehicle          varchar(20)      not null,
    plate            varchar(12),
    city             varchar(80)      not null,
    state            varchar(2)       not null,
    base_lat         double precision,
    base_lng         double precision,
    radius_km        integer          not null default 10,
    status           varchar(20)      not null default 'PENDING',
    status_reason    varchar(300),
    online           boolean          not null default false,
    last_lat         double precision,
    last_lng         double precision,
    last_seen_at     timestamp,
    delivered_count  integer          not null default 0,
    canceled_count   integer          not null default 0,
    created_at       timestamp        not null default now(),
    approved_at      timestamp
);
create index idx_courier_region on courier (status, online, city);

-- Corrida: foto do que o entregador precisa saber; não é por loja (o entregador atende várias).
create table delivery_job (
    id              bigserial primary key,
    order_id        bigint           not null unique,
    order_code      varchar(10)      not null,
    tenant_id       bigint           not null references store (id) on delete cascade,
    status          varchar(20)      not null,
    store_name      varchar(120)     not null,
    pickup_address  varchar(300),
    pickup_lat      double precision not null,
    pickup_lng      double precision not null,
    city            varchar(80),
    dropoff_address varchar(400)     not null,
    dropoff_lat     double precision not null,
    dropoff_lng     double precision not null,
    customer_name   varchar(120)     not null,
    customer_phone  varchar(30),
    item_count      integer          not null,
    distance_km     numeric(6, 1)    not null,
    customer_fee    numeric(10, 2)   not null,
    courier_fee     numeric(10, 2)   not null,
    pickup_code     varchar(6)       not null,
    delivery_code   varchar(6)       not null,
    courier_id      bigint references courier (user_id),
    offers          integer          not null default 1,
    created_at      timestamp        not null default now(),
    expires_at      timestamp        not null,
    accepted_at     timestamp,
    picked_up_at    timestamp,
    delivered_at    timestamp,
    canceled_at     timestamp,
    cancel_reason   varchar(300)
);
create index idx_job_open on delivery_job (pickup_lat, pickup_lng) where status = 'OPEN';
create index idx_job_expiring on delivery_job (expires_at) where status = 'OPEN';
create index idx_job_courier on delivery_job (courier_id, status);
create index idx_job_tenant on delivery_job (tenant_id);

-- Distância em linha reta (km) entre dois pontos; usada pelo mural e pelo despacho.
create function geo_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
    returns double precision language sql immutable parallel safe as
$$ select 6371 * acos(least(1.0, greatest(-1.0, cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lng2) - radians(lng1))
                                                + sin(radians(lat1)) * sin(radians(lat2))))) $$;
