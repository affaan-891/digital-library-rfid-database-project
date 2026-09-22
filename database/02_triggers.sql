-- ============================================================================
-- DIGITAL LIBRARY MANAGEMENT & RFID TIERED FINE ENGINE
-- Database Triggers Definition
-- Target RDBMS: MySQL 8.0+
-- Business Rules: Quota Validation, Status Verification & FIFO Reservation Promotion
-- ============================================================================

USE `library_rfid_db`;

DROP TRIGGER IF EXISTS `trg_enforce_patron_borrow_limit`;
DROP TRIGGER IF EXISTS `trg_prevent_unavailable_copy_checkout`;
DROP TRIGGER IF EXISTS `trg_mark_copy_issued_on_checkout`;
DROP TRIGGER IF EXISTS `trg_auto_promote_reservation_on_return`;

DELIMITER //

-- ----------------------------------------------------------------------------
-- TRIGGER 1: trg_enforce_patron_borrow_limit
-- Type: BEFORE INSERT ON loan_transactions
-- Purpose: Enforces active membership verification and borrowing quota limit
--          governed by the patron's academic tier (Undergrad, Postgrad, Faculty, Researcher).
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_enforce_patron_borrow_limit`
BEFORE INSERT ON `loan_transactions`
FOR EACH ROW
BEGIN
    DECLARE v_account_status VARCHAR(20);
    DECLARE v_max_limit INT;
    DECLARE v_current_active_loans INT;

    -- Allow administrative bulk seeding without trigger execution if flag is set
    IF @DISABLE_TRIGGERS = 1 THEN
        -- Skip trigger execution during seed data loading
        SET v_account_status = NULL;
    ELSE
        -- Fetch patron account status and tier borrow limit
        SELECT p.account_status, pc.max_borrow_limit
          INTO v_account_status, v_max_limit
          FROM patrons p
          INNER JOIN patron_categories pc ON p.category_id = pc.category_id
         WHERE p.patron_id = NEW.patron_id;

        -- 1. Validate Account Status
        IF v_account_status IS NULL OR v_account_status <> 'Active' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Borrowing Limit Exceeded: Patron has reached max allowed checkout quota or account is inactive.';
        END IF;

        -- 2. Count Active / Overdue Loans currently held by the patron
        SELECT COUNT(*)
          INTO v_current_active_loans
          FROM loan_transactions
         WHERE patron_id = NEW.patron_id
           AND loan_status IN ('Active', 'Overdue');

        -- Check if quota is saturated
        IF v_current_active_loans >= v_max_limit THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Borrowing Limit Exceeded: Patron has reached max allowed checkout quota or account is inactive.';
        END IF;
    END IF;
END //

-- ----------------------------------------------------------------------------
-- TRIGGER 2: trg_prevent_unavailable_copy_checkout
-- Type: BEFORE INSERT ON loan_transactions
-- Purpose: Prevents double checkout or checkout of damaged, reserved, or
--          under-binding copies.
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_prevent_unavailable_copy_checkout`
BEFORE INSERT ON `loan_transactions`
FOR EACH ROW
BEGIN
    DECLARE v_copy_status VARCHAR(30);
    DECLARE v_condition_grade VARCHAR(20);

    IF @DISABLE_TRIGGERS IS NULL OR @DISABLE_TRIGGERS <> 1 THEN
        SELECT status, condition_grade
          INTO v_copy_status, v_condition_grade
          FROM book_copies
         WHERE copy_id = NEW.copy_id;

        -- Ensure item exists and is strictly 'Available'
        IF v_copy_status IS NULL OR v_copy_status <> 'Available' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Checkout Conflict: Book copy is not in Available status.';
        END IF;

        -- Prevent circulation of Damaged or Lost physical assets
        IF v_condition_grade IN ('Damaged', 'Lost') THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Checkout Conflict: Book copy is physically compromised or marked Lost.';
        END IF;
    END IF;
END //

