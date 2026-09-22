# Entity Relationship Diagram (ERD) & Data Dictionary

## 1. Architectural Overview & Design Philosophy

The **Digital Library Management & RFID Tiered Fine Engine** database (`library_rfid_db`) is engineered to enforce strict relational discipline:
- **Third Normal Form (3NF) Compliance**: Non-key attributes are dependent solely on the primary key, whole key, and nothing but the key, preventing update, insertion, and deletion anomalies.
- **Physical vs. Conceptual Asset Decoupling**: Catalog metadata (`book_titles`, `publishers`, `authors`) is cleanly abstracted from physical media (`book_copies` with unique EPC Gen2 RFID UIDs and barcodes).
- **Automated Lifecycle Integrity**: Business rules (circulation limits, copy availability, progressive fine escalation, priority reservation queues) are defended at the engine layer through foreign keys, check constraints, and declarative triggers.

---

## 2. Mermaid.js Entity-Relationship Diagram (Crow's Foot Notation)

```mermaid
erDiagram
    PUBLISHERS ||--o{ BOOK_TITLES : "publishes (1:N)"
    BOOK_TITLES ||--|{ TITLE_AUTHORS : "authored_by (1:N)"
    AUTHORS ||--|{ TITLE_AUTHORS : "wrote (1:N)"
    BOOK_TITLES ||--o{ BOOK_COPIES : "instantiates (1:N)"
    BOOK_TITLES ||--o{ BOOK_RESERVATIONS : "receives_demand_for (1:N)"
    
    PATRON_CATEGORIES ||--o{ PATRONS : "classifies (1:N)"
    PATRONS ||--o{ LOAN_TRANSACTIONS : "borrows_under (1:N)"
    PATRONS ||--o{ BOOK_RESERVATIONS : "enqueues (1:N)"
    PATRONS ||--o{ LIBRARY_AUDIT_LOGS : "acted_upon (1:N)"

    BOOK_COPIES ||--o{ LOAN_TRANSACTIONS : "circulates_as (1:N)"
    BOOK_COPIES ||--o{ LIBRARY_AUDIT_LOGS : "subject_of (1:N)"

    LOAN_TRANSACTIONS ||--o| OVERDUE_FINES : "generates_penalty (1:1)"

    PUBLISHERS {
        int publisher_id PK "Auto Increment"
        string publisher_name UK "Unique Publisher Name"
        string contact_email "Official Contact Email"
        string country "Country of Incorporation"
        string website "Web Portal URL"
        timestamp created_at "Record Creation Timestamp"
    }

    BOOK_TITLES {
        int title_id PK "Auto Increment"
        char isbn UK "ISBN-13 (Unique)"
        string title "Work Title"
        int publisher_id FK "References publishers(publisher_id)"
        int edition "Edition Number"
        int publication_year "Year (1800 - 2026)"
        decimal base_replacement_cost "Catalog Replacement Price"
        timestamp created_at "Record Creation Timestamp"
    }

    AUTHORS {
        int author_id PK "Auto Increment"
        string full_name "Full Author Name"
        string email UK "Author Email Address"
        text bio "Academic Biography"
        timestamp created_at "Record Creation Timestamp"
    }

    TITLE_AUTHORS {
        int title_id PK_FK "References book_titles(title_id)"
        int author_id PK_FK "References authors(author_id)"
        boolean is_primary_author "Primary Author Flag"
    }

    BOOK_COPIES {
        int copy_id PK "Auto Increment"
        int title_id FK "References book_titles(title_id)"
        string rfid_tag_uid UK "RFID EPC Gen2 Tag UID"
        string barcode UK "Optical Barcode"
        date acquisition_date "Asset Acquisition Date"
        enum condition_grade "New, Good, Fair, Damaged, Lost"
        enum status "Available, Issued, Reserved, Under_Binding"
        timestamp created_at "Record Creation Timestamp"
    }

    PATRON_CATEGORIES {
        int category_id PK "Auto Increment"
        enum category_name UK "Undergraduate, Postgraduate, Faculty, Researcher"
        int max_borrow_limit "Concurrent Loan Quota"
        int standard_loan_days "Permitted Loan Duration"
        decimal daily_fine_rate "Base Daily Fine Rate"
        timestamp created_at "Record Creation Timestamp"
    }

    PATRONS {
        int patron_id PK "Auto Increment"
        string membership_number UK "Campus Card/Student ID"
        string full_name "Patron Full Name"
        int category_id FK "References patron_categories(category_id)"
        string email UK "Campus Email Address"
        string phone UK "Contact Number"
        enum account_status "Active, Suspended, Expired"
        date enrolled_date "Registration Date"
        timestamp created_at "Record Creation Timestamp"
    }

    LOAN_TRANSACTIONS {
        int loan_id PK "Auto Increment"
        int copy_id FK "References book_copies(copy_id)"
        int patron_id FK "References patrons(patron_id)"
        date issue_date "Checkout Date"
        date due_date "Scheduled Return Date"
        date return_date "Actual Return Date (NULL while active)"
        enum loan_status "Active, Returned, Overdue, Declared_Lost"
        string checked_out_by "Operator ID / Kiosk Identifier"
        timestamp created_at "Transaction Timestamp"
        timestamp updated_at "Update Timestamp"
    }

    OVERDUE_FINES {
        int fine_id PK "Auto Increment"
        int loan_id FK_UK "References loan_transactions(loan_id) - 1:1"
        int overdue_days "Days Past Due"
        decimal calculated_fine "Progressive Slab Fine"
        decimal waiver_amount "Authorized Waiver / Discount"
        decimal net_payable "Final Payable Liability"
        enum payment_status "Unpaid, Partially_Paid, Paid, Waived"
        timestamp assessed_at "Fine Assessment Timestamp"
        timestamp paid_at "Settlement Timestamp"
    }

    BOOK_RESERVATIONS {
        int reservation_id PK "Auto Increment"
        int title_id FK "References book_titles(title_id)"
        int patron_id FK "References patrons(patron_id)"
        datetime reservation_date "Enqueue Timestamp"
        int priority_queue_position "FIFO Sequence Order"
        datetime notification_sent_at "Availability Notice Timestamp"
        enum reservation_status "Queued, Notified, Fulfilled, Cancelled, Expired"
    }

    LIBRARY_AUDIT_LOGS {
        int log_id PK "Auto Increment"
        int copy_id FK "References book_copies(copy_id) NULL on delete"
        int patron_id FK "References patrons(patron_id) NULL on delete"
        enum action_type "CHECK_OUT, CHECK_IN, FINE_ASSESSED, FINE_PAID, LOST_DEPRECIATED, RESERVATION_PROMOTED"
        text details "Comprehensive Event Description"
        timestamp logged_at "Event Timestamp"
    }
```

