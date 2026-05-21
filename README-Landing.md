# Data Warehouse Landing Zone - Design Pattern

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Schema Design](#schema-design)
- [Table Structure](#table-structure)
- [Update Pattern](#update-pattern)
- [Benefits and Rationale](#benefits-and-rationale)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Overview

The **Landing Zone** (also known as the **Staging Area** or **Raw Data Layer**) is the first layer in a data warehouse architecture where data from various source systems is initially loaded. This document describes a proven pattern for designing and managing the Landing zone using Microsoft SQL Server.

### Purpose of the Landing Zone

The Landing zone serves several critical functions:
- **Decoupling**: Isolates the data warehouse from source systems, reducing dependencies and load on operational databases
- **Temporal Storage**: Provides a snapshot of source data at specific points in time
- **Change Detection**: Tracks what data has changed since the last load
- **Data Quality**: Acts as a checkpoint before data moves to more refined layers
- **Auditability**: Maintains a record of when data arrived and how it changed

## Architecture

### Database Structure

```
Landing Database
├── audit (schema)
│   ├── Tables (log tables for ETL operations)
│   ├── Views (monitoring and reporting views)
│   └── Stored Procedures (logging and utility procedures)
├── ERP (schema)
│   ├── Customer
│   ├── Order
│   └── ... (other ERP tables)
├── SALESFORCE (schema)
│   ├── Account
│   ├── Opportunity
│   └── ... (other Salesforce objects)
├── MES (schema)
│   ├── ProductionOrder
│   ├── WorkCenter
│   └── ... (other MES tables)
└── ... (additional source schemas)
```

### Design Principles

1. **Single Landing Database**: All source systems land their data in one common database
2. **Schema-per-Source**: Each data source has its own schema, named in CAPITAL LETTERS
3. **Schema Isolation**: Source schemas are logically separated for security and organization
4. **Audit Schema**: Common audit schema for cross-source monitoring and logging

## Key Concepts

### Change Data Capture (CDC)

Traditional CDC mechanisms track changes at the source database level. This pattern implements a **hash-based CDC** approach that:
- Works with any source system (doesn't require database-level CDC features)
- Detects changes by comparing hash values rather than column-by-column comparison
- Provides efficient change detection with minimal computational overhead

### Hash-Based Change Detection

The **ChangeHashKey** column contains a SHA256 hash of all relevant business columns. This technique:
- **Efficiency**: Single comparison instead of multiple column comparisons
- **Consistency**: Deterministic - same data always produces same hash
- **Sensitivity**: Any change in source data produces a different hash
- **Performance**: Indexed hash column enables fast lookups

**Formula**:
```
ChangeHashKey = SHA256(Column1 + Column2 + ... + ColumnN)
```

### Soft Delete Pattern

Instead of physically removing records, the **IsDeleted** flag marks records as deleted. This approach:
- **Preserves History**: Deleted records remain in the database for audit purposes
- **Enables Recovery**: Accidentally deleted data can be restored
- **Supports Temporal Queries**: Analysis can include or exclude deleted records
- **Maintains Referential Context**: Related records can still reference deleted entities

### Idempotency

The update pattern is **idempotent**, meaning:
- Running the same load multiple times produces the same result
- Failed loads can be safely retried without data corruption
- No duplicate records are created
- Supports both full and incremental load strategies

### Temporal Tracking

Each record tracks its lifecycle through timestamp columns:
- **InsertDatetime**: When the record first appeared in the Landing zone
- **UpdateDatetime**: When the record was last modified
- Enables point-in-time analysis and change rate metrics

## Schema Design

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Database | PascalCase | `Landing` |
| Source Schema | UPPERCASE | `ERP`, `SALESFORCE`, `MES` |
| Audit Schema | lowercase | `audit` |
| Table Name | Match source table | `Customer`, `Order` |
| Business Key Columns | Match source | `CompanyId`, `CustomerId` |
| Technical Columns | PascalCase | `ChangeHashKey`, `InsertDatetime` |

### Schema-per-Source Pattern

Each source system gets its own schema for several reasons:

**Benefits**:
- **Security**: Grant permissions at schema level (e.g., ERP team accesses only `ERP` schema)
- **Organization**: Clear separation of concerns
- **Collision Avoidance**: Different sources can have tables with the same name (e.g., `ERP.Order` vs `SALESFORCE.Order`)
- **Selective Processing**: Process or reload specific sources independently
- **Documentation**: Schema name immediately identifies data provenance

**Example**:
```sql
-- ERP Customer table
ERP.Customer

-- Salesforce Account table (equivalent to Customer in ERP)
SALESFORCE.Account
```

## Table Structure

### Standard Column Layout

Every Landing table follows this structure:

```sql
CREATE TABLE [SOURCE_SCHEMA].[TableName]
(
    -- Business Key Columns (from source)
    [PrimaryKey1]      [DataType]      NOT NULL,
    [PrimaryKey2]      [DataType]      NOT NULL,
    
    -- Change Detection & Metadata
    [ChangeHashKey]    BINARY(32)      NOT NULL,
    [InsertDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [UpdateDatetime]   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    [IsDeleted]        BIT             NOT NULL DEFAULT 0,
    
    -- Business Columns (from source)
    [Column1]          [DataType]      [NULL/NOT NULL],
    [Column2]          [DataType]      [NULL/NOT NULL],
    ...
    
    -- Primary Key Constraint
    CONSTRAINT [PK_SOURCE_TableName] PRIMARY KEY CLUSTERED 
    (
        [PrimaryKey1],
        [PrimaryKey2]
    )
);

-- Index on ChangeHashKey for performance
CREATE NONCLUSTERED INDEX [IX_SOURCE_TableName_ChangeHashKey] 
    ON [SOURCE_SCHEMA].[TableName] ([ChangeHashKey]);

-- Index on temporal columns for audit queries
CREATE NONCLUSTERED INDEX [IX_SOURCE_TableName_Temporal] 
    ON [SOURCE_SCHEMA].[TableName] ([UpdateDatetime], [IsDeleted]);
```

### Column Descriptions

| Column | Type | Purpose | Populated |
|--------|------|---------|-----------|
| Business Key(s) | Varies | Unique identifier from source | Every load |
| ChangeHashKey | BINARY(32) | SHA256 hash of business columns | Every load (computed) |
| InsertDatetime | DATETIME | First insertion timestamp | Insert only |
| UpdateDatetime | DATETIME | Last modification timestamp | Insert & update |
| IsDeleted | BIT | Soft delete flag | Insert (0) & delete (1) |
| Business Columns | Varies | Source data columns | Every load |

### Column Selection Strategy

**Business Key Columns**: Include all columns that form the source table's primary key
- These uniquely identify each record
- Used for matching source to landing data

**Business Columns**: Include only the columns needed for downstream processing
- Not all source columns need to be in the data warehouse
- Select columns relevant to business intelligence and reporting
- Exclude sensitive data if not needed (minimizes compliance requirements)
- Exclude large binary columns (images, documents) unless specifically required

**ChangeHashKey Calculation**: Hash only the business columns
- Do NOT include business key columns (they don't change)
- Do NOT include technical columns (InsertDatetime, UpdateDatetime, IsDeleted)
- Include ALL columns you want to detect changes on

## Update Pattern

### The Four Scenarios

The update logic follows a **MERGE-like pattern** that handles four distinct scenarios:

```
┌─────────────────────────────────────────────────────────────┐
│                    Source Table Extract                     │
│           (Primary Keys + Business Columns)                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─ Calculate ChangeHashKey
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Match with Landing Table on PK                 │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Scenario│    │ Scenario│    │ Scenario│
    │    A    │    │  B & C  │    │    D    │
    └─────────┘    └─────────┘    └─────────┘
```

#### Scenario A: New Record
**Condition**: Record exists in source but NOT in landing

**Action**: INSERT new record
```sql
INSERT INTO [Landing].[SCHEMA].[Table]
(
    [PrimaryKey1],
    [PrimaryKey2],
    [ChangeHashKey],
    [InsertDatetime],
    [UpdateDatetime],
    [IsDeleted],
    [Column1],
    [Column2]
)
VALUES
(
    @PrimaryKey1,
    @PrimaryKey2,
    @ComputedHash,            -- SHA256 hash
    CURRENT_TIMESTAMP,        -- Set insert time
    CURRENT_TIMESTAMP,        -- Set update time
    0,                        -- Not deleted
    @Column1,
    @Column2
);
```

**Example**: A new customer is created in the ERP system
- First time this customer appears in the data warehouse
- All fields are populated from source
- InsertDatetime and UpdateDatetime set to current time

#### Scenario B: No Change
**Condition**: Record exists in both source and landing, ChangeHashKey matches

**Action**: NO ACTION (skip record)
```sql
-- Pseudocode
IF source.ChangeHashKey = landing.ChangeHashKey THEN
    SKIP; -- No changes detected
END IF;
```

**Example**: Customer data hasn't changed since last load
- Hash comparison is very fast (single value comparison)
- Minimizes unnecessary updates
- Preserves UpdateDatetime to reflect actual change time

#### Scenario C: Changed Record
**Condition**: Record exists in both source and landing, ChangeHashKey differs

**Action**: UPDATE existing record
```sql
UPDATE [Landing].[SCHEMA].[Table]
SET
    [ChangeHashKey] = @NewComputedHash,     -- Update hash
    [UpdateDatetime] = CURRENT_TIMESTAMP,   -- Update timestamp
    [Column1] = @NewColumn1,                -- Update business columns
    [Column2] = @NewColumn2
WHERE
    [PrimaryKey1] = @PrimaryKey1
    AND [PrimaryKey2] = @PrimaryKey2;
```

**Example**: Customer's name or VAT number changed in ERP
- Hash detects the change automatically
- All business columns refreshed (even if only one changed)
- UpdateDatetime reflects when change was detected
- InsertDatetime remains unchanged (original arrival time preserved)

#### Scenario D: Deleted Record
**Condition**: Record exists in landing (IsDeleted = 0) but NOT in source

**Action**: SOFT DELETE (mark as deleted)
```sql
UPDATE [Landing].[SCHEMA].[Table]
SET
    [UpdateDatetime] = CURRENT_TIMESTAMP,   -- Update timestamp
    [IsDeleted] = 1                         -- Mark as deleted
WHERE
    [PrimaryKey1] = @PrimaryKey1
    AND [PrimaryKey2] = @PrimaryKey2
    AND [IsDeleted] = 0;                    -- Only update if not already deleted
```

**Example**: Customer record removed from ERP
- Record remains in Landing table for audit purposes
- IsDeleted flag prevents processing in downstream layers
- UpdateDatetime reflects when deletion was detected
- Can be queried for historical analysis

**Note**: Records with `IsDeleted = 1` are NOT re-deleted if still missing in subsequent loads

### Implementation Approaches

#### Option 1: MERGE Statement (Recommended)
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #SourceData AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Scenario C: Update when hash changed
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Scenario A: Insert new records
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Scenario D: Soft delete missing records
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

#### Option 2: Separate Statements
```sql
-- Scenario A: Insert new records
INSERT INTO [Landing].[ERP].[Customer] (...)
SELECT ...
FROM #SourceData s
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] t
    WHERE t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
);

-- Scenario C: Update changed records
UPDATE t
SET ...
FROM [Landing].[ERP].[Customer] t
INNER JOIN #SourceData s 
    ON t.CompanyId = s.CompanyId AND t.CustomerId = s.CustomerId
WHERE t.ChangeHashKey <> s.ChangeHashKey;

-- Scenario D: Soft delete missing records
UPDATE t
SET UpdateDatetime = CURRENT_TIMESTAMP, IsDeleted = 1
FROM [Landing].[ERP].[Customer] t
WHERE t.IsDeleted = 0
    AND NOT EXISTS (
        SELECT 1 FROM #SourceData s
        WHERE s.CompanyId = t.CompanyId AND s.CustomerId = t.CustomerId
    );
```

## Benefits and Rationale

### Why Hash-Based Change Detection?

**Traditional Approach** (column-by-column comparison):
```sql
WHERE target.Column1 <> source.Column1
   OR target.Column2 <> source.Column2
   OR target.Column3 <> source.Column3
   ...
```
**Problems**:
- Complex WHERE clause for tables with many columns
- NULL handling requires special logic (ISNULL or COALESCE)
- Performance degrades with more columns
- Difficult to maintain as schema evolves

**Hash-Based Approach**:
```sql
WHERE target.ChangeHashKey <> source.ChangeHashKey
```
**Advantages**:
- ✅ Single comparison regardless of column count
- ✅ Deterministic and consistent
- ✅ NULL handling embedded in hash calculation
- ✅ Can be indexed for performance
- ✅ Easy to maintain and understand

### Why Soft Deletes?

**Hard Delete** (physical removal):
```sql
DELETE FROM [Landing].[ERP].[Customer]
WHERE ...
```
**Problems**:
- Historical data lost forever
- Audit trail broken
- Cannot distinguish "never existed" from "was deleted"
- Cannot track when deletion occurred

**Soft Delete** (IsDeleted flag):
```sql
UPDATE [Landing].[ERP].[Customer]
SET IsDeleted = 1
WHERE ...
```
**Advantages**:
- ✅ Full audit trail maintained
- ✅ Can restore accidentally deleted data
- ✅ Downstream processes can choose to include/exclude deleted records
- ✅ Temporal analysis remains accurate
- ✅ Regulatory compliance (GDPR, SOX, etc.) easier

### Why Schema-per-Source?

**Single Schema Approach**:
```
Landing.dbo.ERP_Customer
Landing.dbo.ERP_Order
Landing.dbo.Salesforce_Account
Landing.dbo.Salesforce_Opportunity
```
**Problems**:
- Table name collisions require prefixes
- Security must be managed at table level
- Difficult to grant access to "all ERP tables"
- Namespace pollution

**Schema-per-Source Approach**:
```
Landing.ERP.Customer
Landing.ERP.Order
Landing.SALESFORCE.Account
Landing.SALESFORCE.Opportunity
```
**Advantages**:
- ✅ Natural namespace separation
- ✅ Schema-level security grants
- ✅ Clear data lineage
- ✅ Easier to reload entire source
- ✅ Table names match source system exactly

### Why Temporal Columns?

**InsertDatetime** enables:
- Identifying when records first entered the data warehouse
- Measuring data latency (time from source creation to landing)
- Debugging ETL processes
- Compliance and audit requirements

**UpdateDatetime** enables:
- Change frequency analysis
- Identifying stale data
- Troubleshooting data quality issues
- SLA monitoring (how fresh is the data?)
- Incremental processing in downstream layers

## Examples

### Example 1: ERP Customer Table

**Source Table** (ERP database):
```sql
-- dbo.Customer in ERP database
CREATE TABLE dbo.Customer
(
    CompanyId       INT             NOT NULL,
    CustomerId      INT             NOT NULL,
    CustomerName    NVARCHAR(100)   NOT NULL,
    VAT             NVARCHAR(20)    NULL,
    Address         NVARCHAR(200)   NULL,
    CreditLimit     DECIMAL(18,2)   NULL,
    PRIMARY KEY (CompanyId, CustomerId)
);
```

**Landing Table** (Landing database):
```sql
-- ERP.Customer in Landing database
CREATE TABLE [Landing].[ERP].[Customer]
(
    -- Business Keys
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Technical Columns
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Business Columns (selected from source)
    CustomerName        NVARCHAR(100)   NOT NULL,
    VAT                 NVARCHAR(20)    NULL,
    
    CONSTRAINT PK_ERP_Customer PRIMARY KEY CLUSTERED (CompanyId, CustomerId)
);

CREATE NONCLUSTERED INDEX IX_ERP_Customer_ChangeHashKey 
    ON [Landing].[ERP].[Customer] (ChangeHashKey);
```

**Hash Calculation** (pseudocode):
```
ChangeHashKey = SHA256(CustomerName + '|' + ISNULL(VAT, ''))
```

**Note**: Address and CreditLimit are NOT included (not needed in DW)

### Example 2: Complete ETL Process

**Step 1**: Extract from source
```sql
-- Extract data from ERP
SELECT 
    CompanyId,
    CustomerId,
    CustomerName,
    VAT,
    -- Calculate hash
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey
INTO #SourceData
FROM [ERP_Server].[ERP].[dbo].[Customer];
```

**Step 2**: Apply MERGE logic
```sql
MERGE [Landing].[ERP].[Customer] AS target
USING #SourceData AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Update changed records (Scenario C)
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerName = source.CustomerName,
        VAT = source.VAT

-- Insert new records (Scenario A)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CompanyId, CustomerId, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, CustomerName, VAT)
    VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
            source.CustomerName, source.VAT)

-- Soft delete missing records (Scenario D)
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Step 3**: Log results (in audit schema)
```sql
INSERT INTO [Landing].[audit].[ETLLog]
(
    SourceSchema,
    SourceTable,
    RecordsInserted,
    RecordsUpdated,
    RecordsDeleted,
    ExecutionDatetime
)
VALUES
(
    'ERP',
    'Customer',
    @InsertedCount,
    @UpdatedCount,
    @DeletedCount,
    CURRENT_TIMESTAMP
);
```

### Example 3: Scenario Walkthrough

**Initial State** (Landing table):
```
CompanyId | CustomerId | ChangeHashKey | CustomerName  | VAT        | IsDeleted
----------|------------|---------------|---------------|------------|----------
1         | 100        | 0xABCD...     | Acme Corp     | IT12345    | 0
1         | 101        | 0xEF01...     | Beta LLC      | IT67890    | 0
```

**Source Data** (current ERP):
```
CompanyId | CustomerId | CustomerName      | VAT        
----------|------------|-------------------|------------
1         | 100        | Acme Corp         | IT12345    
1         | 101        | Beta Industries   | IT67890    
1         | 102        | Gamma Solutions   | IT11111    
```

**Processing**:

1. **Customer 100**: Hash matches → Scenario B (no action)
   - No changes detected
   - Record untouched

2. **Customer 101**: Hash differs → Scenario C (update)
   - CustomerName changed from "Beta LLC" to "Beta Industries"
   - New hash calculated
   - UpdateDatetime updated
   - Business columns refreshed

3. **Customer 102**: Not in landing → Scenario A (insert)
   - New customer created in ERP
   - New record inserted
   - InsertDatetime and UpdateDatetime set

**Result**:
```
CompanyId | CustomerId | ChangeHashKey | CustomerName      | VAT     | IsDeleted | UpdateDatetime
----------|------------|---------------|-------------------|---------|-----------|----------------
1         | 100        | 0xABCD...     | Acme Corp         | IT12345 | 0         | (unchanged)
1         | 101        | 0x1234...     | Beta Industries   | IT67890 | 0         | 2026-05-20 10:30
1         | 102        | 0x5678...     | Gamma Solutions   | IT11111 | 0         | 2026-05-20 10:30
```

## Best Practices

### 1. Hash Calculation

**Consistent Delimiters**:
```sql
-- Good: Use delimiter to avoid concatenation ambiguity
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))

-- Bad: Values "AB" + "CD" produces same result as "ABC" + "D"
HASHBYTES('SHA2_256', CONCAT(Col1, Col2, Col3))
```

**NULL Handling**:
```sql
-- Good: Explicit NULL handling
HASHBYTES('SHA2_256', 
    CONCAT(
        Col1, '|',
        ISNULL(Col2, ''), '|',
        ISNULL(Col3, '')
    )
)

-- Bad: NULL propagation makes entire hash NULL
HASHBYTES('SHA2_256', CONCAT(Col1, '|', Col2, '|', Col3))
```

**Data Type Consistency**:
```sql
-- Good: Convert to string consistently
HASHBYTES('SHA2_256', 
    CONCAT(
        StringCol, '|',
        CAST(NumericCol AS NVARCHAR(50)), '|',
        CONVERT(NVARCHAR(23), DateCol, 121)  -- ISO format
    )
)
```

### 2. Performance Optimization

**Indexing Strategy**:
```sql
-- Primary key for MERGE operations
CREATE PRIMARY KEY (BusinessKey1, BusinessKey2);

-- Hash index for change detection
CREATE INDEX IX_ChangeHash ON Table (ChangeHashKey);

-- Temporal index for audit queries
CREATE INDEX IX_Temporal ON Table (UpdateDatetime, IsDeleted) 
    INCLUDE (BusinessKey1, BusinessKey2);

-- Composite index for downstream processing
CREATE INDEX IX_Active ON Table (IsDeleted) 
    WHERE IsDeleted = 0;  -- Filtered index for active records
```

**Use Temporary Tables**:
```sql
-- Extract to temp table first
SELECT ... INTO #SourceData FROM [LinkedServer].[Database].[Schema].[Table];

-- Create indexes on temp table
CREATE INDEX IX_Temp ON #SourceData (PrimaryKey1, PrimaryKey2);

-- Then MERGE
MERGE [Landing].[Schema].[Table] AS target
USING #SourceData AS source ...
```

### 3. Error Handling

**Transaction Management**:
```sql
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- Extract
    SELECT ... INTO #SourceData FROM ...;
    
    -- Transform (calculate hash)
    UPDATE #SourceData SET ChangeHashKey = HASHBYTES(...);
    
    -- Load (MERGE)
    MERGE [Landing].[Schema].[Table] ...;
    
    -- Audit
    INSERT INTO [audit].[ETLLog] ...;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    -- Log error
    INSERT INTO [audit].[ETLError] (
        SourceSchema, SourceTable, ErrorMessage, ErrorDatetime
    )
    VALUES (
        'ERP', 'Customer', ERROR_MESSAGE(), CURRENT_TIMESTAMP
    );
    
    THROW;
END CATCH;
```

### 4. Audit Schema Design

**ETL Log Table**:
```sql
CREATE TABLE [audit].[ETLLog]
(
    ETLLogId            INT             IDENTITY(1,1) PRIMARY KEY,
    SourceSchema        NVARCHAR(50)    NOT NULL,
    SourceTable         NVARCHAR(100)   NOT NULL,
    RecordsInserted     INT             NOT NULL DEFAULT 0,
    RecordsUpdated      INT             NOT NULL DEFAULT 0,
    RecordsDeleted      INT             NOT NULL DEFAULT 0,
    ExecutionDatetime   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExecutionDuration   INT             NULL,  -- milliseconds
    RowsProcessed       INT             NULL
);
```

**Monitoring View**:
```sql
CREATE VIEW [audit].[vw_DataFreshness]
AS
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    MAX(UpdateDatetime) AS LastUpdate,
    DATEDIFF(MINUTE, MAX(UpdateDatetime), CURRENT_TIMESTAMP) AS MinutesSinceUpdate,
    COUNT(*) AS TotalRecords,
    SUM(CASE WHEN IsDeleted = 0 THEN 1 ELSE 0 END) AS ActiveRecords,
    SUM(CASE WHEN IsDeleted = 1 THEN 1 ELSE 0 END) AS DeletedRecords
FROM sys.schemas s
INNER JOIN sys.tables t ON s.schema_id = t.schema_id
CROSS APPLY (
    SELECT UpdateDatetime, IsDeleted
    FROM [Landing].[schema].[table]  -- Dynamic SQL needed in practice
) x
WHERE s.name NOT IN ('audit', 'dbo', 'sys')
GROUP BY s.name, t.name;
```

### 5. Data Quality Checks

**Post-Load Validation**:
```sql
-- Check for orphaned foreign keys
SELECT 'Orphaned Orders' AS Issue, COUNT(*) AS Count
FROM [Landing].[ERP].[Order] o
WHERE NOT EXISTS (
    SELECT 1 FROM [Landing].[ERP].[Customer] c
    WHERE c.CompanyId = o.CompanyId 
    AND c.CustomerId = o.CustomerId
    AND c.IsDeleted = 0
);

-- Check for unexpected NULL values
SELECT 'NULL Customer Names' AS Issue, COUNT(*) AS Count
FROM [Landing].[ERP].[Customer]
WHERE CustomerName IS NULL
AND IsDeleted = 0;

-- Check for duplicate business keys (should never happen)
SELECT 'Duplicate Customers' AS Issue, COUNT(*) AS Count
FROM (
    SELECT CompanyId, CustomerId, COUNT(*) AS Cnt
    FROM [Landing].[ERP].[Customer]
    GROUP BY CompanyId, CustomerId
    HAVING COUNT(*) > 1
) x;
```

### 6. Incremental vs Full Load

**Full Load** (recommended for Landing):
- Load all source data every time
- Simple logic
- Idempotent (safe to rerun)
- Detects deletes automatically (Scenario D)
- Recommended for Landing layer

**Incremental Load** (use cautiously):
- Load only changed records (based on source timestamp)
- More complex logic
- Faster for very large tables
- Deletes detection requires separate logic
- Consider for downstream layers, not Landing

**Example - Full Load with TRUNCATE optimization**:
```sql
-- For small dimension tables, truncate and reload can be faster than MERGE
BEGIN TRANSACTION;

    TRUNCATE TABLE [Landing].[ERP].[CustomerCategory];
    
    INSERT INTO [Landing].[ERP].[CustomerCategory] (...)
    SELECT ... FROM [ERP_Server].[ERP].[dbo].[CustomerCategory];

COMMIT TRANSACTION;
```

### 7. Schema Evolution

When source schema changes:

**Adding Columns**:
```sql
-- 1. Add column to Landing table
ALTER TABLE [Landing].[ERP].[Customer]
ADD EmailAddress NVARCHAR(100) NULL;

-- 2. Update hash calculation to include new column
-- (update ETL procedure)

-- 3. Next load will detect ALL records as changed
-- (hash changes because calculation includes new column)
-- This is expected and correct behavior
```

**Removing Columns**:
```sql
-- 1. Update hash calculation (remove column)
-- 2. Next load will detect ALL records as changed
-- 3. Later: drop column from Landing table (optional)
ALTER TABLE [Landing].[ERP].[Customer]
DROP COLUMN OldColumn;
```

**Best Practice**: Version your hash calculation
```sql
-- Option 1: Add hash version column
ALTER TABLE [Landing].[ERP].[Customer]
ADD HashVersion TINYINT NOT NULL DEFAULT 1;

-- Option 2: Include version in hash
ChangeHashKey = HASHBYTES('SHA2_256', CONCAT('v2|', Col1, '|', Col2, ...))
```

---

## Summary

This Landing zone design pattern provides:

✅ **Scalability**: Handles multiple source systems independently  
✅ **Performance**: Hash-based change detection is fast and efficient  
✅ **Auditability**: Full temporal tracking and soft deletes  
✅ **Reliability**: Idempotent loads can be safely retried  
✅ **Maintainability**: Clear structure and consistent patterns  
✅ **Flexibility**: Works with any source system (no CDC requirements)  

By following these principles, you create a robust foundation for your data warehouse that decouples source systems, tracks changes efficiently, and maintains complete audit trails for compliance and analysis.

---

**Document Version**: 1.0  
**Last Updated**: May 20, 2026  
**Technology Stack**: Microsoft SQL Server 2016+
