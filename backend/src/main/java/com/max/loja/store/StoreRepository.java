package com.max.loja.store;

import java.util.Optional;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface StoreRepository extends JpaRepository<Store, Long> {

    Optional<Store> findBySlug(String slug);

    boolean existsBySlug(String slug);

    /**
     * Busca por nome (sem acento) ou endereço e, se pedido, por cidade/UF; {@code q} e {@code city} já vêm de
     * {@code Search.like}. Com {@code lat}/{@code lng} ordena pela distância (lojas sem coordenadas por último) e,
     * com {@code radiusKm}, só traz as que estão dentro do raio. Bloqueadas só para o admin.
     */
    @Query(value = """
            select * from store s where (:includeBlocked = true or (s.blocked = false and s.access_until > :cutoff))
            and (:q = '%%' or unaccent(lower(s.name)) like :q or s.slug like :q)
            and (:city = '%%' or unaccent(lower(s.city)) like :city)
            and (:state = '' or s.state = :state)
            and (cast(:radiusKm as double precision) is null or cast(:lat as double precision) is null
                 or (s.latitude is not null and 6371 * acos(least(1.0, greatest(-1.0,
                     cos(radians(cast(:lat as double precision))) * cos(radians(s.latitude))
                     * cos(radians(s.longitude) - radians(cast(:lng as double precision)))
                     + sin(radians(cast(:lat as double precision))) * sin(radians(s.latitude))))) <= cast(:radiusKm as double precision)))
            order by case when cast(:lat as double precision) is null or s.latitude is null then 1 else 0 end,
                case when cast(:lat as double precision) is null or s.latitude is null then 0 else
                  acos(least(1.0, greatest(-1.0, cos(radians(cast(:lat as double precision))) * cos(radians(s.latitude))
                     * cos(radians(s.longitude) - radians(cast(:lng as double precision)))
                     + sin(radians(cast(:lat as double precision))) * sin(radians(s.latitude))))) end,
                s.name""",
            countQuery = """
            select count(*) from store s where (:includeBlocked = true or (s.blocked = false and s.access_until > :cutoff))
            and (:q = '%%' or unaccent(lower(s.name)) like :q or s.slug like :q)
            and (:city = '%%' or unaccent(lower(s.city)) like :city)
            and (:state = '' or s.state = :state)
            and (cast(:radiusKm as double precision) is null or cast(:lat as double precision) is null
                 or (s.latitude is not null and 6371 * acos(least(1.0, greatest(-1.0,
                     cos(radians(cast(:lat as double precision))) * cos(radians(s.latitude))
                     * cos(radians(s.longitude) - radians(cast(:lng as double precision)))
                     + sin(radians(cast(:lat as double precision))) * sin(radians(s.latitude))))) <= cast(:radiusKm as double precision)))""",
            nativeQuery = true)
    Page<Store> search(@Param("q") String q, @Param("city") String city, @Param("state") String state,
                       @Param("lat") Double lat, @Param("lng") Double lng, @Param("radiusKm") Double radiusKm,
                       @Param("includeBlocked") boolean includeBlocked, @Param("cutoff") java.time.LocalDateTime cutoff,
                       Pageable page);

    /** Cidades com loja aberta ao público, com a quantidade de lojas (para o filtro do app). */
    @Query(value = """
            select s.city as city, s.state as state, count(*) as total from store s
            where s.blocked = false and s.access_until > :cutoff and s.city is not null and s.city <> ''
            group by s.city, s.state order by count(*) desc, s.city limit 100""", nativeQuery = true)
    java.util.List<CityCount> cities(@Param("cutoff") java.time.LocalDateTime cutoff);

    interface CityCount {
        String getCity();

        String getState();

        long getTotal();
    }
}
