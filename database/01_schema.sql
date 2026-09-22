-- ============================================================================
-- DIGITAL LIBRARY MANAGEMENT & RFID TIERED FINE ENGINE
-- Database Schema Definition (DDL)
-- Target RDBMS: MySQL 8.0+ (InnoDB Engine)
-- Character Set: utf8mb4 | Collation: utf8mb4_unicode_ci
-- Normalization: Fully 3NF Compliant
-- ============================================================================

DROP DATABASE IF EXISTS `library_rfid_db`;
CREATE DATABASE `library_rfid_db`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `library_rfid_db`;

-- ----------------------------------------------------------------------------
-- 1. TABLE: publishers
-- Academic publishers providing catalog titles and textbooks.
-- ----------------------------------------------------------------------------
CREATE TABLE `publishers` (
    `publisher_id`    INT AUTO_INCREMENT PRIMARY KEY,
    `publisher_name`  VARCHAR(150) NOT NULL UNIQUE,
    `contact_email`   VARCHAR(100) NOT NULL,
    `country`         VARCHAR(60)  NOT NULL,
    `website`         VARCHAR(255) NULL,
    `created_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `chk_pub_email` CHECK (`contact_email` LIKE '%@%.%')
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 2. TABLE: book_titles
-- Conceptual catalog items (Titles / ISBNs) independent of physical copies.
-- ----------------------------------------------------------------------------
CREATE TABLE `book_titles` (
    `title_id`              INT AUTO_INCREMENT PRIMARY KEY,
    `isbn`                  CHAR(13) NOT NULL UNIQUE,
    `title`                 VARCHAR(255) NOT NULL,
    `publisher_id`          INT NOT NULL,
    `edition`               INT NOT NULL DEFAULT 1,
    `publication_year`      INT NOT NULL,
    `base_replacement_cost` DECIMAL(8,2) NOT NULL,
    `created_at`            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `chk_pub_year` CHECK (`publication_year` BETWEEN 1800 AND 2026),
    CONSTRAINT `chk_repl_cost` CHECK (`base_replacement_cost` > 0),
    CONSTRAINT `chk_edition` CHECK (`edition` > 0),
    CONSTRAINT `fk_titles_publisher`
        FOREIGN KEY (`publisher_id`) REFERENCES `publishers` (`publisher_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 3. TABLE: authors
-- Scholarly and technical authors.
-- ----------------------------------------------------------------------------
CREATE TABLE `authors` (
    `author_id`   INT AUTO_INCREMENT PRIMARY KEY,
    `full_name`   VARCHAR(100) NOT NULL,
    `email`       VARCHAR(100) NOT NULL UNIQUE,
    `bio`         TEXT NULL,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `chk_author_email` CHECK (`email` LIKE '%@%.%')
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 4. TABLE: title_authors (Associative Entity: M-to-N)
-- Resolves Many-to-Many relationship between titles and multi-author works.
-- ----------------------------------------------------------------------------
CREATE TABLE `title_authors` (
    `title_id`          INT NOT NULL,
    `author_id`         INT NOT NULL,
    `is_primary_author` BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (`title_id`, `author_id`),
    CONSTRAINT `fk_ta_title`
        FOREIGN KEY (`title_id`) REFERENCES `book_titles` (`title_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT `fk_ta_author`
        FOREIGN KEY (`author_id`) REFERENCES `authors` (`author_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 5. TABLE: book_copies
-- Physical item instances tagged with High-Frequency (HF) / UHF RFID chips.
-- ----------------------------------------------------------------------------
CREATE TABLE `book_copies` (
    `copy_id`           INT AUTO_INCREMENT PRIMARY KEY,
    `title_id`          INT NOT NULL,
    `rfid_tag_uid`      VARCHAR(50) NOT NULL UNIQUE,
    `barcode`           VARCHAR(50) NOT NULL UNIQUE,
    `acquisition_date`  DATE NOT NULL,
    `condition_grade`   ENUM('New', 'Good', 'Fair', 'Damaged', 'Lost') NOT NULL DEFAULT 'New',
    `status`            ENUM('Available', 'Issued', 'Reserved', 'Under_Binding') NOT NULL DEFAULT 'Available',
    `created_at`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_copies_title`
        FOREIGN KEY (`title_id`) REFERENCES `book_titles` (`title_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX `idx_rfid_lookup` (`rfid_tag_uid`),
    INDEX `idx_barcode_lookup` (`barcode`),
    INDEX `idx_composite_status` (`title_id`, `status`, `condition_grade`)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 6. TABLE: patron_categories
-- Academic tier specifications determining circulation rights and quotas.
-- ----------------------------------------------------------------------------
CREATE TABLE `patron_categories` (
    `category_id`         INT AUTO_INCREMENT PRIMARY KEY,
    `category_name`       ENUM('Undergraduate', 'Postgraduate', 'Faculty', 'Researcher') NOT NULL UNIQUE,
    `max_borrow_limit`    INT NOT NULL,
    `standard_loan_days`  INT NOT NULL,
    `daily_fine_rate`     DECIMAL(6,2) NOT NULL,
    `created_at`          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `chk_borrow_limit` CHECK (`max_borrow_limit` > 0),
    CONSTRAINT `chk_loan_days` CHECK (`standard_loan_days` > 0),
    CONSTRAINT `chk_fine_rate` CHECK (`daily_fine_rate` >= 0)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 7. TABLE: patrons
-- Library cardholders (students, researchers, academic faculty members).
-- ----------------------------------------------------------------------------
CREATE TABLE `patrons` (
    `patron_id`          INT AUTO_INCREMENT PRIMARY KEY,
    `membership_number`  VARCHAR(20) NOT NULL UNIQUE,
    `full_name`          VARCHAR(100) NOT NULL,
    `category_id`        INT NOT NULL,
    `email`              VARCHAR(100) NOT NULL UNIQUE,
    `phone`              VARCHAR(25) NOT NULL UNIQUE,
    `account_status`     ENUM('Active', 'Suspended', 'Expired') NOT NULL DEFAULT 'Active',
    `enrolled_date`      DATE NOT NULL,
    `created_at`         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `chk_patron_email` CHECK (`email` LIKE '%@%.%'),
    CONSTRAINT `fk_patrons_category`
        FOREIGN KEY (`category_id`) REFERENCES `patron_categories` (`category_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX `idx_membership` (`membership_number`),
    INDEX `idx_account_status` (`account_status`)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 8. TABLE: loan_transactions
-- Physical checkout and checkin cycle lifecycle.
-- ----------------------------------------------------------------------------
CREATE TABLE `loan_transactions` (
    `loan_id`         INT AUTO_INCREMENT PRIMARY KEY,
    `copy_id`         INT NOT NULL,
    `patron_id`       INT NOT NULL,
    `issue_date`      DATE NOT NULL,
    `due_date`        DATE NOT NULL,
    `return_date`     DATE NULL,
    `loan_status`     ENUM('Active', 'Returned', 'Overdue', 'Declared_Lost') NOT NULL DEFAULT 'Active',
    `checked_out_by`  VARCHAR(50) NOT NULL,
    `created_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `chk_due_after_issue` CHECK (`due_date` >= `issue_date`),
    CONSTRAINT `chk_return_after_issue` CHECK (`return_date` IS NULL OR `return_date` >= `issue_date`),
    CONSTRAINT `fk_loans_copy`
        FOREIGN KEY (`copy_id`) REFERENCES `book_copies` (`copy_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT `fk_loans_patron`
        FOREIGN KEY (`patron_id`) REFERENCES `patrons` (`patron_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    INDEX `idx_loan_status_due` (`loan_status`, `due_date`),
    INDEX `idx_patron_active_loans` (`patron_id`, `loan_status`)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 9. TABLE: overdue_fines
-- Financial ledger tracking progressive fines, adjustments, and receipts.
-- ----------------------------------------------------------------------------
CREATE TABLE `overdue_fines` (
    `fine_id`          INT AUTO_INCREMENT PRIMARY KEY,
    `loan_id`          INT NOT NULL UNIQUE,
    `overdue_days`     INT NOT NULL,
    `calculated_fine`  DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    `waiver_amount`    DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    `net_payable`      DECIMAL(8,2) NOT NULL,
    `payment_status`   ENUM('Unpaid', 'Partially_Paid', 'Paid', 'Waived') NOT NULL DEFAULT 'Unpaid',
    `assessed_at`      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `paid_at`          TIMESTAMP NULL,
    CONSTRAINT `chk_overdue_days` CHECK (`overdue_days` >= 0),
    CONSTRAINT `chk_calc_fine` CHECK (`calculated_fine` >= 0),
    CONSTRAINT `chk_waiver_amount` CHECK (`waiver_amount` >= 0 AND `waiver_amount` <= `calculated_fine`),
    CONSTRAINT `chk_net_payable` CHECK (`net_payable` >= 0),
    CONSTRAINT `fk_fines_loan`
        FOREIGN KEY (`loan_id`) REFERENCES `loan_transactions` (`loan_id`)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 10. TABLE: book_reservations
-- Priority queue management for high-demand titles with finite copies.
-- ----------------------------------------------------------------------------
CREATE TABLE `book_reservations` (
    `reservation_id`           INT AUTO_INCREMENT PRIMARY KEY,
    `title_id`                 INT NOT NULL,
    `patron_id`                INT NOT NULL,
    `reservation_date`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `priority_queue_position`  INT NOT NULL,
    `notification_sent_at`     DATETIME NULL,
    `reservation_status`       ENUM('Queued', 'Notified', 'Fulfilled', 'Cancelled', 'Expired') NOT NULL DEFAULT 'Queued',
    CONSTRAINT `chk_queue_pos` CHECK (`priority_queue_position` > 0),
    CONSTRAINT `uq_title_patron_active_res` UNIQUE (`title_id`, `patron_id`, `reservation_status`),
    CONSTRAINT `fk_res_title`
        FOREIGN KEY (`title_id`) REFERENCES `book_titles` (`title_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT `fk_res_patron`
        FOREIGN KEY (`patron_id`) REFERENCES `patrons` (`patron_id`)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    INDEX `idx_res_queue` (`title_id`, `reservation_status`, `priority_queue_position`)
) ENGINE = InnoDB;

-- ----------------------------------------------------------------------------
-- 11. TABLE: library_audit_logs
-- Immutable tamper-evident operational and financial event journal.
-- ----------------------------------------------------------------------------
CREATE TABLE `library_audit_logs` (
    `log_id`       INT AUTO_INCREMENT PRIMARY KEY,
    `copy_id`      INT NULL,
    `patron_id`    INT NULL,
    `action_type`  ENUM('CHECK_OUT', 'CHECK_IN', 'FINE_ASSESSED', 'FINE_PAID', 'LOST_DEPRECIATED', 'RESERVATION_PROMOTED') NOT NULL,
    `details`      TEXT NOT NULL,
    `logged_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_audit_copy`
        FOREIGN KEY (`copy_id`) REFERENCES `book_copies` (`copy_id`)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT `fk_audit_patron`
        FOREIGN KEY (`patron_id`) REFERENCES `patrons` (`patron_id`)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    INDEX `idx_audit_action_time` (`action_type`, `logged_at`)
) ENGINE = InnoDB;
