package com.max.loja.delivery;

import com.max.loja.security.CurrentUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** Acompanhar o entregador (cliente e loja) e avaliá-lo (cliente). */
@RestController
public class TrackingController {

    public record RateRequest(@Min(1) @Max(5) int stars, @Size(max = 300) String comment) {
    }

    private final TrackingService tracking;
    private final CourierRatingService rating;

    public TrackingController(TrackingService tracking, CourierRatingService rating) {
        this.tracking = tracking;
        this.rating = rating;
    }

    @GetMapping("/api/stores/{slug}/orders/{orderId}/tracking")
    public TrackingService.Tracking forCustomer(@AuthenticationPrincipal Jwt jwt, @PathVariable String slug, @PathVariable Long orderId) {
        return tracking.forCustomer(CurrentUser.of(jwt).id(), orderId);
    }

    @GetMapping("/api/store/orders/{orderId}/tracking")
    public TrackingService.Tracking forTeam(@PathVariable Long orderId) {
        return tracking.forTeam(orderId);
    }

    @PostMapping("/api/stores/{slug}/orders/{orderId}/rate-courier")
    public CourierRatingService.Result rate(@AuthenticationPrincipal Jwt jwt, @PathVariable String slug, @PathVariable Long orderId,
                                            @Valid @RequestBody RateRequest req) {
        return rating.rate(CurrentUser.of(jwt).id(), orderId, req.stars(), req.comment());
    }
}
