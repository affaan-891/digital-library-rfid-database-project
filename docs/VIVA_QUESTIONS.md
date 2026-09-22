# Technical Viva Voce Defense Guide & Examiner Rubric

This document prepares students and software engineers for university viva defense, database evaluation panels, and technical interviews. It contains 10 rigorous viva questions spanning database internals, relational algebra, concurrency control, and academic business logic.

---

### Question 1: Progressive Tiered Fine Slab Algorithm
**Examiner Prompt:** *"Why did you implement the progressive overdue fine calculation inside a stored procedure rather than computing it on-the-fly via a simple generated virtual column in the table?"*

**Concept Tested:** Procedural Business Logic vs. Deterministic Functional Columns, Historical Liability Freezing, Temporal Mutation.

**Model Answer:**
> "A generated virtual column in MySQL must be deterministic and based solely on attributes present in the immediate row (or constant expressions). Overdue fine calculation in an academic library is inherently temporal and non-linear:
> 1. **Temporal Mutation Risk:** If calculated as `(CURDATE() - due_date) * rate`, the fine would change every single day even after a book has been physically returned unless an explicit snapshot is taken.
> 2. **Piecewise Tiered Slabs:** The tariff follows non-linear slabs:
>    - Days 1 to 7: $1.0 \times \text{base rate}$
>    - Days 8 to 14: $1.5 \times \text{base rate}$
>    - Days 15+: $2.0 \times \text{base rate}$
>    - Upper ceiling: $\min(\text{calculated fine}, \text{base replacement cost})$
> 3. **Financial Snapshot Immutability:** Once a book is returned or declared lost, the assessed fine must become a frozen, immutable historical receivable in `overdue_fines` that can withstand subsequent patron category rate changes or book price fluctuations. Encapsulating this logic in `sp_process_book_return` ensures atomic computation, cap enforcement, and immutable persistence."

---

### Question 2: FIFO Priority Queue Rebalancing & Race Conditions
**Examiner Prompt:** *"When a popular title is returned, your trigger promotes the top reservation from 'Queued' to 'Notified' and decrements priority positions. How does your schema prevent race conditions if two copies of the same title are returned simultaneously?"*

**Concept Tested:** Concurrency Control, Lock Contention, Serializability, Trigger Execution Context.

**Model Answer:**
> "In high-throughput environments, two concurrent return transactions executing `AFTER UPDATE` triggers could read the same top queued reservation if not serialized:
> 1. In `sp_process_book_return`, we initiate an explicit ACID transaction with `START TRANSACTION;` and acquire an exclusive row-level write lock (`SELECT ... FOR UPDATE`) on the loan transaction and book copy.
> 2. In MySQL InnoDB, row updates on `book_reservations` serialize on the primary key and index locks (`idx_res_queue`). The first transaction to update reservation status locks that row.
> 3. Furthermore, our unique constraint `UNIQUE(title_id, patron_id, reservation_status)` prevents the same patron from being double-queued or double-notified for the same catalog title.
> 4. To eliminate all possible phantom queue reads under heavy kiosk concurrency, the queue promotion logic can be placed directly within the stored procedure using `SELECT reservation_id ... FOR UPDATE SKIP LOCKED` or explicit row locking on the `book_reservations` queue table."

---

### Question 3: Physical Media vs. Conceptual Title Normalization
**Examiner Prompt:** *"Why did you separate `book_titles` from `book_copies`? Why not store `rfid_tag_uid` and `barcode` directly inside `book_titles`?"*

**Concept Tested:** 3NF Normalization, 1-to-N Entity Decomposition, Update/Insertion Anomalies.

