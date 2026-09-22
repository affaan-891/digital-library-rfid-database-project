# Digital Library Management & RFID Tiered Fine Engine

[![MySQL 8.0+](https://img.shields.io/badge/MySQL-8.0%2B-blue.svg?logo=mysql&logoColor=white)](https://dev.mysql.com/doc/)
[![Engine: InnoDB](https://img.shields.io/badge/Engine-InnoDB-orange.svg)](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html)
[![Normalization: 3NF](https://img.shields.io/badge/Normalization-3NF%20Verified-brightgreen.svg)](docs/ERD.md)
[![Transactions: ACID](https://img.shields.io/badge/Transactions-ACID%20Pessimistic%20Locking-purple.svg)](database/03_procedures.sql)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade, academic database system designed for university Computer Science and Software Engineering DBMS coursework, laboratory project defense, and semester viva examinations. 

This repository models an automated campus library circulation environment integrating **EPC Gen2 RFID physical item tracking**, **dynamic FIFO reservation priority queues**, **progressive overdue fine escalation slabs**, and **straight-line textbook depreciation recovery algorithms** wrapped in explicit ACID transactions.

---

## Repository Architecture

```
digital-library-rfid-database-project/
├── database/
│   ├── 01_schema.sql             # 11 3NF Normalized Tables, Constraints, Keys & Foreign Keys
│   ├── 02_triggers.sql           # Quota Enforcers, Anti-Double Checkout & Auto-Promotion Triggers
│   ├── 03_procedures.sql         # ACID Return Engine, Depreciation Engine & Aggregate Functions
│   ├── 04_views_and_queries.sql  # Risk Registers, Demand Turn-Ratio Views & 5 Complex Viva Queries
│   └── 05_seed_data.sql          # Academic Publishers, CS Textbooks, RFID Tags & Circulation Log
├── docs/
│   ├── ERD.md                    # Visual Mermaid.js Crow's Foot Diagram & Full Data Dictionary
│   └── VIVA_QUESTIONS.md         # 10 Tough Viva Voce Questions, Answers & Examiner Rubric
└── README.md                     # Project Documentation & Execution Guide
```

---

## Core Domain Capabilities

### 1. 3NF Normalized Schema & Physical Media Decoupling
- **Conceptual Work (`book_titles`) vs. Physical Media (`book_copies`)**: Separates catalog metadata (ISBN-13, edition, base replacement price) from physical copy circulation states, preventing 1NF and 2NF anomalies.
- **RFID UID & Optical Barcode Indexing**: Fast sub-millisecond point lookups on EPC Class 1 Gen 2 hexadecimal tags (`VARCHAR(50) UNIQUE`) and standard barcodes.
- **Many-to-Many Authorship Modeling**: Associative table `title_authors` tracks primary and co-author relationships cleanly.

### 2. Progressive Overdue Fine Slab Engine
Rather than naive flat daily charges, the engine enforces progressive delinquent escalation to incentivize rapid item returns, capped strictly at 100% of title replacement value:

| Overdue Duration | Tariff Tier | Rate Applied | Example (UG Rate: $1.00/day) |
|---|---|---|---|
| **Days 1 to 7** | Standard Grace / Early Delinquency | $\text{base\_rate} \times 1.00$ | $7 \times \$1.00 = \$7.00$ |
| **Days 8 to 14** | Escalation Tier | $\text{base\_rate} \times 1.50$ | $7 \times \$1.50 = \$10.50$ |
| **Days 15+** | Severe Delinquency Tier | $\text{base\_rate} \times 2.00$ | Days past $14 \times \$2.00$ |
| **Ceiling Cap** | Anti-Gouging Maximum | $100\%$ Base Replacement Cost | Capped at `bt.base_replacement_cost` |

### 3. Straight-Line Asset Depreciation Model (`sp_assess_lost_book_charge`)
When an issued textbook is declared lost by a student, the replacement fee is determined through equitable straight-line asset depreciation:
$$\text{Asset Age} = \max(0, \text{TIMESTAMPDIFF(YEAR, acquisition\_date, CURDATE())})$$
$$\text{Depreciated Value} = \text{base\_cost} \times \max(1.00 - (\text{Age} \times 0.10), 0.30)$$
$$\text{Total Invoice} = \text{Depreciated Value} + \$15.00\text{ (Admin Fee)} + \text{Accrued Overdue Fine}$$
- **30% Salvage Floor**: Ensures minimum asset value recovery regardless of textbook age.
- **ACID Transaction Isolation**: Row locks acquired via `FOR UPDATE` to prevent concurrent return conflicts.

### 4. Automated Multi-Copy Reservation Promotion
- Enforces an automated FIFO queue in `book_reservations`.
- When an active loan transitions to `'Returned'`, trigger `trg_auto_promote_reservation_on_return` automatically promotes the top queued patron (`priority_queue_position = 1`), transitions physical copy status to `'Reserved'`, timestamps `notification_sent_at`, and decrements subsequent queue positions.

---

## Database Installation & Setup Guide

### Prerequisites
- **MySQL Server 8.0+** or **MariaDB 10.5+**
- MySQL Command Line Client / MySQL Workbench / phpMyAdmin / DBeaver

### Option A: Command Line Client (Windows PowerShell / macOS / Linux)

```powershell
# Clone the repository
git clone https://github.com/affaan-891/digital-library-rfid-database-project.git
cd digital-library-rfid-database-project

# Connect to MySQL and run sequential installation scripts
mysql -u root -p -e "source database/01_schema.sql;"
mysql -u root -p -e "source database/02_triggers.sql;"
mysql -u root -p -e "source database/03_procedures.sql;"
mysql -u root -p -e "source database/04_views_and_queries.sql;"
mysql -u root -p -e "source database/05_seed_data.sql;"
```

### Option B: Single Command Pipeline

```powershell
Get-Content database/01_schema.sql, database/02_triggers.sql, database/03_procedures.sql, database/04_views_and_queries.sql, database/05_seed_data.sql | mysql -u root -p --default-character-set=utf8mb4
```

---

## Analytical Views & Queries Preview

### 1. Overdue Loans Risk Register View
```sql
SELECT 
    loan_id, 
    patron_name, 
    category_name, 
    title, 
    days_overdue, 
    progressive_fine_accrued 
FROM vw_overdue_loans_risk_register
ORDER BY days_overdue DESC;
```

### 2. Title Circulation Demand Metrics View
```sql
SELECT 
    title, 
    total_physical_copies, 
    currently_issued_copies, 
    pending_reservations_count, 
    circulation_turnover_ratio 
FROM vw_title_circulation_demand_metrics
ORDER BY circulation_turnover_ratio DESC;
```

### 3. Executing the Book Return Procedure
```sql
-- Process return for Copy ID #7 on current date
CALL sp_process_book_return(7, CURDATE(), @assessed_fine);
SELECT @assessed_fine AS fine_charged;
```

### 4. Assessing Lost Asset Recovery Charge
```sql
-- Declare Loan ID #14 as lost
CALL sp_assess_lost_book_charge(14, @recovery_invoice);
SELECT @recovery_invoice AS total_patron_liability;
```

---

## Entity Relationship Overview

See [docs/ERD.md](docs/ERD.md) for the complete 11-table Mermaid.js diagram and detailed data dictionary.

```
+---------------+        1:N        +---------------+        1:N        +---------------+
|  publishers   | ----------------> |  book_titles  | ----------------> |  book_copies  |
+---------------+                   +---------------+                   +---------------+
                                            |                                   |
                                            | 1:N                               | 1:N
                                            v                                   v
+-------------------+        1:N    +---------------+        1:N        +-------------------+
| patron_categories | ------------> |    patrons    | ----------------> | loan_transactions |
+-------------------+               +---------------+                   +-------------------+
                                            |                                   | 1:1
                                            | 1:N                               v
                                            v                           +-------------------+
                                    +---------------+                   |   overdue_fines   |
                                    |book_reservat's|                   +-------------------+
                                    +---------------+
```

---

## Viva Voce Preparation
Refer to [docs/VIVA_QUESTIONS.md](docs/VIVA_QUESTIONS.md) for comprehensive examiners' evaluation criteria, covering:
1. Procedural Fine Slab Computation vs. Generated Virtual Columns
2. Concurrency Control and Race Condition Mitigation in FIFO Reservation Queues
3. 3NF Decomposition Proofs and Anomaly Elimination
4. Straight-Line Depreciation Mathematics and Salvage Floor Integrity
5. RFID EPC Class 1 Gen 2 B-Tree Index Tuning
6. Window Functions (`DENSE_RANK()`) vs. Correlated Subqueries
7. Three-Valued Logic in Anti-Joins (`NOT EXISTS` vs. `NOT IN`)
8. Cascading Deletion vs. Audit Trail Preservation (`ON DELETE RESTRICT`)

---

## License
Distributed under the MIT License. See `LICENSE` for more information.
