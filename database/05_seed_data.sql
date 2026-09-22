-- ============================================================================
-- DIGITAL LIBRARY MANAGEMENT & RFID TIERED FINE ENGINE
-- Realistic Academic Digital Library Seed Dataset (DML)
-- Target RDBMS: MySQL 8.0+
-- Execution Order: Complies strictly with foreign key dependencies.
-- ============================================================================

USE `library_rfid_db`;

-- Enable trigger bypass for deterministic, historical seed dataset ingestion
SET @DISABLE_TRIGGERS = 1;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------------------------------------------------------
-- TRUNCATE EXISTING TABLES IN REVERSE DEPENDENCY ORDER
-- ----------------------------------------------------------------------------
TRUNCATE TABLE `library_audit_logs`;
TRUNCATE TABLE `book_reservations`;
TRUNCATE TABLE `overdue_fines`;
TRUNCATE TABLE `loan_transactions`;
TRUNCATE TABLE `patrons`;
TRUNCATE TABLE `patron_categories`;
TRUNCATE TABLE `book_copies`;
TRUNCATE TABLE `title_authors`;
TRUNCATE TABLE `authors`;
TRUNCATE TABLE `book_titles`;
TRUNCATE TABLE `publishers`;

SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 1. SEED: publishers (4 Academic Technical Publishers)
-- ----------------------------------------------------------------------------
INSERT INTO `publishers` (`publisher_id`, `publisher_name`, `contact_email`, `country`, `website`) VALUES
(1, 'IEEE Computer Society', 'press-info@computer.org', 'United States', 'https://www.computer.org'),
(2, 'Springer Nature', 'service@springernature.com', 'Germany', 'https://www.springernature.com'),
(3, 'John Wiley & Sons', 'academicsales@wiley.com', 'United States', 'https://www.wiley.com'),
(4, 'Oxford University Press', 'library.enquiries@oup.com', 'United Kingdom', 'https://academic.oup.com');

-- ----------------------------------------------------------------------------
-- 2. SEED: book_titles (8 Foundational CS & Engineering Titles)
-- ----------------------------------------------------------------------------
INSERT INTO `book_titles` (`title_id`, `isbn`, `title`, `publisher_id`, `edition`, `publication_year`, `base_replacement_cost`) VALUES
(1, '9780131103627', 'The C Programming Language', 3, 2, 1988, 65.00),
(2, '9780262033848', 'Introduction to Algorithms (CLRS)', 1, 3, 2009, 125.00),
(3, '9780136042594', 'Artificial Intelligence: A Modern Approach', 2, 4, 2020, 139.50),
(4, '9780073523323', 'Database System Concepts', 2, 7, 2019, 115.00),
(5, '9781491903063', 'Designing Data-Intensive Applications', 4, 1, 2017, 59.99),
(6, '9780132143011', 'Distributed Systems: Principles and Paradigms', 3, 3, 2017, 89.50),
(7, '9780134685991', 'Effective Java', 1, 3, 2018, 54.00),
(8, '9780201633610', 'Design Patterns: Elements of Reusable Object-Oriented Software', 4, 1, 1994, 74.50);

-- ----------------------------------------------------------------------------
-- 3. SEED: authors (10 Celebrated Computer Science Authorities)
-- ----------------------------------------------------------------------------
INSERT INTO `authors` (`author_id`, `full_name`, `email`, `bio`) VALUES
(1, 'Brian W. Kernighan', 'bwk@bell-labs.com', 'Canadian computer scientist, co-creator of AWK and AMPL, co-author of the original C book.'),
(2, 'Dennis M. Ritchie', 'dmr@bell-labs.com', 'Creator of the C programming language and co-developer of the UNIX operating system, Turing Award laureate.'),
(3, 'Thomas H. Cormen', 'thc@cs.dartmouth.edu', 'Emeritus Professor of Computer Science at Dartmouth College and lead author of CLRS Algorithms.'),
(4, 'Charles E. Leiserson', 'cel@mit.edu', 'Professor of Computer Science and Engineering at MIT, ACM Fellow, pioneer in parallel computing.'),
(5, 'Stuart J. Russell', 'russell@berkeley.edu', 'Professor of Computer Science at UC Berkeley, renowned researcher in AI and human-compatible intelligence.'),
(6, 'Peter Norvig', 'pnorvig@stanford.edu', 'Director of Research at Google and Education Fellow at Stanford University.'),
(7, 'Abraham Silberschatz', 'avi@cs.yale.edu', 'Sidney J. Weinberg Professor of Computer Science at Yale University, operating systems and database pioneer.'),
(8, 'Martin Kleppmann', 'mk428@cam.ac.uk', 'Associate Professor in Distributed Systems at the University of Cambridge and author.'),
(9, 'Andrew S. Tanenbaum', 'ast@cs.vu.nl', 'Emeritus Professor of Computer Science at Vrije Universiteit Amsterdam, creator of MINIX.'),
(10, 'Joshua J. Bloch', 'josh@bloch.us', 'Software engineer and author, led design of numerous Java platform features including the Java Collections Framework.');

