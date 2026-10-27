package com.max.loja.store;

import org.springframework.data.jpa.repository.JpaRepository;

public interface StoreSettingsRepository extends JpaRepository<StoreSettings, Long> {

    default StoreSettings current() {
        return findById(1L).orElseThrow();
    }
}