---

## 3. Comprehensive Data Dictionary

### Table 1: `publishers`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `publisher_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Surrogate primary identifier |
| `publisher_name` | `VARCHAR(150)` | `UNIQUE` | No | Name of publisher house |
| `contact_email` | `VARCHAR(100)` | `CHECK (%@%.%)` | No | Official inquiries email |
| `country` | `VARCHAR(60)` | None | No | Geographic headquarters |
| `website` | `VARCHAR(255)` | None | Yes | Official web address |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Record creation timestamp |

### Table 2: `book_titles`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `title_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Catalog work identifier |
| `isbn` | `CHAR(13)` | `UNIQUE` | No | Standard 13-digit International Book Number |
| `title` | `VARCHAR(255)` | None | No | Title of academic work |
| `publisher_id` | `INT` | `FOREIGN KEY` (`ON DELETE RESTRICT`) | No | Reference to `publishers.publisher_id` |
| `edition` | `INT` | `CHECK (edition > 0)` | No | Edition number |
| `publication_year`| `INT` | `CHECK (1800 TO 2026)` | No | Year of publication |
| `base_replacement_cost` | `DECIMAL(8,2)` | `CHECK (> 0)` | No | Replacement baseline cost (USD) |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Ingestion timestamp |

### Table 3: `authors`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `author_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Author surrogate primary key |
| `full_name` | `VARCHAR(100)` | None | No | Full legal/scholarly name |
| `email` | `VARCHAR(100)` | `UNIQUE`, `CHECK (%@%.%)` | No | Primary author contact email |
| `bio` | `TEXT` | None | Yes | Academic background and credentials |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Ingestion timestamp |