-- ----------------------------------------------------------------------------
-- 4. SEED: title_authors (Many-to-Many Title Authorship Associative Entity)
-- ----------------------------------------------------------------------------
INSERT INTO `title_authors` (`title_id`, `author_id`, `is_primary_author`) VALUES
(1, 1, TRUE),
(1, 2, FALSE),
(2, 3, TRUE),
(2, 4, FALSE),
(3, 5, TRUE),
(3, 6, FALSE),
(4, 7, TRUE),
(5, 8, TRUE),
(6, 9, TRUE),
(7, 10, TRUE),
(8, 3, TRUE);

-- ----------------------------------------------------------------------------
-- 5. SEED: patron_categories (4 Academic Tiers with Specific Policies)
-- ----------------------------------------------------------------------------
INSERT INTO `patron_categories` (`category_id`, `category_name`, `max_borrow_limit`, `standard_loan_days`, `daily_fine_rate`) VALUES
(1, 'Undergraduate', 3, 14, 1.00),
(2, 'Postgraduate',  5, 21, 1.50),
(3, 'Faculty',       10, 60, 0.50),
(4, 'Researcher',    7, 30, 0.75);

-- ----------------------------------------------------------------------------
-- 6. SEED: patrons (15 Campus Patrons)
-- ----------------------------------------------------------------------------
INSERT INTO `patrons` (`patron_id`, `membership_number`, `full_name`, `category_id`, `email`, `phone`, `account_status`, `enrolled_date`) VALUES
(1,  'UG-2023-0101', 'Amina Zafar',         1, 'amina.zafar@campus.edu',       '+92-300-1112233', 'Active',    '2023-09-01'),
(2,  'UG-2023-0102', 'Bilal Ahmed',         1, 'bilal.ahmed@campus.edu',       '+92-301-2223344', 'Active',    '2023-09-01'),
(3,  'UG-2023-0103', 'Hassan Raza',         1, 'hassan.raza@campus.edu',       '+92-302-3334455', 'Active',    '2023-09-05'),
(4,  'UG-2024-0104', 'Dua Fatima',          1, 'dua.fatima@campus.edu',        '+92-303-4445566', 'Active',    '2024-02-10'),
(5,  'UG-2024-0105', 'Usman Tariq',         1, 'usman.tariq@campus.edu',       '+92-304-5556677', 'Suspended', '2024-02-12'),
(6,  'UG-2024-0106', 'Khadija Imran',       1, 'khadija.imran@campus.edu',     '+92-305-6667788', 'Active',    '2024-09-01'),
(7,  'PG-2022-0201', 'Dr. Farhan Qureshi',  2, 'farhan.qureshi@campus.edu',    '+92-311-1234567', 'Active',    '2022-10-15'),
(8,  'PG-2023-0202', 'Sana Mir',            2, 'sana.mir@campus.edu',          '+92-312-2345678', 'Active',    '2023-03-01'),
(9,  'PG-2023-0203', 'Zainab Abbas',        2, 'zainab.abbas@campus.edu',      '+92-313-3456789', 'Active',    '2023-03-15'),
(10, 'PG-2024-0204', 'Omer Sheikh',         2, 'omer.sheikh@campus.edu',       '+92-314-4567890', 'Expired',   '2024-01-20'),
(11, 'FAC-1001',     'Prof. Tariq Mehmood', 3, 'tariq.mehmood@campus.edu',     '+92-321-9876543', 'Active',    '2018-01-10'),
(12, 'FAC-1002',     'Dr. Samina Altaf',    3, 'samina.altaf@campus.edu',      '+92-322-8765432', 'Active',    '2019-08-20'),
(13, 'FAC-1003',     'Dr. Naveed Akhtar',   3, 'naveed.akhtar@campus.edu',     '+92-323-7654321', 'Active',    '2020-11-05'),
(14, 'RES-3001',     'Ayesha Siddiqua',     4, 'ayesha.siddiqua@campus.edu',   '+92-331-5551234', 'Active',    '2022-06-01'),
(15, 'RES-3002',     'Hamza Khalid',        4, 'hamza.khalid@campus.edu',      '+92-332-6662345', 'Active',    '2023-01-15');

