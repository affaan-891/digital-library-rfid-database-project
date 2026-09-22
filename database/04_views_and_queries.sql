-- ============================================================================
-- DIGITAL LIBRARY MANAGEMENT & RFID TIERED FINE ENGINE
-- Analytical Views & Complex Viva-Ready Queries
-- Target RDBMS: MySQL 8.0+
-- ============================================================================

USE `library_rfid_db`;

DROP VIEW IF EXISTS `vw_overdue_loans_risk_register`;
DROP VIEW IF EXISTS `vw_title_circulation_demand_metrics`;

-- ============================================================================
-- 1. ANALYTICAL VIEW: vw_overdue_loans_risk_register
-- Identifies unreturned items exceeding their due date, dynamically computes
-- their progressive tiered fine accrued to date, and surfaces patron contact info.
-- ============================================================================
CREATE VIEW `vw_overdue_loans_risk_register` AS
SELECT 
    lt.loan_id,
    lt.copy_id,
    bc.rfid_tag_uid,
    bc.barcode,
    bt.title,
    bt.isbn,
    bt.base_replacement_cost,
    p.patron_id,
    p.membership_number,
    p.full_name AS patron_name,
    p.email AS patron_email,
    p.phone AS patron_phone,
    pc.category_name,
    pc.daily_fine_rate,
    lt.issue_date,
    lt.due_date,
    DATEDIFF(CURDATE(), lt.due_date) AS days_overdue,
    ROUND(
        LEAST(
            CASE 
                -- Tier 1: Days 1 to 7
                WHEN DATEDIFF(CURDATE(), lt.due_date) <= 7 THEN
                    DATEDIFF(CURDATE(), lt.due_date) * (pc.daily_fine_rate * 1.00)
                -- Tier 2: Days 8 to 14
                WHEN DATEDIFF(CURDATE(), lt.due_date) <= 14 THEN
                    (7 * pc.daily_fine_rate * 1.00) 
                    + ((DATEDIFF(CURDATE(), lt.due_date) - 7) * (pc.daily_fine_rate * 1.50))
                -- Tier 3: Days 15+
                ELSE
                    (7 * pc.daily_fine_rate * 1.00) 
                    + (7 * pc.daily_fine_rate * 1.50) 
                    + ((DATEDIFF(CURDATE(), lt.due_date) - 14) * (pc.daily_fine_rate * 2.00))
            END,
            bt.base_replacement_cost
        ), 
        2
    ) AS progressive_fine_accrued
FROM loan_transactions lt
INNER JOIN book_copies bc ON lt.copy_id = bc.copy_id
INNER JOIN book_titles bt ON bc.title_id = bt.title_id
INNER JOIN patrons p ON lt.patron_id = p.patron_id
INNER JOIN patron_categories pc ON p.category_id = pc.category_id
WHERE lt.loan_status IN ('Active', 'Overdue')
  AND CURDATE() > lt.due_date;

-- ============================================================================
-- 2. ANALYTICAL VIEW: vw_title_circulation_demand_metrics
-- Aggregates physical asset deployment, active circulation, pending demand queue,
-- and calculates the operational turnover ratio.
-- ============================================================================
CREATE VIEW `vw_title_circulation_demand_metrics` AS
SELECT 
    bt.title_id,
    bt.isbn,
    bt.title,
    pub.publisher_name,
    COUNT(DISTINCT bc.copy_id) AS total_physical_copies,
    COUNT(DISTINCT CASE WHEN bc.status = 'Issued' THEN bc.copy_id END) AS currently_issued_copies,
    COUNT(DISTINCT CASE WHEN bc.status = 'Available' THEN bc.copy_id END) AS currently_available_copies,
    COUNT(DISTINCT CASE WHEN br.reservation_status = 'Queued' THEN br.reservation_id END) AS pending_reservations_count,
    COUNT(DISTINCT lt.loan_id) AS total_lifetime_checkouts,
    ROUND(
        COUNT(DISTINCT lt.loan_id) / NULLIF(COUNT(DISTINCT bc.copy_id), 0),
        2
    ) AS circulation_turnover_ratio
FROM book_titles bt
INNER JOIN publishers pub ON bt.publisher_id = pub.publisher_id
LEFT JOIN book_copies bc ON bt.title_id = bc.title_id
LEFT JOIN book_reservations br ON bt.title_id = br.title_id
LEFT JOIN loan_transactions lt ON bc.copy_id = lt.copy_id
GROUP BY bt.title_id, bt.isbn, bt.title, pub.publisher_name;

-- ============================================================================
-- COMPLEX VIVA-READY QUERIES WITH ACADEMIC CONTEXT
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1: Titles where reservation demand exceeds total physical copies held by > 200%
-- Demonstrates: INNER JOIN, LEFT JOIN, GROUP BY, HAVING, Aggregate Ratio
-- Academic Context: Procurement bottleneck analysis for university acquisition committee.
-- ----------------------------------------------------------------------------
SELECT 
    bt.title_id,
    bt.isbn,
    bt.title,
    COUNT(DISTINCT bc.copy_id) AS total_copies_held,
    COUNT(DISTINCT br.reservation_id) AS queued_reservations,
    ROUND((COUNT(DISTINCT br.reservation_id) / NULLIF(COUNT(DISTINCT bc.copy_id), 0)) * 100, 2) AS demand_pressure_pct