### Table 4: `title_authors` (Associative Entity)
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `title_id` | `INT` | `PRIMARY KEY`, `FK` (`ON DELETE CASCADE`) | No | Reference to `book_titles.title_id` |
| `author_id` | `INT` | `PRIMARY KEY`, `FK` (`ON DELETE RESTRICT`)| No | Reference to `authors.author_id` |
| `is_primary_author`| `BOOLEAN` | `DEFAULT TRUE` | No | Indicates principal/lead author |

### Table 5: `book_copies`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `copy_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Physical inventory copy ID |
| `title_id` | `INT` | `FOREIGN KEY` (`ON DELETE RESTRICT`) | No | Reference to `book_titles.title_id` |
| `rfid_tag_uid` | `VARCHAR(50)` | `UNIQUE`, Index | No | 96-bit/128-bit EPC Gen2 RFID hexadecimal UID |
| `barcode` | `VARCHAR(50)` | `UNIQUE`, Index | No | Fallback optical barcode string |
| `acquisition_date` | `DATE` | None | No | Date acquired by university library |
| `condition_grade` | `ENUM` | `'New','Good','Fair','Damaged','Lost'` | No | Physical asset wear and integrity |
| `status` | `ENUM` | `'Available','Issued','Reserved','Under_Binding'` | No | Immediate circulation status |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | System registry timestamp |

### Table 6: `patron_categories`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `category_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Category surrogate ID |
| `category_name` | `ENUM` | `UNIQUE` (`'Undergraduate','Postgraduate','Faculty','Researcher'`) | No | Patron institutional classification |
| `max_borrow_limit` | `INT` | `CHECK (> 0)` | No | Maximum simultaneous item checkout quota |
| `standard_loan_days`| `INT` | `CHECK (> 0)` | No | Default duration of loan before overdue |
| `daily_fine_rate` | `DECIMAL(6,2)` | `CHECK (>= 0)` | No | Base overdue fine tariff per day |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Policy creation timestamp |

### Table 7: `patrons`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `patron_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Patron primary key |
| `membership_number`| `VARCHAR(20)` | `UNIQUE`, Index | No | Institutional card or registration ID |
| `full_name` | `VARCHAR(100)` | None | No | Legal patron name |
| `category_id` | `INT` | `FOREIGN KEY` (`ON DELETE RESTRICT`) | No | Reference to `patron_categories.category_id` |
| `email` | `VARCHAR(100)` | `UNIQUE`, `CHECK (%@%.%)` | No | Campus email address |
| `phone` | `VARCHAR(25)` | `UNIQUE` | No | Contact phone number |
| `account_status` | `ENUM` | `'Active','Suspended','Expired'` | No | Circulation eligibility state |
| `enrolled_date` | `DATE` | None | No | Initial registration date |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Account creation timestamp |