-- ----------------------------------------------------------------------------
-- HELPER TRIGGER: trg_mark_copy_issued_on_checkout
-- Type: AFTER INSERT ON loan_transactions
-- Purpose: Automatically transitions copy status to 'Issued' and records
--          tamper-evident audit log.
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_mark_copy_issued_on_checkout`
AFTER INSERT ON `loan_transactions`
FOR EACH ROW
BEGIN
    IF @DISABLE_TRIGGERS IS NULL OR @DISABLE_TRIGGERS <> 1 THEN
        -- Update copy state to Issued
        UPDATE book_copies
           SET status = 'Issued'
         WHERE copy_id = NEW.copy_id;

        -- Insert audit record
        INSERT INTO library_audit_logs (copy_id, patron_id, action_type, details)
        VALUES (
            NEW.copy_id,
            NEW.patron_id,
            'CHECK_OUT',
            CONCAT('Book Copy ID #', NEW.copy_id, ' checked out by Patron ID #', NEW.patron_id, ' under Loan ID #', NEW.loan_id, '. Due date: ', NEW.due_date)
        );
    END IF;
END //

-- ----------------------------------------------------------------------------
-- TRIGGER 3: trg_auto_promote_reservation_on_return
-- Type: AFTER UPDATE ON loan_transactions
-- Purpose: When a loaned copy is returned, checks the title's reservation queue.
--          If reservations exist, notifies the top patron (FIFO queue pos 1),
--          sets copy status to 'Reserved', and rebalances remaining queue.
--          If no reservations exist, resets copy status to 'Available'.
-- ----------------------------------------------------------------------------
CREATE TRIGGER `trg_auto_promote_reservation_on_return`
AFTER UPDATE ON `loan_transactions`
FOR EACH ROW
BEGIN
    DECLARE v_title_id INT;
    DECLARE v_res_id INT;
    DECLARE v_queued_patron_id INT;

    -- Execute logic only when transitioning to Returned
    IF (@DISABLE_TRIGGERS IS NULL OR @DISABLE_TRIGGERS <> 1) AND OLD.loan_status <> 'Returned' AND NEW.loan_status = 'Returned' THEN
        
        -- Retrieve title_id of the physical book copy
        SELECT title_id
          INTO v_title_id
          FROM book_copies
         WHERE copy_id = NEW.copy_id;

        -- Check if any queued reservations exist for this title
        SELECT reservation_id, patron_id
          INTO v_res_id, v_queued_patron_id
          FROM book_reservations
         WHERE title_id = v_title_id
           AND reservation_status = 'Queued'
         ORDER BY priority_queue_position ASC, reservation_date ASC
         LIMIT 1;

        IF v_res_id IS NOT NULL THEN
            -- 1. Promote top reservation to 'Notified'
            UPDATE book_reservations
               SET reservation_status = 'Notified',
                   notification_sent_at = NOW()
             WHERE reservation_id = v_res_id;

            -- 2. Mark the physical copy as 'Reserved'
            UPDATE book_copies
               SET status = 'Reserved'
             WHERE copy_id = NEW.copy_id;

            -- 3. Rebalance remaining queue positions (FIFO decrement)
            UPDATE book_reservations
               SET priority_queue_position = priority_queue_position - 1
             WHERE title_id = v_title_id
               AND reservation_status = 'Queued'
               AND priority_queue_position > 1;

            -- 4. Audit Log
            INSERT INTO library_audit_logs (copy_id, patron_id, action_type, details)
            VALUES (
                NEW.copy_id,
                v_queued_patron_id,
                'RESERVATION_PROMOTED',
                CONCAT('Copy ID #', NEW.copy_id, ' held for Patron ID #', v_queued_patron_id, ' via Reservation ID #', v_res_id, ' (FIFO Priority 1).')
            );
        ELSE
            -- No pending reservation; reset copy status to Available
            UPDATE book_copies
               SET status = 'Available'
             WHERE copy_id = NEW.copy_id;

            -- Audit Log
            INSERT INTO library_audit_logs (copy_id, patron_id, action_type, details)
            VALUES (
                NEW.copy_id,
                NEW.patron_id,
                'CHECK_IN',
                CONCAT('Copy ID #', NEW.copy_id, ' returned by Patron ID #', NEW.patron_id, ' and returned to active circulation.')
            );
        END IF;

    END IF;
END //

DELIMITER ;