-- ----------------------------------------------------------------------------
-- 7. SEED: book_copies (24 Physical RFID Tagged Copies)
-- ----------------------------------------------------------------------------
INSERT INTO `book_copies` (`copy_id`, `title_id`, `rfid_tag_uid`, `barcode`, `acquisition_date`, `condition_grade`, `status`) VALUES
-- Title 1: The C Programming Language (3 Copies)
(1,  1, 'E28011606000020462000001', 'BC-1001', '2021-03-15', 'Good', 'Available'),
(2,  1, 'E28011606000020462000002', 'BC-1002', '2021-03-15', 'Fair', 'Issued'),
(3,  1, 'E28011606000020462000003', 'BC-1003', '2022-08-10', 'New',  'Available'),

-- Title 2: Introduction to Algorithms (4 Copies)
(4,  2, 'E28011606000020462000004', 'BC-1004', '2021-01-10', 'Good', 'Issued'),
(5,  2, 'E28011606000020462000005', 'BC-1005', '2021-01-10', 'Good', 'Issued'),
(6,  2, 'E28011606000020462000006', 'BC-1006', '2022-09-01', 'Fair', 'Reserved'),
(7,  2, 'E28011606000020462000007', 'BC-1007', '2023-05-18', 'New',  'Available'),

-- Title 3: Artificial Intelligence: A Modern Approach (3 Copies)
(8,  3, 'E28011606000020462000008', 'BC-1008', '2022-02-14', 'New',  'Issued'),
(9,  3, 'E28011606000020462000009', 'BC-1009', '2022-02-14', 'Good', 'Issued'),
(10, 3, 'E28011606000020462000010', 'BC-1010', '2023-11-20', 'Good', 'Available'),

-- Title 4: Database System Concepts (4 Copies)
(11, 4, 'E28011606000020462000011', 'BC-1011', '2021-04-12', 'Good', 'Available'),
(12, 4, 'E28011606000020462000012', 'BC-1012', '2021-04-12', 'Fair', 'Issued'),
(13, 4, 'E28011606000020462000013', 'BC-1013', '2022-10-05', 'Good', 'Issued'),
(14, 4, 'E28011606000020462000014', 'BC-1014', '2023-03-22', 'Damaged', 'Under_Binding'),

-- Title 5: Designing Data-Intensive Applications (3 Copies)
(15, 5, 'E28011606000020462000015', 'BC-1015', '2022-01-18', 'New',  'Issued'),
(16, 5, 'E28011606000020462000016', 'BC-1016', '2022-01-18', 'Good', 'Available'),
(17, 5, 'E28011606000020462000017', 'BC-1017', '2023-07-11', 'Good', 'Available'),

-- Title 6: Distributed Systems: Principles and Paradigms (3 Copies)
(18, 6, 'E28011606000020462000018', 'BC-1018', '2021-09-09', 'Good', 'Available'),
(19, 6, 'E28011606000020462000019', 'BC-1019', '2022-05-14', 'Fair', 'Issued'),
(20, 6, 'E28011606000020462000020', 'BC-1020', '2023-10-01', 'Lost', 'Available'),

-- Title 7: Effective Java (2 Copies)
(21, 7, 'E28011606000020462000021', 'BC-1021', '2022-04-20', 'Good', 'Available'),
(22, 7, 'E28011606000020462000022', 'BC-1022', '2023-08-30', 'New',  'Available'),

-- Title 8: Design Patterns (2 Copies)
(23, 8, 'E28011606000020462000023', 'BC-1023', '2021-06-15', 'Good', 'Available'),
(24, 8, 'E28011606000020462000024', 'BC-1024', '2023-02-10', 'Good', 'Available');