### Table 8: `loan_transactions`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `loan_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Circulation transaction ID |
| `copy_id` | `INT` | `FOREIGN KEY` (`ON DELETE RESTRICT`) | No | Reference to `book_copies.copy_id` |
| `patron_id` | `INT` | `FOREIGN KEY` (`ON DELETE RESTRICT`) | No | Reference to `patrons.patron_id` |
| `issue_date` | `DATE` | None | No | Date book was checked out |
| `due_date` | `DATE` | `CHECK (due_date >= issue_date)` | No | Scheduled return deadline |
| `return_date` | `DATE` | `CHECK (return_date >= issue_date)` | Yes | Actual return date |
| `loan_status` | `ENUM` | `'Active','Returned','Overdue','Declared_Lost'` | No | Current transaction status |
| `checked_out_by` | `VARCHAR(50)` | None | No | Desk clerk or self-checkout terminal ID |
| `created_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Checkout timestamp |
| `updated_at` | `TIMESTAMP` | `ON UPDATE CURRENT_TIMESTAMP` | No | Status update timestamp |

### Table 9: `overdue_fines`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `fine_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Fine invoice primary key |
| `loan_id` | `INT` | `FOREIGN KEY`, `UNIQUE` (1-to-1) | No | Reference to `loan_transactions.loan_id` |
| `overdue_days` | `INT` | `CHECK (>= 0)` | No | Total calendar days overdue |
| `calculated_fine` | `DECIMAL(8,2)` | `CHECK (>= 0)` | No | Progressive slab fine sum |
| `waiver_amount` | `DECIMAL(8,2)` | `CHECK (waiver <= calculated_fine)` | No | Authorized reduction / administrative discount |
| `net_payable` | `DECIMAL(8,2)` | `CHECK (>= 0)` | No | Final outstanding obligation |
| `payment_status` | `ENUM` | `'Unpaid','Partially_Paid','Paid','Waived'` | No | Settlement state |
| `assessed_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Date penalty was recorded |
| `paid_at` | `TIMESTAMP` | None | Yes | Timestamp of financial settlement |

### Table 10: `book_reservations`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `reservation_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Reservation ticket identifier |
| `title_id` | `INT` | `FOREIGN KEY` (`ON DELETE CASCADE`) | No | Reference to requested `book_titles.title_id` |
| `patron_id` | `INT` | `FOREIGN KEY` (`ON DELETE CASCADE`) | No | Reference to enqueued `patrons.patron_id` |
| `reservation_date` | `DATETIME` | `DEFAULT CURRENT_TIMESTAMP` | No | Timestamp of reservation submission |
| `priority_queue_position`| `INT` | `CHECK (> 0)` | No | Relative priority queue ordinal (1 = next in line) |
| `notification_sent_at` | `DATETIME` | None | Yes | Notification broadcast timestamp |
| `reservation_status` | `ENUM` | `'Queued','Notified','Fulfilled','Cancelled','Expired'` | No | Current queue state |

### Table 11: `library_audit_logs`
| Column Name | Data Type | Key / Constraint | Nullable | Description & Domain |
|---|---|---|---|---|
| `log_id` | `INT` | `PRIMARY KEY`, `AUTO_INCREMENT` | No | Sequential log sequence ID |
| `copy_id` | `INT` | `FOREIGN KEY` (`ON DELETE SET NULL`)| Yes | Associated physical asset |
| `patron_id` | `INT` | `FOREIGN KEY` (`ON DELETE SET NULL`)| Yes | Associated user |
| `action_type` | `ENUM` | `'CHECK_OUT','CHECK_IN','FINE_ASSESSED','FINE_PAID','LOST_DEPRECIATED','RESERVATION_PROMOTED'` | No | Event category |
| `details` | `TEXT` | None | No | Detailed description and delta values |
| `logged_at` | `TIMESTAMP` | `DEFAULT CURRENT_TIMESTAMP` | No | Tamper-evident occurrence timestamp |

---

## 4. Normalization Audit & 3NF Proof

### First Normal Form (1NF)
1. **Atomic Values**: Every cell contains a single scalar value. ISBNs, RFID UIDs, author names, and emails are discrete attributes.
2. **Repeating Groups Eliminated**: Multi-author publications are split into an associative table `title_authors`. Multiple physical copies are modeled as discrete records in `book_copies` rather than CSV lists on titles.

### Second Normal Form (2NF)
1. **Full Functional Dependency**: All non-key attributes are fully functionally dependent on the primary key.
2. In composite key tables (`title_authors`), the attribute `is_primary_author` depends on the combination `(title_id, author_id)`. Neither `title_id` nor `author_id` alone determines whether that specific author is primary on that specific book.

### Third Normal Form (3NF)
1. **Transitive Dependency Elimination**: No non-prime attribute depends transitively on another non-prime attribute.
2. Example 1: In `patrons`, attributes `category_name`, `max_borrow_limit`, and `daily_fine_rate` are intentionally NOT stored. Storing them in `patrons` would create the transitive dependency `patron_id -> category_id -> daily_fine_rate`. Instead, `patrons` stores only `category_id`, pointing to `patron_categories`.
3. Example 2: In `book_copies`, book details (`title`, `isbn`, `base_replacement_cost`) are not stored. Storing them would cause `copy_id -> title_id -> base_replacement_cost`. This is segregated into `book_titles`.
