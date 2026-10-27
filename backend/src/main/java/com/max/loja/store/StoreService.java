package com.max.loja.store;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.max.loja.delivery.DeliveryPricing;
import com.max.loja.security.AuditService;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.Search;
import com.max.loja.shared.TenantContext;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StoreService {

    public record StoreRequest(@NotBlank @Size(max = 120) String name, @Size(max = 500) String description,
                               @Size(max = 30) String whatsapp,
                               @Size(max = 80) String instagram, @Size(max = 300) String pickupAddress,
                               boolean pickupEnabled, boolean deliveryEnabled,
                               @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal deliveryFee,
                               @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal freeDeliveryFrom,
                               @Size(min = 7, max = 7) @Valid List<StoreHours.Day> openingHours,
                               @Size(max = 80) String city, @Pattern(regexp = "^$|^[A-Za-z]{2}$") String state,
                               @DecimalMin("-90") @DecimalMax("90") Double latitude,
                               @DecimalMin("-180") @DecimalMax("180") Double longitude,
                               @Valid List<DeliveryZones.Zone> deliveryZones, boolean courierDelivery) {
    }

    /** {@code status}: aberta/fechada agora (nulo sem horário informado); {@code hours}: linhas para mostrar. */
    public record StoreResponse(Long id, String slug, String name, String description, String whatsapp, String instagram,
                                String pickupAddress, boolean pickupEnabled, boolean deliveryEnabled, BigDecimal deliveryFee,
                                BigDecimal freeDeliveryFrom, String logoUrl, String coverUrl,
                                List<StoreHours.Day> openingHours, List<String> hours, StoreHours.Status status,
                                String city, String state, Double latitude, Double longitude,
                                List<DeliveryZones.Zone> deliveryZones, boolean courierDelivery) {
    }

    /** Cartão da busca de lojas no app do cliente; {@code distanceKm} só vem quando a busca mandou a posição. */
    public record StoreCard(Long id, String slug, String name, String instagram, String description, String logoUrl,
                            StoreHours.Status status, String city, String state, Double distanceKm) {
    }

    /**
     * Quanto custa a entrega para quem está em ({@code lat}, {@code lng}): {@code needsLocation} quando a loja cobra por
     * distância e o app ainda não mandou a posição; {@code available=false} fora da área de entrega.
     */
    public record DeliveryQuote(boolean available, boolean needsLocation, Double distanceKm, BigDecimal fee, String message,
                                BigDecimal freight, String freightPayer) {

        public DeliveryQuote(boolean available, boolean needsLocation, Double distanceKm, BigDecimal fee, String message) {
            this(available, needsLocation, distanceKm, fee, message, null, null);
        }
    }

    public record CityCount(String city, String state, long total) {
    }

    private final StoreRepository stores;
    private final AuditService audit;
    private final ObjectMapper json;
    private final Clock clock;
    private final DeliveryPricing courierPricing;
    private final StoreBilling billing;

    public StoreService(StoreRepository stores, AuditService audit, ObjectMapper json, Clock clock,
                        DeliveryPricing courierPricing, StoreBilling billing) {
        this.courierPricing = courierPricing;
        this.billing = billing;
        this.stores = stores;
        this.audit = audit;
        this.json = json;
        this.clock = clock;
    }

    public StoreResponse response(Store s) {
        List<StoreHours.Day> days = StoreHours.parse(s.getOpeningHours(), json);
        return new StoreResponse(s.getId(), s.getSlug(), s.getName(), s.getDescription(), s.getWhatsapp(), s.getInstagram(),
                s.getPickupAddress(), s.isPickupEnabled(), s.isDeliveryEnabled(), s.getDeliveryFee(), s.getFreeDeliveryFrom(),
                s.getLogoUrl(), s.getCoverUrl(), days, StoreHours.lines(days),
                StoreHours.status(days, LocalDateTime.now(clock)), s.getCity(), s.getState(), s.getLatitude(), s.getLongitude(),
                DeliveryZones.parse(s.getDeliveryZones(), json), s.isCourierDelivery());
    }

    private StoreCard card(Store s, Double lat, Double lng) {
        Double km = lat == null || lng == null || s.getLatitude() == null || s.getLongitude() == null ? null
                : Math.round(distanceKm(lat, lng, s.getLatitude(), s.getLongitude()) * 10) / 10.0;
        return new StoreCard(s.getId(), s.getSlug(), s.getName(), s.getInstagram(), s.getDescription(), s.getLogoUrl(),
                StoreHours.status(StoreHours.parse(s.getOpeningHours(), json), LocalDateTime.now(clock)), s.getCity(),
                s.getState(), km);
    }

    public DeliveryQuote deliveryQuote(Store s, Double lat, Double lng, BigDecimal subtotal) {
        if (s.isCourierDelivery() && s.getLatitude() != null && s.getLongitude() != null) {
            return courierQuote(s, lat, lng, subtotal);
        }
        boolean free = s.getFreeDeliveryFrom() != null && subtotal.compareTo(s.getFreeDeliveryFrom()) >= 0;
        List<DeliveryZones.Zone> zones = DeliveryZones.parse(s.getDeliveryZones(), json);
        if (zones.isEmpty() || s.getLatitude() == null || s.getLongitude() == null) {
            return new DeliveryQuote(true, false, null, free ? BigDecimal.ZERO : s.getDeliveryFee(), null);
        }
        if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            return new DeliveryQuote(false, true, null, null, "Use sua localização para calcular a entrega.");
        }
        double km = Math.round(distanceKm(lat, lng, s.getLatitude(), s.getLongitude()) * 10) / 10.0;
        return zones.stream().filter(z -> km <= z.upToKm()).findFirst()
                .map(z -> new DeliveryQuote(true, false, km, free ? BigDecimal.ZERO : z.fee(), null))
                .orElseGet(() -> new DeliveryQuote(false, false, km, null, "Você está a " + km + " km: fora da área de entrega"
                        + " (até " + zones.get(zones.size() - 1).upToKm() + " km)."));
    }

    /** Entregador da plataforma: frete pela distância (fórmula da plataforma), sem faixas da loja. */
    private DeliveryQuote courierQuote(Store s, Double lat, Double lng, BigDecimal subtotal) {
        if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            return new DeliveryQuote(false, true, null, null, "Use sua localização para calcular a entrega.");
        }
        double km = Math.round(distanceKm(lat, lng, s.getLatitude(), s.getLongitude()) * 10) / 10.0;
        if (!courierPricing.covers(km)) {
            return new DeliveryQuote(false, false, km, null, "Você está a " + km + " km: fora da área de entrega (até "
                    + courierPricing.maxKm() + " km).");
        }
        // frete = o que o entregador recebe, direto de quem paga (a plataforma não passa dinheiro): o cliente, ou a loja
        // quando o pedido passa do valor de frete grátis
        BigDecimal freight = courierPricing.customerFee(km);
        boolean storePays = s.getFreeDeliveryFrom() != null && subtotal.compareTo(s.getFreeDeliveryFrom()) >= 0;
        return new DeliveryQuote(true, false, km, storePays ? BigDecimal.ZERO : freight, null, freight,
                storePays ? "STORE" : "CUSTOMER");
    }

    /** Distância em linha reta (haversine), em km. */
    static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.pow(Math.sin(dLat / 2), 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLng / 2), 2);
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    /** Loja da requisição (JWT da equipe ou slug da URL). */
    @Transactional(readOnly = true)
    public Store current() {
        return stores.findById(TenantContext.get()).orElseThrow(() -> new NotFoundException("Loja não encontrada"));
    }

    /** Lojas por nome, cidade/UF e/ou perto da posição do cliente (a posição só vale nesta consulta, nada é guardado). */
    @Transactional(readOnly = true)
    public PageResponse<StoreCard> search(String q, String city, String state, Double lat, Double lng, Double radiusKm,
                                          Integer page, Integer size) {
        if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
            lat = null;
            lng = null;
        }
        Double la = lat;
        Double ln = lng;
        Double radius = la == null || radiusKm == null || radiusKm <= 0 ? null : Math.min(radiusKm, 500);
        String uf = state == null ? "" : state.trim().toUpperCase();
        return PageResponse.of(stores.search(Search.like(q == null ? "" : q), Search.like(city == null ? "" : city),
                uf.length() == 2 ? uf : "", la, ln, radius, false, billing.visibleCutoff(), PageResponse.request(page, size, Sort.unsorted())),
                s -> card(s, la, ln));
    }

    @Transactional(readOnly = true)
    public List<CityCount> cities() {
        return stores.cities(billing.visibleCutoff()).stream().map(c -> new CityCount(c.getCity(), c.getState(), c.getTotal())).toList();
    }

    @Transactional
    public StoreResponse update(StoreRequest req, Long actorId) {
        if (!req.pickupEnabled() && !req.deliveryEnabled()) {
            throw new BusinessException("Deixe pelo menos retirada ou entrega ligada");
        }
        Store s = current();
        s.setName(req.name().trim());
        s.setDescription(blank(req.description()));
        String zones = DeliveryZones.write(req.deliveryZones(), json);
        if (zones != null && (req.latitude() == null || req.longitude() == null)) {
            throw new BusinessException("Marque a localização da loja para cobrar entrega por distância");
        }
        s.setDeliveryZones(zones);
        if (req.courierDelivery() && (req.latitude() == null || req.longitude() == null)) {
            throw new BusinessException("Marque a localização da loja para usar entregador da plataforma");
        }
        s.setCourierDelivery(req.courierDelivery());
        s.setCity(blank(req.city()));
        s.setState(blank(req.state()) == null ? null : req.state().trim().toUpperCase());
        boolean hasPoint = req.latitude() != null && req.longitude() != null;
        s.setLatitude(hasPoint ? req.latitude() : null);
        s.setLongitude(hasPoint ? req.longitude() : null);
        s.setOpeningHours(StoreHours.write(req.openingHours(), json));
        s.setWhatsapp(blank(req.whatsapp()));
        s.setInstagram(blank(req.instagram()));
        s.setPickupAddress(blank(req.pickupAddress()));
        s.setPickupEnabled(req.pickupEnabled());
        s.setDeliveryEnabled(req.deliveryEnabled());
        s.setDeliveryFee(req.deliveryFee());
        s.setFreeDeliveryFrom(req.freeDeliveryFrom());
        audit.record(AuditService.STORE_SETTINGS, actorId, null);
        return response(s);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
