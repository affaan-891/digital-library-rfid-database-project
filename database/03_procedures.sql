-- ============================================================================
-- DIGITAL LIBRARY MANAGEMENT & RFID TIERED FINE ENGINE
-- Stored Procedures & Functions
-- Target RDBMS: MySQL 8.0+
-- ACID Transaction Management, Tiered Slabs & Straight-Line Asset Depreciation
-- ============================================================================

USE `library_rfid_db`;

DROP PROCEDURE IF EXISTS `sp_process_book_return`;
DROP PROCEDURE IF EXISTS `sp_assess_lost_book_charge`;
DROP FUNCTION IF EXISTS `fn_get_patron_total_unpaid_fines`;

DELIMITER //

-- ============================================================================
-- FUNCTION: fn_get_patron_total_unpaid_fines
-- Deterministic helper function computing total outstanding fine liability.
-- ============================================================================
CREATE FUNCTION `fn_get_patron_total_unpaid_fines`(
    `p_patron_id` INT
) 
RETURNS DECIMAL(8,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_total_unpaid DECIMAL(8,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(f.net_payable), 0.00)
      INTO v_total_unpaid
      FROM overdue_fines f
      INNER JOIN loan_transactions lt ON f.loan_id = lt.loan_id
     WHERE lt.patron_id = p_patron_id
       AND f.payment_status IN ('Unpaid', 'Partially_Paid');

    RETURN v_total_unpaid;
END //

-- ============================================================================
-- PROCEDURE 1: sp_process_book_return
-- Handles book return with ACID transaction safety & progressive fine slabs.
-- Fine Slab Architecture:
--   - Days 1 to 7:   base_daily_rate * 1.0 (Standard Grace/Initial Overdue)
--   - Days 8 to 14:  base_daily_rate * 1.5 (Escalation Tier)
--   - Days 15+:      base_daily_rate * 2.0 (Severe Delinquency Tier)
-- Cap: Calculated fine cannot exceed 100% of title replacement cost.
-- ============================================================================
CREATE PROCEDURE `sp_process_book_return`(
    IN  `p_copy_id`       INT,
    IN  `p_return_date`   DATE,
    OUT `p_fine_assessed` DECIMAL(8,2)
)
proc_label: BEGIN
    DECLARE v_loan_id INT;
    DECLARE v_patron_id INT;
    DECLARE v_due_date DATE;
    DECLARE v_base_daily_rate DECIMAL(6,2);
    DECLARE v_replacement_cost DECIMAL(8,2);
    DECLARE v_overdue_days INT DEFAULT 0;
    DECLARE v_calculated_fine DECIMAL(8,2) DEFAULT 0.00;

    -- Transaction rollback on unexpected exception
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. Pessimistic lock on active loan
    SELECT lt.loan_id, lt.patron_id, lt.due_date, pc.daily_fine_rate, bt.base_replacement_cost
      INTO v_loan_id, v_patron_id, v_due_date, v_base_daily_rate, v_replacement_cost
      FROM loan_transactions lt
      INNER JOIN book_copies bc ON lt.copy_id = bc.copy_id
      INNER JOIN book_titles bt ON bc.title_id = bt.title_id
      INNER JOIN patrons p ON lt.patron_id = p.patron_id
      INNER JOIN patron_categories pc ON p.category_id = pc.category_id
     WHERE lt.copy_id = p_copy_id
       AND lt.loan_status IN ('Active', 'Overdue')
     ORDER BY lt.issue_date DESC
     LIMIT 1
     FOR UPDATE;

    -- Validate existence of active loan
    IF v_loan_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Return Processing Error: No active or overdue loan transaction found for this copy ID.';
    END IF;

    -- 2. Calculate overdue duration
    SET v_overdue_days = DATEDIFF(p_return_date, v_due_date);

    IF v_overdue_days <= 0 THEN
        SET v_overdue_days = 0;
        SET v_calculated_fine = 0.00;
    ELSE
        -- 3. Progressive Tiered Fine Calculation
        IF v_overdue_days <= 7 THEN
            -- Tier 1 (Days 1 to 7)
            SET v_calculated_fine = v_overdue_days * (v_base_daily_rate * 1.00);
        ELSEIF v_overdue_days <= 14 THEN
            -- Tier 2 (Days 8 to 14)
            SET v_calculated_fine = (7 * v_base_daily_rate * 1.00)
                                  + ((v_overdue_days - 7) * (v_base_daily_rate * 1.50));
        ELSE
            -- Tier 3 (Days 15+)
            SET v_calculated_fine = (7 * v_base_daily_rate * 1.00)
                                  + (7 * (v_base_daily_rate * 1.50))
                                  + ((v_overdue_days - 14) * (v_base_daily_rate * 2.00));
        END IF;

        -- Apply title replacement cost cap (Anti-gouging ceiling)
        IF v_calculated_fine > v_replacement_cost THEN
            SET v_calculated_fine = v_replacement_cost;
        END IF;
    END IF;

    -- Round fine to 2 decimal places
    SET v_calculated_fine = ROUND(v_calculated_fine, 2);
    SET p_fine_assessed = v_calculated_fine;

    -- 4. Record Fine Assessment if overdue
    IF v_calculated_fine > 0.00 THEN
        INSERT INTO overdue_fines (
            loan_id,
            overdue_days,
            calculated_fine,
            waiver_amount,
            net_payable,
            payment_status
        ) VALUES (
            v_loan_id,
            v_overdue_days,
            v_calculated_fine,
            0.00,
            v_calculated_fine,
            'Unpaid'
        );

        -- Audit Log for Fine
        INSERT INTO library_audit_logs (copy_id, patron_id, action_type, details)
        VALUES (
            p_copy_id,
            v_patron_id,
            'FINE_ASSESSED',
            CONCAT('Tiered fine of $', v_calculated_fine, ' assessed on Loan ID #', v_loan_id, ' for ', v_overdue_days, ' overdue day(s).')
        );
    END IF;

    -- 5. Complete Loan Cycle (Fires trg_auto_promote_reservation_on_return)
    UPDATE loan_transactions
       SET return_date = p_return_date,
           loan_status = 'Returned'
     WHERE loan_id = v_loan_id;

    COMMIT;
END //

-- ============================================================================
-- PROCEDURE 2: sp_assess_lost_book_charge
-- Straight-Line Depreciation Recovery Algorithm:
--   - 10% depreciation per annum from acquisition date.
--   - Guaranteed 30% residual value salvage floor.
--   - Standard administrative processing overhead ($15.00).
--   - Accumulated overdue fines up to loss declaration date.
-- ============================================================================
CREATE PROCEDURE `sp_assess_lost_book_charge`(
    IN  `p_loan_id`               INT,
    OUT `p_total_recovery_fee`    DECIMAL(8,2)
)
proc_label: BEGIN
    DECLARE v_copy_id INT;
    DECLARE v_patron_id INT;
    DECLARE v_title_id INT;
    DECLARE v_acquisition_date DATE;
    DECLARE v_base_cost DECIMAL(8,2);
    DECLARE v_due_date DATE;
    DECLARE v_base_daily_rate DECIMAL(6,2);
    
    DECLARE v_age_years INT;
    DECLARE v_depreciation_factor DECIMAL(5,2);
    DECLARE v_depreciated_value DECIMAL(8,2);
    DECLARE v_overdue_days INT;
    DECLARE v_accumulated_fine DECIMAL(8,2) DEFAULT 0.00;
    DECLARE v_processing_fee CONSTANT DECIMAL(8,2) VALUE 15.00;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. Pessimistic lock on loan and asset specifications
    SELECT lt.copy_id, lt.patron_id, lt.due_date, bc.acquisition_date,
           bt.title_id, bt.base_replacement_cost, pc.daily_fine_rate
      INTO v_copy_id, v_patron_id, v_due_date, v_acquisition_date,
           v_title_id, v_base_cost, v_base_daily_rate
      FROM loan_transactions lt
      INNER JOIN book_copies bc ON lt.copy_id = bc.copy_id
      INNER JOIN book_titles bt ON bc.title_id = bt.title_id
      INNER JOIN patrons p ON lt.patron_id = p.patron_id
      INNER JOIN patron_categories pc ON p.category_id = pc.category_id
     WHERE lt.loan_id = p_loan_id
       AND lt.loan_status IN ('Active', 'Overdue')
     FOR UPDATE;

    IF v_copy_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lost Book Error: Loan is not in an Active or Overdue state eligible for loss declaration.';
    END IF;

    -- 2. Compute Asset Depreciation (10% per year, min 30% residual floor)
    SET v_age_years = TIMESTAMPDIFF(YEAR, v_acquisition_date, CURDATE());
    IF v_age_years < 0 THEN 
        SET v_age_years = 0; 
    END IF;

    -- Residual factor: max(1.0 - (0.10 * years), 0.30)
    SET v_depreciation_factor = GREATEST(1.00 - (v_age_years * 0.10), 0.30);
    SET v_depreciated_value = ROUND(v_base_cost * v_depreciation_factor, 2);

    -- 3. Calculate accumulated overdue fine up to today
    SET v_overdue_days = DATEDIFF(CURDATE(), v_due_date);
    IF v_overdue_days > 0 THEN
        IF v_overdue_days <= 7 THEN
            SET v_accumulated_fine = v_overdue_days * (v_base_daily_rate * 1.00);
        ELSEIF v_overdue_days <= 14 THEN
            SET v_accumulated_fine = (7 * v_base_daily_rate * 1.00)
                                   + ((v_overdue_days - 7) * (v_base_daily_rate * 1.50));
        ELSE
            SET v_accumulated_fine = (7 * v_base_daily_rate * 1.00)
                                   + (7 * (v_base_daily_rate * 1.50))
                                   + ((v_overdue_days - 14) * (v_base_daily_rate * 2.00));
        END IF;

        IF v_accumulated_fine > v_base_cost THEN
            SET v_accumulated_fine = v_base_cost;
        END IF;
    ELSE
        SET v_overdue_days = 0;
        SET v_accumulated_fine = 0.00;
    END IF;

    -- 4. Calculate total recovery invoice
    SET p_total_recovery_fee = ROUND(v_depreciated_value + v_processing_fee + v_accumulated_fine, 2);

    -- 5. Update physical copy condition to Lost
    UPDATE book_copies
       SET condition_grade = 'Lost',
           status = 'Available'
     WHERE copy_id = v_copy_id;

    -- 6. Update loan transaction to Declared_Lost
    UPDATE loan_transactions
       SET loan_status = 'Declared_Lost',
           return_date = CURDATE()
     WHERE loan_id = p_loan_id;

    -- 7. Upsert Fine / Loss Assessment Record
    INSERT INTO overdue_fines (
        loan_id,
        overdue_days,
        calculated_fine,
        waiver_amount,
        net_payable,
        payment_status
    ) VALUES (
        p_loan_id,
        v_overdue_days,
        p_total_recovery_fee,
        0.00,
        p_total_recovery_fee,
        'Unpaid'
    )
    ON DUPLICATE KEY UPDATE
        calculated_fine = VALUES(calculated_fine),
        net_payable = VALUES(net_payable),
        payment_status = 'Unpaid';

    -- 8. Record in Tamper-Evident Audit Log
    INSERT INTO library_audit_logs (copy_id, patron_id, action_type, details)
    VALUES (
        v_copy_id,
        v_patron_id,
        'LOST_DEPRECIATED',
        CONCAT('Book Copy ID #', v_copy_id, ' declared Lost. Age: ', v_age_years, ' yrs. Depreciated book value: $', v_depreciated_value, ', Admin processing fee: $', v_processing_fee, ', Overdue fine: $', v_accumulated_fine, '. Total recovery charge: $', p_total_recovery_fee)
    );

    COMMIT;
END //

DELIMITER ;
