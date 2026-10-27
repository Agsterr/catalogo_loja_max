package com.max.loja.catalog;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CategoryRepository extends JpaRepository<Category, Long> {

    List<Category> findAllByOrderByDepartmentAscPositionAscNameAsc();

    List<Category> findByActiveTrueOrderByDepartmentAscPositionAscNameAsc();
}