-- ----------------------------------------------------------------------------
-- 8. SEED: loan_transactions (20 Transactions: Active, Overdue, Returned, Lost)
-- ----------------------------------------------------------------------------
INSERT INTO `loan_transactions` (`loan_id`, `copy_id`, `patron_id`, `issue_date`, `due_date`, `return_date`, `loan_status`, `checked_out_by`) VALUES
-- Returned Normal Loans
(1,  1,  1,  '2026-07-01', '2026-07-15', '2026-07-14', 'Returned',      'librarian_desk1'),
(2,  3,  2,  '2026-07-05', '2026-07-19', '2026-07-18', 'Returned',      'librarian_desk1'),
(3,  11, 7,  '2026-07-10', '2026-07-31', '2026-07-29', 'Returned',      'self_kiosk_01'),
(4,  16, 11, '2026-06-01', '2026-07-31', '2026-07-25', 'Returned',      'librarian_desk2'),
(5,  21, 14, '2026-07-01', '2026-07-31', '2026-07-30', 'Returned',      'self_kiosk_02'),

-- Returned Overdue Loans (Triggered Fines)
(6,  7,  3,  '2026-07-01', '2026-07-15', '2026-07-25', 'Returned',      'librarian_desk1'), -- 10 days overdue
(7,  10, 8,  '2026-06-10', '2026-07-01', '2026-07-20', 'Returned',      'librarian_desk2'), -- 19 days overdue
(8,  17, 1,  '2026-07-15', '2026-07-29', '2026-08-04', 'Returned',      'self_kiosk_01'), -- 6 days overdue
(9,  23, 4,  '2026-07-01', '2026-07-15', '2026-07-28', 'Returned',      'librarian_desk1'), -- 13 days overdue

-- Active Current Loans (Not Overdue)
(10, 2,  2,  '2026-09-15', '2026-09-29', NULL,         'Active',        'self_kiosk_01'),
(11, 4,  7,  '2026-09-10', '2026-10-01', NULL,         'Active',        'librarian_desk1'),
(12, 12, 12, '2026-08-01', '2026-09-30', NULL,         'Active',        'librarian_desk2'),
(13, 15, 15, '2026-09-01', '2026-10-01', NULL,         'Active',        'self_kiosk_02'),

-- Active Overdue Loans (Immediate Delinquency Risk)
(14, 5,  3,  '2026-08-10', '2026-08-24', NULL,         'Overdue',       'librarian_desk1'), -- ~29 days overdue
(15, 8,  1,  '2026-08-20', '2026-09-03', NULL,         'Overdue',       'self_kiosk_01'), -- ~19 days overdue
(16, 9,  8,  '2026-08-15', '2026-09-05', NULL,         'Overdue',       'librarian_desk2'), -- ~17 days overdue
(17, 13, 9,  '2026-08-18', '2026-09-08', NULL,         'Overdue',       'self_kiosk_01'), -- ~14 days overdue
(18, 19, 6,  '2026-08-25', '2026-09-08', NULL,         'Overdue',       'librarian_desk1'), -- ~14 days overdue

-- Declared Lost Asset Loan
(19, 20, 5,  '2026-05-10', '2026-05-24', '2026-09-10', 'Declared_Lost', 'librarian_desk1'),

-- Additional Active Regular Loan
(20, 6,  14, '2026-08-20', '2026-09-19', '2026-09-20', 'Returned',      'librarian_desk2');

-- ----------------------------------------------------------------------------
-- 9. SEED: overdue_fines (Financial Records & Slabs)
-- ----------------------------------------------------------------------------
INSERT INTO `overdue_fines` (`fine_id`, `loan_id`, `overdue_days`, `calculated_fine`, `waiver_amount`, `net_payable`, `payment_status`, `assessed_at`, `paid_at`) VALUES
-- Loan 6: UG (rate 1.00), 10 days: 7*1.00 + 3*1.50 = 11.50
(1, 6,  10, 11.50, 0.00,  11.50, 'Paid',   '2026-07-25 10:15:00', '2026-07-25 10:20:00'),

