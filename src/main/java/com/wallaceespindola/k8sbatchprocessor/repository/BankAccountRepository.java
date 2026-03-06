package com.wallaceespindola.k8sbatchprocessor.repository;

import com.wallaceespindola.k8sbatchprocessor.domain.BankAccount;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface BankAccountRepository extends JpaRepository<BankAccount, Long> {

    Page<BankAccount> findByIdBetweenAndStatus(Long minId, Long maxId, String status, Pageable pageable);

    long countByStatus(String status);

    long countByPartitionIdAndStatus(Integer partitionId, String status);

    long countByPartitionId(Integer partitionId);

    List<BankAccount> findByPartitionIdOrderById(Integer partitionId);

    @Query("SELECT b.id FROM BankAccount b ORDER BY b.id ASC")
    List<Long> findAllIdsSorted();

    @Query("SELECT MIN(b.id) FROM BankAccount b")
    Long findMinId();

    @Query("SELECT MAX(b.id) FROM BankAccount b")
    Long findMaxId();

    void deleteAllByStatus(String status);
}
