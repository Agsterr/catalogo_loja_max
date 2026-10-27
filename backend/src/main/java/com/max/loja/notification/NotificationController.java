package com.max.loja.notification;

import com.max.loja.notification.NotificationService.Inbox;
import com.max.loja.security.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Sino do app (paginado): a equipe vê os avisos da loja dela; o cliente, os dele em todas as lojas. */
@RestController
@RequestMapping("/api/notifications")
public class NotificationController {

    private final NotificationService service;

    public NotificationController(NotificationService service) {
        this.service = service;
    }

    @GetMapping
    public Inbox inbox(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) Integer page,
                       @RequestParam(required = false) Integer size) {
        return service.inbox(CurrentUser.of(jwt), page, size);
    }

    @PostMapping("/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void markAllRead(@AuthenticationPrincipal Jwt jwt) {
        service.markAllRead(CurrentUser.of(jwt));
    }

    @PostMapping("/{id}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void markRead(@AuthenticationPrincipal Jwt jwt, @PathVariable Long id) {
        service.markRead(CurrentUser.of(jwt), id);
    }
}