-- Loan 7: PG (rate 1.50), 19 days: 7*1.50 + 7*2.25 + 5*3.00 = 10.50 + 15.75 + 15.00 = 41.25
(2, 7,  19, 41.25, 5.00,  36.25, 'Paid',   '2026-07-20 14:30:00', '2026-07-21 09:00:00'),

-- Loan 8: UG (rate 1.00), 6 days: 6*1.00 = 6.00
(3, 8,  6,  6.00,  0.00,  6.00,  'Paid',   '2026-08-04 11:00:00', '2026-08-04 11:05:00'),

-- Loan 9: UG (rate 1.00), 13 days: 7*1.00 + 6*1.50 = 16.00
(4, 9,  13, 16.00, 0.00,  16.00, 'Unpaid', '2026-07-28 16:45:00', NULL),

-- Loan 19: Declared Lost Recovery Charge (Depreciated value + processing fee + overdue fine)
(5, 19, 109, 87.15, 0.00, 87.15, 'Unpaid', '2026-09-10 12:00:00', NULL);

-- ----------------------------------------------------------------------------
-- 10. SEED: book_reservations (FIFO Priority Queues for High-Demand Titles)
-- ----------------------------------------------------------------------------
INSERT INTO `book_reservations` (`reservation_id`, `title_id`, `patron_id`, `reservation_date`, `priority_queue_position`, `notification_sent_at`, `reservation_status`) VALUES
-- Priority Queue for Title 2 (Introduction to Algorithms - High Demand)
(1, 2, 1,  '2026-09-12 09:15:00', 1, '2026-09-20 10:00:00', 'Notified'),
(2, 2, 2,  '2026-09-14 11:30:00', 1, NULL,                 'Queued'),
(3, 2, 6,  '2026-09-18 14:00:00', 2, NULL,                 'Queued'),
(4, 2, 8,  '2026-09-20 16:45:00', 3, NULL,                 'Queued'),
(5, 2, 15, '2026-09-21 08:30:00', 4, NULL,                 'Queued'),

-- Priority Queue for Title 3 (AI: A Modern Approach)
(6, 3, 3,  '2026-09-15 10:00:00', 1, NULL,                 'Queued'),
(7, 3, 4,  '2026-09-17 12:15:00', 2, NULL,                 'Queued'),
(8, 3, 9,  '2026-09-19 15:20:00', 3, NULL,                 'Queued');

-- ----------------------------------------------------------------------------
-- 11. SEED: library_audit_logs (Immutable Audit Trail)
-- ----------------------------------------------------------------------------
INSERT INTO `library_audit_logs` (`log_id`, `copy_id`, `patron_id`, `action_type`, `details`, `logged_at`) VALUES
(1,  1,  1,  'CHECK_OUT',           'Book Copy ID #1 checked out by Patron ID #1 under Loan ID #1.', '2026-07-01 09:30:00'),
(2,  1,  1,  'CHECK_IN',            'Copy ID #1 returned by Patron ID #1 and returned to active circulation.', '2026-07-14 11:20:00'),
(3,  7,  3,  'CHECK_OUT',           'Book Copy ID #7 checked out by Patron ID #3 under Loan ID #6.', '2026-07-01 10:00:00'),
(4,  7,  3,  'FINE_ASSESSED',       'Tiered fine of $11.50 assessed on Loan ID #6 for 10 overdue day(s).', '2026-07-25 10:15:00'),
(5,  7,  3,  'FINE_PAID',           'Fine payment of $11.50 settled in full for Fine ID #1.', '2026-07-25 10:20:00'),
(6,  7,  3,  'CHECK_IN',            'Copy ID #7 returned by Patron ID #3 and returned to active circulation.', '2026-07-25 10:22:00'),
(7,  6,  1,  'RESERVATION_PROMOTED', 'Copy ID #6 held for Patron ID #1 via Reservation ID #1 (FIFO Priority 1).', '2026-09-20 10:00:00'),
(8,  20, 5,  'LOST_DEPRECIATED',    'Book Copy ID #20 declared Lost. Age: 5 yrs. Depreciated book value: $44.75, Admin processing fee: $15.00, Overdue fine: $27.40. Total recovery charge: $87.15', '2026-09-10 12:00:00');

-- Re-enable triggers for subsequent operational transactions
SET @DISABLE_TRIGGERS = 0;
