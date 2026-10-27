-- Onde a loja fica: cidade/UF para filtrar e latitude/longitude para ordenar por distância ("lojas perto de mim").
alter table store add column city varchar(80);
alter table store add column state varchar(2);
alter table store add column latitude double precision;
alter table store add column longitude double precision;
create index idx_store_city on store (lower(city));