FROM book_titles bt
INNER JOIN book_copies bc ON bt.title_id = bc.title_id
LEFT JOIN book_reservations br ON bt.title_id = br.title_id AND br.reservation_status = 'Queued'
GROUP BY bt.title_id, bt.isbn, bt.title
HAVING queued_reservations > (total_copies_held * 2.0);

-- ----------------------------------------------------------------------------
-- Q2: Anti-Join using NOT EXISTS
-- Registered patrons who have never borrowed any library asset in the last 180 days.
-- Demonstrates: Anti-join optimization pattern, correlated NOT EXISTS subquery.
-- Academic Context: Disengaged member outreach and card renewal purge preparation.
-- ----------------------------------------------------------------------------
SELECT 
    p.patron_id,
    p.membership_number,
    p.full_name,
    p.email,
    pc.category_name,
    p.enrolled_date
FROM patrons p
INNER JOIN patron_categories pc ON p.category_id = pc.category_id
WHERE p.account_status = 'Active'
  AND NOT EXISTS (
      SELECT 1 
      FROM loan_transactions lt
      WHERE lt.patron_id = p.patron_id
        AND lt.issue_date >= DATE_SUB(CURDATE(), INTERVAL 180 DAY)
  )
ORDER BY p.enrolled_date ASC;

-- ----------------------------------------------------------------------------
-- Q3: Correlated Subquery
-- Patrons whose average loan duration exceeds the average borrowing period of their category tier.
-- Demonstrates: Correlated subquery in WHERE/HAVING clause, multi-table aggregate comparisons.
-- Academic Context: Behavioral anomaly detection for chronic loan hoarders.
-- ----------------------------------------------------------------------------
SELECT 
    p.patron_id,
    p.full_name,
    pc.category_name,
    pc.standard_loan_days AS tier_policy_days,
    ROUND(AVG(DATEDIFF(COALESCE(lt.return_date, CURDATE()), lt.issue_date)), 2) AS patron_avg_loan_days
FROM patrons p
INNER JOIN patron_categories pc ON p.category_id = pc.category_id
INNER JOIN loan_transactions lt ON p.patron_id = lt.patron_id
GROUP BY p.patron_id, p.full_name, pc.category_name, pc.standard_loan_days
HAVING patron_avg_loan_days > (
    SELECT AVG(DATEDIFF(COALESCE(sub_lt.return_date, CURDATE()), sub_lt.issue_date))
    FROM loan_transactions sub_lt
    INNER JOIN patrons sub_p ON sub_lt.patron_id = sub_p.patron_id
    WHERE sub_p.category_id = p.category_id
)
ORDER BY patron_avg_loan_days DESC;

-- ----------------------------------------------------------------------------
-- Q4: Window Function DENSE_RANK()
-- Ranking titles by lifetime circulation frequency partitioned by academic publisher.
-- Demonstrates: Window functions (DENSE_RANK() OVER (PARTITION BY ... ORDER BY ...)).
-- Academic Context: Publisher licensing ROI assessment and contract renegotiation.
-- ----------------------------------------------------------------------------
SELECT 
    pub.publisher_name,
    bt.title,
    bt.isbn,
    COUNT(lt.loan_id) AS total_checkouts,
    DENSE_RANK() OVER (
        PARTITION BY pub.publisher_id 
        ORDER BY COUNT(lt.loan_id) DESC
    ) AS rank_within_publisher
FROM publishers pub
INNER JOIN book_titles bt ON pub.publisher_id = bt.publisher_id
LEFT JOIN book_copies bc ON bt.title_id = bc.title_id
LEFT JOIN loan_transactions lt ON bc.copy_id = lt.copy_id
GROUP BY pub.publisher_id, pub.publisher_name, bt.title_id, bt.title, bt.isbn
ORDER BY pub.publisher_name ASC, rank_within_publisher ASC;

-- ----------------------------------------------------------------------------
-- Q5: Performance Optimization Analysis using EXPLAIN ANALYZE
-- Verification of composite B-Tree index scan on `(title_id, status, condition_grade)`.
-- Demonstrates: Query execution plan verification, index lookup vs full table scan.
-- Academic Context: Sub-millisecond RFID shelf inventory scanning verification.
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT 
    bc.copy_id,
    bc.rfid_tag_uid,
    bc.barcode,
    bc.status,
    bc.condition_grade,
    bt.title
FROM book_copies bc
INNER JOIN book_titles bt ON bc.title_id = bt.title_id
WHERE bc.title_id = 1
  AND bc.status = 'Available'
  AND bc.condition_grade IN ('New', 'Good');