**Model Answer:**
> "Storing physical identifiers like `rfid_tag_uid` or `barcode` in `book_titles` violates First and Second Normal Forms:
> 1. **1-to-Many Physical Cardinality:** A university library frequently holds 5 to 20 identical physical copies of a single textbook (e.g., Cormen's *Introduction to Algorithms*). If stored in a single table, we would either have repeating columns (`rfid_tag_1`, `rfid_tag_2` — violating 1NF) or duplicate title metadata for each copy (violating 2NF/3NF).
> 2. **Elimination of Update Anomalies:** If the replacement price, title name, or publisher of a textbook changes, updating 20 distinct copy rows risks data inconsistency. With our decoupled design, catalog metadata exists once in `book_titles`, and physical inventory state (`condition_grade`, `status`, `rfid_tag_uid`, `acquisition_date`) resides independently in `book_copies` referencing `title_id`."

---

### Question 4: Straight-Line Asset Depreciation Model
**Examiner Prompt:** *"Explain the mathematical and relational modeling behind your `sp_assess_lost_book_charge` procedure. How does it handle aging textbooks?"*

**Concept Tested:** Asset Depreciation Relational Modeling, Salvage Floor Bounds, Composite Fee Assessment.

**Model Answer:**
> "Textbooks undergo wear, obsolescence, and technological aging. When a patron loses a book, charging full original catalog price for a 5-year-old book is academically inequitable, while charging zero creates moral hazard. We implement standard straight-line depreciation:
> $$\text{Age in Years} = \max(0, \text{TIMESTAMPDIFF(YEAR, acquisition\_date, CURDATE())})$$
> $$\text{Depreciation Rate} = \text{Age} \times 10\%$$
> $$\text{Residual Factor} = \max(1.00 - \text{Depreciation Rate}, 0.30)$$
> - **Salvage Floor (30%):** Ensures that regardless of age, the library recovers at least 30% of baseline replacement value for salvage value and binding.
> - **Administrative Processing Surcharge:** Adds a fixed $15.00 overhead to cover catalog re-indexing, RFID reprogramming, and acquisitions clerk labor.
> - **Overdue Fine Integration:** Incorporates progressive overdue charges up to the loss date, capped at 100% of title cost.
> All components are aggregated and atomically posted into `overdue_fines` while marking `book_copies.condition_grade = 'Lost'`."

---

### Question 5: RFID Tag Collision and UID Physical Tracking
**Examiner Prompt:** *"How does the database handle RFID UID data types, index scanning, and potential duplicates during bulk shelf inventory scanning?"*

**Concept Tested:** Hexadecimal Character Encoding, B-Tree Index Selectivity, Unique Constraints, Physical Collision Mitigation.

**Model Answer:**
> "1. **Data Type Selection:** RFID chips in libraries adhere to EPC Class 1 Gen 2 (ISO 18000-6C) or ISO 15693 (HF 13.56 MHz), producing 96-bit or 128-bit hexadecimal identifiers (24 to 32 characters). We assign `VARCHAR(50)` with `UNIQUE` constraint and `utf8mb4_bin` or indexed collation.
> 2. **Index Selectivity:** The unique B-Tree index on `rfid_tag_uid` gives $O(\log N)$ point-lookup performance. When an RFID shelf wand or checkout portal reads 40 tags simultaneously, the anti-collision protocol in the reader layer delivers discrete UIDs, which the database resolves in sub-millisecond lookups.
> 3. **Composite Indexing:** For real-time inventory queries (e.g., checking if an item is available on shelf), we provide the composite index `(title_id, status, condition_grade)` on `book_copies`, allowing the query planner to satisfy multi-column availability predicates via index range scans without touching heap storage."

---

### Question 6: Correlated Subquery vs. Window Function
**Examiner Prompt:** *"In Query 4, why use the window function `DENSE_RANK() OVER (PARTITION BY ...)` instead of a correlated `COUNT(DISTINCT ...)` subquery?"*

**Concept Tested:** Analytical Processing, Query Execution Cost, Algorithmic Time Complexity ($O(N \log N)$ vs. $O(N^2)$).

**Model Answer:**
> "A correlated subquery to compute rank compares each row against all other rows matching the outer partition:
> - **Correlated Subquery:** Forces the query engine to execute a nested loop over the table for every tuple, yielding $O(N^2)$ time complexity.
> - **Window Function (`DENSE_RANK()`):** The query optimizer performs a single scan, groups tuples into partition buckets, sorts each partition in memory or temporary disk using an efficient sort algorithm ($O(N \log N)$), and computes ranks sequentially in a single pass.
> Window functions prevent redundant table scans and minimize temporary tablespace I/O, which is essential for analytical university dashboards."

---

### Question 7: Anti-Join Pattern: `NOT EXISTS` vs. `NOT IN` with NULLs
**Examiner Prompt:** *"In Query 2, why did you use `WHERE NOT EXISTS (...)` rather than `WHERE patron_id NOT IN (SELECT patron_id FROM loan_transactions)`?"*

**Concept Tested:** Three-Valued Logic in SQL (`TRUE`, `FALSE`, `UNKNOWN`), Nullability Trap, Optimizer Transformation.

**Model Answer:**
> "The classic SQL pitfall with `NOT IN` lies in ANSI SQL Three-Valued Logic:
> - If the subquery `SELECT patron_id FROM loan_transactions` contains even a single `NULL` value, the expression `patron_id NOT IN (...)` evaluates to `UNKNOWN` (neither `TRUE` nor `FALSE`) for every outer row. As a consequence, the query returns **0 results**, creating a silent logical bug.
> - In contrast, `NOT EXISTS` evaluates whether the correlated subquery returns at least one tuple. It operates on boolean truth values and is impervious to `NULL` column values within the subquery.
> - Modern MySQL 8.0 optimizers transform `NOT EXISTS` into an efficient Anti-Semi-Join plan (using Left Hash Join or Single-Pass Index Anti-Join), skipping scans as soon as a single match is discovered."

---

### Question 8: Foreign Key Action Safety: `ON DELETE RESTRICT` vs. `CASCADE`
**Examiner Prompt:** *"Why did you use `ON DELETE RESTRICT` for `loan_transactions` referencing `patrons`, but `ON DELETE CASCADE` for `title_authors` referencing `book_titles`?"*

**Concept Tested:** Referential Integrity, Regulatory Compliance, Financial Audit Trails, Orphan Records.

**Model Answer:**
> "Referential actions must match legal and operational data lifetimes:
> 1. **Financial & Operational Audit Integrity (`RESTRICT`):** If a student withdraws from university, deleting their patron record must NOT cascade into deleting their loan history or unpaid fines. Doing so would destroy the audit trail, falsify overdue receivables, and cause accounting discrepancy. Therefore, `ON DELETE RESTRICT` prevents deletion of any patron who has past transactions.
> 2. **Associative / Auxiliary Entities (`CASCADE`):** The `title_authors` table is purely an associative bridge table. If a conceptual catalog title is officially expunged from the catalog, its junction entries have no meaning and can be purged automatically with `ON DELETE CASCADE` without compromising audit safety."

---

### Question 9: Transaction Isolation & ACID Compliance
**Examiner Prompt:** *"What could go wrong if `sp_process_book_return` ran under the `READ UNCOMMITTED` transaction isolation level?"*

**Concept Tested:** Transaction Isolation Levels, Dirty Reads, Lost Updates, Financial Inconsistency.

**Model Answer:**
> "Under `READ UNCOMMITTED` (the lowest ANSI SQL isolation level):
> 1. **Dirty Reads:** A concurrent cashier session could read a partially calculated fine before the transaction commits. If the return transaction subsequently encounters an error and rolls back, the patron might pay for a fine that technically never existed in the database.
> 2. **Lost Updates & Phantom Reservation Allocation:** If two librarians check in books for the same title concurrently, both might observe the same queue head (`priority_queue_position = 1`), causing both physical copies to be held for the same student while the second queued student is starved.
> By running under MySQL's default `REPEATABLE READ` (or `READ COMMITTED`) with explicit pessimistic row locks (`FOR UPDATE`), we guarantee strict serializability of loan state changes."

---

### Question 10: Multi-Column Composite Index Ordering Rule
**Examiner Prompt:** *"You created an index on `book_copies(title_id, status, condition_grade)`. Would a query filtering only on `condition_grade = 'Good'` use this index efficiently?"*

**Concept Tested:** Leftmost Prefix Rule of B-Tree Indexes, Index Skipping, Full Index Scan vs. Range Scan.

**Model Answer:**
> "No, it would not be able to perform an index range scan due to the **Leftmost Prefix Rule** of B-Tree indexes:
> - A composite B-Tree index is sorted hierarchically: first by `title_id`, then within each `title_id` by `status`, and finally within each status by `condition_grade`.
> - A query specifying only `condition_grade = 'Good'` lacks the leading columns (`title_id` and `status`). The database engine cannot jump directly to a range in the tree.
> - While MySQL 8.0 introduced *Index Skip Scan* (which can conceptually jump across distinct leading prefixes if the cardinality of leading columns is very low), it is far less efficient than a direct index seek. If filtering by `condition_grade` alone is a primary access path, an independent single-column index on `condition_grade` must be constructed."
