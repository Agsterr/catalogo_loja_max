package com.max.loja.delivery;

import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
public class CourierSubscription {

    @Id
    private Long courierId;

    @Column(nullable = false)
    private LocalDateTime paidUntil;
}
