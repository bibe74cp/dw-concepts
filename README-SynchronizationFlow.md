# Landing Zone Synchronization Flow - Technical Documentation

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [SSIS Package Structure](#ssis-package-structure)
- [Synchronization Steps](#synchronization-steps)
- [Implementation Patterns](#implementation-patterns)
- [Error Handling](#error-handling)
- [Performance Optimization](#performance-optimization)
- [Examples](#examples)
- [Best Practices](#best-practices)
- [Monitoring and Logging](#monitoring-and-logging)

## Overview

This document describes the technical implementation of the **synchronization flow** that loads data from source systems into the Landing zone using **SQL Server Integration Services (SSIS)**. Each Landing table has a dedicated SSIS package that implements a consistent, repeatable pattern for detecting and applying changes.

### Purpose

The synchronization flow ensures that:
- Landing tables are faithful replicas of source tables
- Changes are detected efficiently using hash-based comparison
- All changes are tracked with temporal metadata
- Deleted records are handled with soft-delete pattern
- The process is idempotent and can be safely retried

### Design Principles

1. **Package-per-Table**: Each Landing table has its own SSIS package
2. **Hash-Based CDC**: Changes detected by comparing SHA256 hashes
3. **Three-Way Merge**: Handle inserts, updates, and deletes in a single execution
4. **Idempotent**: Running the same package multiple times produces the same result
5. **Atomic**: Each synchronization is a single transaction
6. **Auditable**: Complete logging of all operations

## Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      Source System                              │
│                   (ERP, Salesforce, MES)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Step 1: Extract & Hash     │
              │   SELECT with HASHBYTES()    │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Step 2: Conditional Split  │
              │   Route based on existence   │
              │   and hash comparison        │
              └──────────────┬───────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌────────┐         ┌────────┐         ┌────────┐
    │ INSERT │         │ UPDATE │         │  SKIP  │
    │  New   │         │Changed │         │No Chg  │
    └────────┘         └────────┘         └────────┘
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Step 3: Soft Delete        │
              │   Mark missing as deleted    │
              └──────────────┬───────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │   Audit Logging              │
              │   Record metrics & status    │
              └──────────────────────────────┘
```

### Data Flow Components

```
Source → Data Flow Task → Destination
         │
         ├─ OLE DB Source (Extract with Hash)
         ├─ Lookup Transformation (Check Existence)
         ├─ Conditional Split (Route by Hash)
         ├─ OLE DB Command (Update Changed)
         ├─ OLE DB Destination (Insert New)
         └─ Execute SQL Task (Soft Delete)
```

## SSIS Package Structure

### Package Variables

Each SSIS package defines the following variables:

| Variable | Type | Purpose | Example |
|----------|------|---------|---------|
| `SourceServer` | String | Source database server | `ERP_PROD_SERVER` |
| `SourceDatabase` | String | Source database name | `ERP_Production` |
| `SourceSchema` | String | Source schema name | `dbo` |
| `SourceTable` | String | Source table name | `Customer` |
| `LandingSchema` | String | Landing schema name | `ERP` |
| `LandingTable` | String | Landing table name | `Customer` |
| `HashColumns` | String | Columns to hash | `CustomerName,VAT` |
| `PKColumns` | String | Primary key columns | `CompanyId,CustomerId` |
| `RecordsInserted` | Int32 | Count of inserted records | 0 |
| `RecordsUpdated` | Int32 | Count of updated records | 0 |
| `RecordsDeleted` | Int32 | Count of deleted records | 0 |
| `ExecutionStart` | DateTime | Package start time | `2026-05-21 10:00:00` |

### Connection Managers

1. **Source Connection**: OLE DB connection to source system (read-only)
2. **Landing Connection**: OLE DB connection to Landing database (read-write)
3. **Audit Connection**: OLE DB connection for logging (optional, can use Landing)

### Package Control Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Control Flow                                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. [Set Variables] (Script Task)                          │
│     ↓                                                       │
│  2. [Truncate Staging] (Execute SQL Task)                  │
│     ↓                                                       │
│  3. [Extract & Load] (Data Flow Task) ──────┐              │
│     ↓                                        │              │
│  4. [Soft Delete Missing] (Execute SQL Task) │              │
│     ↓                                        │              │
│  5. [Log Execution] (Execute SQL Task)       │              │
│     ↓                                        │              │
│  6. [Cleanup Staging] (Execute SQL Task)     │              │
│                                              │              │
│  On Error: [Log Error] (Execute SQL Task) ←─┘              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Synchronization Steps

### Step 1: Extract from Source with Hash Calculation

**Purpose**: Read source data and calculate hash for change detection

**Implementation**: OLE DB Source component with dynamic SQL query

**SQL Query Pattern**:
```sql
-- Dynamic query generated from package variables
SELECT 
    -- Primary Key Columns
    CompanyId,
    CustomerId,
    
    -- Calculated Hash (ChangeHashKey)
    HASHBYTES('SHA2_256', 
        CONCAT(
            ISNULL(CustomerName, ''), '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    
    -- Business Columns
    CustomerName,
    VAT

FROM [ERP].[dbo].[Customer]
WHERE 1=1  -- Optional: add incremental filter for very large tables
```

**Key Points**:
- Hash is calculated at the source to minimize data transfer
- Use `ISNULL()` to handle NULL values consistently
- Use delimiter (`|`) to avoid hash collisions
- Convert all data types to string before hashing
- Only include columns that exist in Landing table

**Performance Consideration**:
```sql
-- For very large tables (100M+ rows), add filter
-- Example: incremental load based on ModifiedDate
WHERE ModifiedDate >= DATEADD(DAY, -7, GETDATE())

-- Or use change tracking if available
WHERE CHANGE_TRACKING_VERSION >= @LastSyncVersion
```

### Step 2: Conditional Split and Routing

**Purpose**: Route records to appropriate destinations based on existence and change detection

**Implementation**: Data Flow components

#### 2.1 Lookup Transformation

**Configuration**:
- **Lookup Table**: `Landing.ERP.Customer`
- **Join Columns**: Primary key columns (`CompanyId`, `CustomerId`)
- **Return Columns**: `ChangeHashKey`, `IsDeleted`
- **No Match Output**: New records (route to INSERT)
- **Match Output**: Existing records (route to Conditional Split)

**Cache Mode**:
- **Full Cache**: For small dimensions (< 1M rows) - fastest
- **Partial Cache**: For medium tables (1M-10M rows) - balanced
- **No Cache**: For very large tables (> 10M rows) - memory efficient

**Lookup Query**:
```sql
SELECT 
    CompanyId,
    CustomerId,
    ChangeHashKey,
    IsDeleted
FROM [Landing].[ERP].[Customer]
```

#### 2.2 Conditional Split Transformation

**Purpose**: Separate matched records into changed vs. unchanged

**Split Conditions**:

| Output Name | Condition | Action |
|-------------|-----------|--------|
| `Changed` | `Source.ChangeHashKey != Landing.ChangeHashKey` | Route to UPDATE |
| `Unchanged` | `Source.ChangeHashKey == Landing.ChangeHashKey` | No action (ignore) |

**Expression Syntax** (SSIS):
```
-- Changed Records Output
[Source_ChangeHashKey] != [Landing_ChangeHashKey]

-- Unchanged Records (Default Output)
-- No condition needed - catches all non-changed records
```

#### 2.3 Data Flow Routing

**Three Paths**:

1. **No Match Output from Lookup** → OLE DB Destination (INSERT)
2. **Changed Output from Conditional Split** → OLE DB Command (UPDATE)
3. **Unchanged Output from Conditional Split** → Row Count (metrics only, no action)

### Step 2.4: INSERT New Records

**Component**: OLE DB Destination

**Destination Table**: `[Landing].[ERP].[Customer]`

**Column Mappings**:
```
Source Column          → Destination Column
─────────────────────────────────────────────
CompanyId              → CompanyId
CustomerId             → CustomerId
ChangeHashKey          → ChangeHashKey
CustomerName           → CustomerName
VAT                    → VAT
CURRENT_TIMESTAMP      → InsertDatetime
CURRENT_TIMESTAMP      → UpdateDatetime
0 (constant)           → IsDeleted
```

**Derived Column Transformation** (before INSERT):
```
Column Name       Expression                      Data Type
─────────────────────────────────────────────────────────────
InsertDatetime    GETDATE()                       DT_DBTIMESTAMP
UpdateDatetime    GETDATE()                       DT_DBTIMESTAMP
IsDeleted         (DT_BOOL)0                      DT_BOOL
```

**Insert Query** (generated by destination):
```sql
INSERT INTO [Landing].[ERP].[Customer]
(
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    CustomerName,
    VAT
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
```

### Step 2.5: UPDATE Changed Records

**Component**: OLE DB Command

**Update Query**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    ChangeHashKey = ?,
    UpdateDatetime = CURRENT_TIMESTAMP,
    CustomerName = ?,
    VAT = ?
WHERE 
    CompanyId = ?
    AND CustomerId = ?
```

**Parameter Mapping** (order matters):
```
Parameter  Source Column      Type
────────────────────────────────────
Param_0    ChangeHashKey      BINARY(32)
Param_1    CustomerName       NVARCHAR(100)
Param_2    VAT                NVARCHAR(20)
Param_3    CompanyId          INT
Param_4    CustomerId         INT
```

**Important Notes**:
- `InsertDatetime` is NOT updated (preserve original insertion time)
- `UpdateDatetime` is set to `CURRENT_TIMESTAMP`
- `IsDeleted` is NOT modified (preserve deletion state if any)
- ALL business columns are updated (even if only one changed)

**Performance Warning**:
- OLE DB Command executes UPDATE row-by-row (slow for large updates)
- For bulk updates, consider staging table approach (see Performance Optimization)

### Step 3: Soft Delete Missing Records

**Purpose**: Mark records that exist in Landing but not in source as deleted

**Implementation**: Execute SQL Task

**SQL Statement**:
```sql
-- Soft delete records not present in current source extract
UPDATE t
SET 
    UpdateDatetime = CURRENT_TIMESTAMP,
    IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0  -- Only process active records
    AND NOT EXISTS (
        SELECT 1 
        FROM #Staging s  -- Staging table populated during data flow
        WHERE s.CompanyId = t.CompanyId 
            AND s.CustomerId = t.CustomerId
    );

-- Return count for logging
SELECT @@ROWCOUNT AS DeletedCount;
```

**Alternative Approach** (without staging):
```sql
-- Use MERGE for all three operations in one statement
MERGE [Landing].[ERP].[Customer] AS target
USING (
    -- Source query from Step 1
    SELECT 
        CompanyId,
        CustomerId,
        HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
        CustomerName,
        VAT
    FROM [ERP].[dbo].[Customer]
) AS source
ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- UPDATE changed records
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- INSERT new records
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CompanyId, CustomerId, ChangeHashKey,
        InsertDatetime, UpdateDatetime, IsDeleted,
        CustomerName, VAT
    )
    VALUES (
        source.CompanyId, source.CustomerId, source.ChangeHashKey,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.CustomerName, source.VAT
    )

-- SOFT DELETE missing records
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

## Implementation Patterns

### Pattern 1: Data Flow with Staging Table

**Most Common Pattern** - Flexible and performant for most scenarios

**Steps**:

1. **Create/Truncate Staging Table**:
```sql
-- Execute SQL Task: Truncate Staging
IF OBJECT_ID('tempdb..#Staging_ERP_Customer') IS NOT NULL
    DROP TABLE #Staging_ERP_Customer;

CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT,
    CustomerId      INT,
    ChangeHashKey   BINARY(32),
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20)
);
```

2. **Data Flow: Extract → Staging**:
   - OLE DB Source: Query with hash calculation
   - OLE DB Destination: `#Staging_ERP_Customer`

3. **Execute SQL: Merge Staging → Landing**:
```sql
-- Perform three-way merge
MERGE [Landing].[ERP].[Customer] AS target
USING #Staging_ERP_Customer AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;

-- Capture metrics
SELECT 
    COUNT(CASE WHEN $action = 'INSERT' THEN 1 END) AS InsertCount,
    COUNT(CASE WHEN $action = 'UPDATE' AND source.CompanyId IS NOT NULL THEN 1 END) AS UpdateCount,
    COUNT(CASE WHEN $action = 'UPDATE' AND source.CompanyId IS NULL THEN 1 END) AS DeleteCount
FROM (
    MERGE [Landing].[ERP].[Customer] AS target
    USING #Staging_ERP_Customer AS source
        ON target.CompanyId = source.CompanyId 
        AND target.CustomerId = source.CustomerId
    -- ... (same MERGE as above)
    OUTPUT $action, source.CompanyId
) AS MergeOutput;
```

**Advantages**:
- All operations in single MERGE (atomic)
- Better performance for large updates
- Simpler debugging (staging table can be inspected)
- Easier error recovery

**Disadvantages**:
- Requires additional storage (staging table)
- Two-step process (extract, then merge)

### Pattern 2: Direct Data Flow (No Staging)

**Faster for small tables** - Eliminates intermediate staging

**Steps**:

1. **Data Flow with Conditional Routing**:
   - OLE DB Source with hash calculation
   - Lookup Transformation (match on PK)
   - Conditional Split (compare hashes)
   - OLE DB Destination (INSERT new)
   - OLE DB Command (UPDATE changed)

2. **Execute SQL: Soft Delete**:
```sql
-- Mark as deleted records not seen in this run
-- Use correlation with source query
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND t.UpdateDatetime < ?  -- Package start time
    AND NOT EXISTS (
        SELECT 1 FROM [ERP].[dbo].[Customer] s
        WHERE s.CompanyId = t.CompanyId 
        AND s.CustomerId = t.CustomerId
    );
```

**Advantages**:
- Fewer steps (faster for small tables)
- No staging storage required
- Single pass through data

**Disadvantages**:
- OLE DB Command is row-by-row (slow for large updates)
- Harder to debug (no intermediate state)
- Soft delete requires separate query to source

### Pattern 3: Hybrid (Staging + Optimized Flow)

**Best performance for large tables** - Combines benefits of both

**Steps**:

1. **Create Staging with Indexes**:
```sql
CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20),
    
    PRIMARY KEY (CompanyId, CustomerId)
);

CREATE INDEX IX_Hash ON #Staging_ERP_Customer (ChangeHashKey);
```

2. **Bulk Insert to Staging**:
   - Fast Load enabled
   - Minimal logging
   - No constraints during insert

3. **T-SQL Merge** (as in Pattern 1)

4. **Indexed Soft Delete**:
```sql
-- Efficient anti-join with indexed staging
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
    LEFT JOIN #Staging_ERP_Customer s
        ON t.CompanyId = s.CompanyId 
        AND t.CustomerId = s.CustomerId
WHERE t.IsDeleted = 0
    AND s.CompanyId IS NULL;
```

## Error Handling

### Transaction Management

**Package-Level Transaction**:
```
Package Properties:
- TransactionOption: Required
- IsolationLevel: ReadCommitted
```

All tasks within the package participate in a single transaction:
- If any task fails, entire package rolls back
- Landing table remains in consistent state
- Can safely retry the entire package

**Task-Level Error Handling**:
```
Each Task:
- On Error → Execute SQL Task (Log Error)
- On Success → Next Task
```

### Error Logging

**Audit Error Table**:
```sql
CREATE TABLE [audit].[ETLError]
(
    ErrorId             INT IDENTITY(1,1) PRIMARY KEY,
    PackageName         NVARCHAR(255) NOT NULL,
    TaskName            NVARCHAR(255) NULL,
    SourceSchema        NVARCHAR(50) NULL,
    SourceTable         NVARCHAR(100) NULL,
    ErrorCode           INT NULL,
    ErrorDescription    NVARCHAR(4000) NULL,
    ErrorDatetime       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- SSIS System Variables
    ExecutionID         UNIQUEIDENTIFIER NULL,
    MachineName         NVARCHAR(128) NULL,
    UserName            NVARCHAR(128) NULL
);
```

**Error Logging SQL** (Execute SQL Task on error):
```sql
INSERT INTO [audit].[ETLError]
(
    PackageName,
    TaskName,
    SourceSchema,
    SourceTable,
    ErrorCode,
    ErrorDescription,
    ExecutionID,
    MachineName,
    UserName
)
VALUES
(
    ?,  -- @[System::PackageName]
    ?,  -- @[System::TaskName]
    ?,  -- @[User::SourceSchema]
    ?,  -- @[User::SourceTable]
    ?,  -- @[System::ErrorCode]
    ?,  -- @[System::ErrorDescription]
    ?,  -- @[System::ExecutionInstanceGUID]
    ?,  -- @[System::MachineName]
    ?,  -- @[System::UserName]
);
```

### Retry Logic

**Package Configuration**:
- **Max Concurrent Executables**: 1 (prevent concurrent runs)
- **Checkpoint Enabled**: False (full package retry, not task-level)
- **Force Execution Result**: False (allow natural completion)

**SQL Agent Job Configuration**:
- **Retry Attempts**: 3
- **Retry Interval**: 5 minutes
- **On Failure**: Email notification

## Performance Optimization

### Optimization Techniques

#### 1. Source Query Optimization

**Index Hints**:
```sql
-- Use appropriate index for source scan
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer] WITH (INDEX(IX_ModifiedDate))
WHERE ModifiedDate >= @LastSync
```

**Parallel Processing**:
```sql
-- Enable parallel query execution for large tables
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', CONCAT(...)) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer]
OPTION (MAXDOP 4)
```

#### 2. SSIS Data Flow Tuning

**Buffer Configuration**:
```
Data Flow Properties:
- DefaultBufferMaxRows: 10000 (default)
- DefaultBufferSize: 10485760 (10MB default)
- EngineThreads: 10 (or CPU count)
```

**OLE DB Destination Settings**:
```
Fast Load Options:
- Table Lock: True
- Check Constraints: False
- Keep Identity: False
- Keep Nulls: True
- Rows per Batch: 100000
- Maximum Insert Commit Size: 100000
```

**Lookup Transformation**:
```
Cache Settings (for Full Cache):
- Enable Memory Restriction: True
- Cache Size (MB): 256 (adjust based on dimension size)
- Enable Disk Cache: True (for large lookups)
```

#### 3. Staging Table Optimization

**Use Heap Table for Staging**:
```sql
-- No clustered index during insert (faster)
CREATE TABLE #Staging_ERP_Customer
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20)
);

-- Add indexes AFTER insert
CREATE CLUSTERED INDEX CIX_PK 
    ON #Staging_ERP_Customer (CompanyId, CustomerId);

CREATE NONCLUSTERED INDEX IX_Hash 
    ON #Staging_ERP_Customer (ChangeHashKey);
```

**Batch Size for MERGE**:
```sql
-- For very large tables, process in batches
DECLARE @BatchSize INT = 100000;
DECLARE @BatchStart INT = 0;

WHILE EXISTS (
    SELECT 1 FROM #Staging_ERP_Customer 
    WHERE RowNum > @BatchStart
)
BEGIN
    MERGE [Landing].[ERP].[Customer] AS target
    USING (
        SELECT * FROM #Staging_ERP_Customer
        WHERE RowNum BETWEEN @BatchStart AND @BatchStart + @BatchSize
    ) AS source
    -- ... MERGE logic ...
    
    SET @BatchStart = @BatchStart + @BatchSize;
END
```

#### 4. Minimize Locking

**Read Uncommitted for Source**:
```sql
-- Source queries don't need locks (read-only)
SELECT ...
FROM [ERP].[dbo].[Customer] WITH (NOLOCK)
WHERE ...
```

**Batch Commits for Landing**:
```sql
-- Commit every N rows to release locks
MERGE [Landing].[ERP].[Customer] AS target
USING #Staging AS source
    ON ...
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...
OPTION (OPTIMIZE FOR (@BatchSize = 50000));
```

#### 5. Partitioning for Very Large Tables

**Partition Source Extract**:
```sql
-- Process by date ranges for temporal tables
DECLARE @StartDate DATE = '2026-01-01';
DECLARE @EndDate DATE = '2026-12-31';

SELECT ...
FROM [ERP].[dbo].[Customer]
WHERE CreatedDate BETWEEN @StartDate AND @EndDate
```

**Parallel Package Execution**:
- Create separate packages for date ranges
- Execute in parallel using master package
- Union results in Landing (with appropriate locking)

## Examples

### Example 1: Simple Dimension Load (Customer)

**Source Table**:
```sql
-- [ERP].[dbo].[Customer]
CREATE TABLE [ERP].[dbo].[Customer]
(
    CompanyId       INT,
    CustomerId      INT,
    CustomerName    NVARCHAR(100),
    VAT             NVARCHAR(20),
    CreditLimit     DECIMAL(18,2),
    PRIMARY KEY (CompanyId, CustomerId)
);

-- Sample data
CompanyId | CustomerId | CustomerName     | VAT      | CreditLimit
----------|------------|------------------|----------|------------
1         | 100        | Acme Corp        | IT12345  | 50000.00
1         | 101        | Beta LLC         | IT67890  | 25000.00
1         | 102        | Gamma Solutions  | IT11111  | 100000.00
```

**Landing Table**:
```sql
-- [Landing].[ERP].[Customer]
CREATE TABLE [Landing].[ERP].[Customer]
(
    CompanyId       INT NOT NULL,
    CustomerId      INT NOT NULL,
    ChangeHashKey   BINARY(32) NOT NULL,
    InsertDatetime  DATETIME NOT NULL,
    UpdateDatetime  DATETIME NOT NULL,
    IsDeleted       BIT NOT NULL,
    CustomerName    NVARCHAR(100) NOT NULL,
    VAT             NVARCHAR(20) NULL,
    PRIMARY KEY (CompanyId, CustomerId)
);
```

**SSIS Package: Load_ERP_Customer**

**Step 1: Extract Query**:
```sql
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    CustomerName,
    VAT
FROM [ERP].[dbo].[Customer]
```

**Result**:
```
CompanyId | CustomerId | ChangeHashKey  | CustomerName     | VAT
----------|------------|----------------|------------------|--------
1         | 100        | 0xA1B2C3...    | Acme Corp        | IT12345
1         | 101        | 0xD4E5F6...    | Beta LLC         | IT67890
1         | 102        | 0x789ABC...    | Gamma Solutions  | IT11111
```

**Step 2: Data Flow**

Assume Landing table currently has:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT     | IsDeleted
----------|------------|---------------|---------------|---------|----------
1         | 100        | 0xA1B2C3...   | Acme Corp     | IT12345 | 0
1         | 101        | 0xOLDHASH..   | Beta LLC      | IT67890 | 0
1         | 103        | 0x999888...   | Delta Inc     | IT55555 | 0
```

**Lookup Results**:
- Customer 100: **Match** (exists in Landing)
- Customer 101: **Match** (exists in Landing)
- Customer 102: **No Match** (new record)
- Customer 103: (in Landing but not in source - will be soft deleted)

**Conditional Split**:
- Customer 100: Hash matches → **Unchanged** (no action)
- Customer 101: Hash differs → **Changed** (route to UPDATE)
- Customer 102: No match → **New** (route to INSERT)

**Actions**:

1. **INSERT Customer 102**:
```sql
INSERT INTO [Landing].[ERP].[Customer]
VALUES (
    1, 102, 0x789ABC..., 
    '2026-05-21 10:15:00', '2026-05-21 10:15:00', 0,
    'Gamma Solutions', 'IT11111'
)
```

2. **UPDATE Customer 101**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    ChangeHashKey = 0xD4E5F6...,
    UpdateDatetime = '2026-05-21 10:15:00',
    CustomerName = 'Beta LLC',
    VAT = 'IT67890'
WHERE CompanyId = 1 AND CustomerId = 101
```

**Step 3: Soft Delete**:
```sql
UPDATE [Landing].[ERP].[Customer]
SET 
    UpdateDatetime = '2026-05-21 10:15:00',
    IsDeleted = 1
WHERE CompanyId = 1 AND CustomerId = 103
    AND IsDeleted = 0
```

**Final Landing Table State**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName     | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|------------------|---------|-----------|----------------
1         | 100        | 0xA1B2C3...   | Acme Corp        | IT12345 | 0         | (unchanged)
1         | 101        | 0xD4E5F6...   | Beta LLC         | IT67890 | 0         | 2026-05-21 10:15
1         | 102        | 0x789ABC...   | Gamma Solutions  | IT11111 | 0         | 2026-05-21 10:15
1         | 103        | 0x999888...   | Delta Inc        | IT55555 | 1         | 2026-05-21 10:15
```

**Metrics**:
- Records Inserted: 1 (Customer 102)
- Records Updated: 1 (Customer 101)
- Records Deleted: 1 (Customer 103)
- Records Unchanged: 1 (Customer 100)

### Example 2: Fact Table Load (Order Detail)

**Source Tables**:
```sql
-- [ERP].[dbo].[OrderHeader]
CompanyId | OrderId | CustomerId | OrderDate  | Status
----------|---------|------------|------------|--------
1         | 1001    | 100        | 2026-05-20 | Shipped
1         | 1002    | 101        | 2026-05-21 | Pending

-- [ERP].[dbo].[OrderDetail]
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice
----------|---------|---------|-----------|----------|----------
1         | 1001    | 1       | 200       | 10       | 50.00
1         | 1001    | 2       | 201       | 5        | 100.00
1         | 1002    | 1       | 202       | 8        | 75.00
```

**Extract Query** (joining header + detail):
```sql
SELECT 
    d.CompanyId,
    d.OrderId,
    d.LineNum,
    
    -- Hash of all non-key columns
    HASHBYTES('SHA2_256', 
        CONCAT(
            CAST(d.ProductId AS NVARCHAR(50)), '|',
            CAST(d.Quantity AS NVARCHAR(50)), '|',
            CAST(d.UnitPrice AS NVARCHAR(50)), '|',
            ISNULL(h.Status, '')
        )
    ) AS ChangeHashKey,
    
    d.ProductId,
    d.Quantity,
    d.UnitPrice,
    h.Status AS OrderStatus
    
FROM [ERP].[dbo].[OrderDetail] d
INNER JOIN [ERP].[dbo].[OrderHeader] h
    ON d.CompanyId = h.CompanyId
    AND d.OrderId = h.OrderId
```

**Scenario: Order Status Update**:

Initial state in Landing:
```
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice | OrderStatus
----------|---------|---------|-----------|----------|-----------|------------
1         | 1001    | 1       | 200       | 10       | 50.00     | Pending
1         | 1001    | 2       | 201       | 5        | 100.00    | Pending
```

Source system now shows:
```
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice | OrderStatus
----------|---------|---------|-----------|----------|-----------|------------
1         | 1001    | 1       | 200       | 10       | 50.00     | Shipped
1         | 1001    | 2       | 201       | 5        | 100.00    | Shipped
1         | 1002    | 1       | 202       | 8        | 75.00     | Pending
```

**Processing**:
- Lines 1001/1 and 1001/2: Hash changed (Status changed) → **UPDATE**
- Line 1002/1: New line → **INSERT**

**Result**:
```
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice | OrderStatus | UpdateDatetime
----------|---------|---------|-----------|----------|-----------|-------------|----------------
1         | 1001    | 1       | 200       | 10       | 50.00     | Shipped     | 2026-05-21 10:30
1         | 1001    | 2       | 201       | 5        | 100.00    | Shipped     | 2026-05-21 10:30
1         | 1002    | 1       | 202       | 8        | 75.00     | Pending     | 2026-05-21 10:30
```

### Example 3: Handling Schema Changes

**Scenario**: Adding new column `EmailAddress` to Customer

**Step 1**: Alter Landing Table:
```sql
ALTER TABLE [Landing].[ERP].[Customer]
ADD EmailAddress NVARCHAR(255) NULL;
```

**Step 2**: Update Extract Query:
```sql
SELECT 
    CompanyId,
    CustomerId,
    
    -- Updated hash includes new column
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, ''), '|',
            ISNULL(EmailAddress, '')  -- NEW
        )
    ) AS ChangeHashKey,
    
    CustomerName,
    VAT,
    EmailAddress  -- NEW
FROM [ERP].[dbo].[Customer]
```

**Step 3**: Update SSIS Package:
- Add `EmailAddress` to OLE DB Source output
- Map `EmailAddress` in OLE DB Destination
- Update OLE DB Command UPDATE statement

**Impact of Next Load**:
- All records will show hash mismatch (hash calculation changed)
- All records will be updated (expected behavior)
- UpdateDatetime will reflect the schema change

**Best Practice**: Version the hash or add HashVersion column:
```sql
HASHBYTES('SHA2_256', 
    CONCAT(
        'v2|',  -- Version prefix
        CustomerName, '|',
        ISNULL(VAT, ''), '|',
        ISNULL(EmailAddress, '')
    )
)
```

## Best Practices

### 1. Package Design

**Naming Convention**:
```
Pattern: Load_{Schema}_{Table}.dtsx
Examples:
- Load_ERP_Customer.dtsx
- Load_SALESFORCE_Account.dtsx
- Load_MES_ProductionOrder.dtsx
```

**Parameterization**:
```
Use package parameters for:
- Source connection string
- Landing connection string
- Filter criteria (date ranges)
- Batch size

Avoid hardcoding:
- Server names
- Database names
- Credentials
```

**Version Control**:
- Store packages in source control (Git, TFS)
- Use Project Deployment Model (SSISDB)
- Tag releases with version numbers
- Document changes in package annotations

### 2. Hash Calculation

**Consistent Ordering**:
```sql
-- Always use same column order in hash
CONCAT(Col1, '|', Col2, '|', Col3)  -- Good

-- Don't change order between loads
CONCAT(Col2, '|', Col1, '|', Col3)  -- Bad (produces different hash)
```

**Data Type Handling**:
```sql
-- Convert all types to string with fixed format
HASHBYTES('SHA2_256', 
    CONCAT(
        StringCol, '|',
        CAST(IntCol AS NVARCHAR(50)), '|',
        CAST(DecimalCol AS NVARCHAR(50)), '|',
        CONVERT(NVARCHAR(23), DateCol, 121),  -- ISO format YYYY-MM-DD HH:MI:SS.mmm
        ISNULL(NullableCol, '')
    )
)
```

**Exclude Volatile Columns**:
```sql
-- Don't include auto-changing columns in hash
-- Examples: ModifiedDate, ModifiedBy, RowVersion
SELECT 
    ...,
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            VAT
            -- NOT including: ModifiedDate, RowVersion
        )
    ) AS ChangeHashKey,
    ...
```

### 3. Performance

**Index the Landing Table**:
```sql
-- Primary key on business key
CREATE PRIMARY KEY (CompanyId, CustomerId);

-- Index on hash for change detection
CREATE INDEX IX_ChangeHash ON Table (ChangeHashKey);

-- Index on temporal columns for queries
CREATE INDEX IX_Temporal ON Table (UpdateDatetime, IsDeleted);
```

**Use Staging for Large Tables**:
- Tables > 1M rows: Use staging + MERGE
- Tables > 10M rows: Use partitioned staging
- Tables > 100M rows: Consider incremental load strategy

**Monitor Buffer Spooling**:
```
SSIS Execution Logs:
- Look for "Buffer spooled to disk" warnings
- Increase buffer size or reduce rows per buffer
- Add more RAM to SSIS server
```

### 4. Testing

**Unit Test Each Package**:
```sql
-- Setup: Insert known test data
INSERT INTO [ERP].[dbo].[Customer] VALUES (...);

-- Execute: Run SSIS package

-- Assert: Verify Landing table
SELECT COUNT(*) FROM [Landing].[ERP].[Customer] 
WHERE CompanyId = 999;  -- Test data

-- Cleanup: Remove test data
DELETE FROM [Landing].[ERP].[Customer] WHERE CompanyId = 999;
DELETE FROM [ERP].[dbo].[Customer] WHERE CompanyId = 999;
```

**Test Scenarios**:
1. **Fresh Load**: Empty Landing table → Full insert
2. **No Changes**: Re-run package → No updates
3. **Updates**: Modify source → Landing updated
4. **Deletes**: Remove from source → Soft delete
5. **Schema Change**: Add column → All records update
6. **Error Recovery**: Kill mid-execution → Retry succeeds

### 5. Monitoring

**Track Execution Metrics**:
```sql
CREATE TABLE [audit].[ETLLog]
(
    LogId               INT IDENTITY PRIMARY KEY,
    PackageName         NVARCHAR(255),
    SourceSchema        NVARCHAR(50),
    SourceTable         NVARCHAR(100),
    RecordsExtracted    INT,
    RecordsInserted     INT,
    RecordsUpdated      INT,
    RecordsDeleted      INT,
    RecordsUnchanged    INT,
    ExecutionStart      DATETIME,
    ExecutionEnd        DATETIME,
    DurationSeconds     INT,
    Status              NVARCHAR(20),  -- Success, Failed, Warning
    ErrorMessage        NVARCHAR(4000)
);
```

**Alert on Anomalies**:
```sql
-- Alert if deletion rate > 10%
IF (@RecordsDeleted * 1.0 / NULLIF(@TotalRecords, 0)) > 0.10
BEGIN
    -- Send alert
    EXEC msdb.dbo.sp_send_dbmail
        @subject = 'High Deletion Rate Alert',
        @body = 'More than 10% of records were deleted';
END

-- Alert if execution time > 2x average
IF @DurationSeconds > (SELECT AVG(DurationSeconds) * 2 FROM audit.ETLLog)
BEGIN
    -- Send alert
END
```

## Monitoring and Logging

### Execution Logging

**Package-Level Logging**:
```sql
-- Execute SQL Task at package start
INSERT INTO [audit].[ETLLog]
(PackageName, SourceSchema, SourceTable, ExecutionStart, Status)
VALUES (?, ?, ?, GETDATE(), 'Running');

-- Execute SQL Task at package end (success)
UPDATE [audit].[ETLLog]
SET 
    ExecutionEnd = GETDATE(),
    DurationSeconds = DATEDIFF(SECOND, ExecutionStart, GETDATE()),
    RecordsExtracted = ?,
    RecordsInserted = ?,
    RecordsUpdated = ?,
    RecordsDeleted = ?,
    Status = 'Success'
WHERE LogId = ?;

-- Execute SQL Task on error
UPDATE [audit].[ETLLog]
SET 
    ExecutionEnd = GETDATE(),
    Status = 'Failed',
    ErrorMessage = ?
WHERE LogId = ?;
```

### Dashboard Queries

**Data Freshness**:
```sql
SELECT 
    SourceSchema,
    SourceTable,
    MAX(UpdateDatetime) AS LastUpdate,
    DATEDIFF(MINUTE, MAX(UpdateDatetime), GETDATE()) AS MinutesSinceUpdate,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END) AS ActiveRecords
FROM [Landing].[ERP].[Customer]
GROUP BY SourceSchema, SourceTable;
```

**Execution History**:
```sql
SELECT 
    PackageName,
    ExecutionStart,
    DurationSeconds,
    RecordsInserted,
    RecordsUpdated,
    RecordsDeleted,
    Status
FROM [audit].[ETLLog]
WHERE ExecutionStart >= DATEADD(DAY, -7, GETDATE())
ORDER BY ExecutionStart DESC;
```

**Error Summary**:
```sql
SELECT 
    PackageName,
    COUNT(*) AS ErrorCount,
    MAX(ErrorDatetime) AS LastError,
    MAX(ErrorDescription) AS LastErrorMessage
FROM [audit].[ETLError]
WHERE ErrorDatetime >= DATEADD(DAY, -1, GETDATE())
GROUP BY PackageName
ORDER BY ErrorCount DESC;
```

---

## Summary

The Landing Zone synchronization flow provides:

✅ **Consistency**: Every table follows the same pattern  
✅ **Efficiency**: Hash-based change detection minimizes processing  
✅ **Reliability**: Idempotent and transactional operations  
✅ **Auditability**: Complete tracking of all changes  
✅ **Scalability**: Handles tables from thousands to billions of rows  
✅ **Maintainability**: Clear, documented, repeatable process  

By following these patterns and best practices, you create a robust ETL pipeline that reliably synchronizes data from source systems to the Landing zone while maintaining data quality and audit compliance.

---

**Document Version**: 1.0  
**Last Updated**: May 21, 2026  
**Technology Stack**: Microsoft SQL Server 2016+, SSIS 2016+  
**Audience**: Data Engineers, ETL Developers, Technical Architects
