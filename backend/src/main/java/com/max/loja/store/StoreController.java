package com.max.loja.store;

import java.math.BigDecimal;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class StoreController {

    public record StoreRequest(@NotBlank @Size(max = 120) String name, @Size(max = 30) String whatsapp,
                               @Size(max = 80) String instagram, @Size(max = 300) String pickupAddress,
                               boolean pickupEnabled, boolean deliveryEnabled,
                               @NotNull @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal deliveryFee,
                               @DecimalMin("0") @Digits(integer = 8, fraction = 2) BigDecimal freeDeliveryFrom) {
    }

    public record StoreResponse(String name, String whatsapp, String instagram, String pickupAddress,
                                boolean pickupEnabled, boolean deliveryEnabled, BigDecimal deliveryFee,
                                BigDecimal freeDeliveryFrom) {

        static StoreResponse from(StoreSettings s) {
            return new StoreResponse(s.getName(), s.getWhatsapp(), s.getInstagram(), s.getPickupAddress(),
                    s.isPickupEnabled(), s.isDeliveryEnabled(), s.getDeliveryFee(), s.getFreeDeliveryFrom());
        }
    }

    private final StoreSettingsRepository settings;

    public StoreController(StoreSettingsRepository settings) {
        this.settings = settings;
    }

    @GetMapping("/api/public/store")
    @Transactional(readOnly = true)
    public StoreResponse store() {
        return StoreResponse.from(settings.current());
    }

    @PutMapping("/api/store/settings")
    @Transactional
    public StoreResponse update(@Valid @RequestBody StoreRequest req) {
        if (!req.pickupEnabled() && !req.deliveryEnabled()) {
            throw new com.max.loja.shared.BusinessException("Deixe pelo menos retirada ou entrega ligada");
        }
        StoreSettings s = settings.current();
        s.setName(req.name().trim());
        s.setWhatsapp(blank(req.whatsapp()));
        s.setInstagram(blank(req.instagram()));
        s.setPickupAddress(blank(req.pickupAddress()));
        s.setPickupEnabled(req.pickupEnabled());
        s.setDeliveryEnabled(req.deliveryEnabled());
        s.setDeliveryFee(req.deliveryFee());
        s.setFreeDeliveryFrom(req.freeDeliveryFrom());
        return StoreResponse.from(s);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
