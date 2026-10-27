-- Faixas de entrega por distância em JSON ([{"upToKm":3,"fee":8.00},...]); nulo = taxa fixa da loja.
alter table store add column delivery_zones text;
