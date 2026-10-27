package com.max.loja.delivery;

import java.util.List;

import com.max.loja.delivery.CourierDtos.CancelRequest;
import com.max.loja.delivery.CourierDtos.CodeRequest;
import com.max.loja.delivery.CourierDtos.EarningsResponse;
import com.max.loja.delivery.CourierDtos.JobCard;
import com.max.loja.delivery.CourierDtos.JobDetail;
import com.max.loja.delivery.CourierDtos.OnlineRequest;
import com.max.loja.delivery.CourierDtos.ProfileRequest;
import com.max.loja.delivery.CourierDtos.ProfileResponse;
import com.max.loja.security.CurrentUser;
import com.max.loja.shared.PageResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** API do app do entregador. */
@RestController
public class CourierController {

    private final CourierService service;

    public CourierController(CourierService service) {
        this.service = service;
    }

    @GetMapping("/api/courier/me")
    public ProfileResponse me(@AuthenticationPrincipal Jwt jwt) {
        return service.profile(CurrentUser.of(jwt).id());
    }

    @PutMapping("/api/courier/me")
    public ProfileResponse update(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ProfileRequest req) {
        return service.update(CurrentUser.of(jwt).id(), req);
    }

    @PostMapping("/api/courier/online")
    public ProfileResponse online(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody OnlineRequest req) {
        return service.setOnline(CurrentUser.of(jwt).id(), req);
    }

    /** Mural: corridas abertas perto de {@code lat,lng} (ou da última posição/base), da mais perto para a mais longe. */
    @GetMapping("/api/courier/jobs/open")
    public PageResponse<JobCard> open(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) Double lat,
                                      @RequestParam(required = false) Double lng, @RequestParam(required = false) Integer page,
                                      @RequestParam(required = false) Integer size) {
        return service.openJobs(CurrentUser.of(jwt).id(), lat, lng, page, size);
    }

    @GetMapping("/api/courier/jobs/active")
    public List<JobDetail> active(@AuthenticationPrincipal Jwt jwt) {
        return service.active(CurrentUser.of(jwt).id());
    }

    @GetMapping("/api/courier/jobs/history")
    public PageResponse<JobDetail> history(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) Integer page,
                                           @RequestParam(required = false) Integer size) {
        return service.history(CurrentUser.of(jwt).id(), page, size);
    }

    @GetMapping("/api/courier/jobs/{id}")
    public JobDetail job(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        return service.job(CurrentUser.of(jwt).id(), id);
    }

    @PostMapping("/api/courier/jobs/{id}/accept")
    public JobDetail accept(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        return service.accept(CurrentUser.of(jwt).id(), id);
    }

    @PostMapping("/api/courier/jobs/{id}/pickup")
    public JobDetail pickUp(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id, @Valid @RequestBody CodeRequest req) {
        return service.pickUp(CurrentUser.of(jwt).id(), id, req.code());
    }

    @PostMapping("/api/courier/jobs/{id}/deliver")
    public JobDetail deliver(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id, @Valid @RequestBody CodeRequest req) {
        return service.deliver(CurrentUser.of(jwt).id(), id, req.code());
    }

    @PostMapping("/api/courier/jobs/{id}/cancel")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cancel(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id, @RequestBody(required = false) CancelRequest req) {
        service.cancel(CurrentUser.of(jwt).id(), id, req == null ? null : req.reason());
    }

    @GetMapping("/api/courier/earnings")
    public EarningsResponse earnings(@AuthenticationPrincipal Jwt jwt) {
        return service.earnings(CurrentUser.of(jwt).id());
    }
}
