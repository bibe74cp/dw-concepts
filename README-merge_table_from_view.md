# Merge Table from View - Pattern Documentation

## Overview

This pattern provides a automated code generation approach for creating dimension/fact tables and their synchronization stored procedures in a data warehouse. The pattern uses **source views** to define the desired structure and content, then generates the physical table and merge logic automatically.

## Conceptual Model

### Three-Layer Column Structure

Every source view follows a strict three-layer column structure:

```
┌─────────────────────────────────────────────┐
│  1. PRIMARY KEY COLUMNS                     │
│     - Business natural keys                 │
│     - Used for record matching              │
│     - Position: BEFORE data-warehouse cols  │
├─────────────────────────────────────────────┤
│  2. DATA-WAREHOUSE COLUMNS (Metadata)       │
│     - ChangeHashKey (VARBINARY(32))        │
│     - InsertDatetime (DATETIME)            │
│     - UpdateDatetime (DATETIME)            │
│     - IsDeleted (BIT)                      │
│     - Position: MIDDLE (anchor columns)     │
├─────────────────────────────────────────────┤
│  3. ATTRIBUTE COLUMNS                       │
│     - Business descriptive data             │
│     - Subject to change detection           │
│     - Position: AFTER data-warehouse cols   │
└─────────────────────────────────────────────┘
```

### Column Identification Logic

The stored procedure uses the **data-warehouse columns as anchors** to partition the view columns:

1. **Scan** the view's column list from left to right
2. **Detect** the first occurrence of any data-warehouse column (`ChangeHashKey`, `InsertDatetime`, `UpdateDatetime`, `IsDeleted`)
3. **Classify**:
   - Columns **before** first data-warehouse column → **Primary Keys**
   - The data-warehouse columns themselves → **Metadata** (not modified during merge)
   - Columns **after** last data-warehouse column → **Attributes**

## Pattern Components

### A. Table Creation Script

#### Step 1: Commented DROP Statement
```sql
--DROP TABLE IF EXISTS Dim.LeggeRiferimento;
GO
```
**Purpose**: Provides quick way to rebuild table during development (uncomment to drop)

#### Step 2: Conditional Table Creation
```sql
IF OBJECT_ID('Dim.LeggeRiferimento', 'U') IS NULL
BEGIN
    -- Table creation logic
END;
GO
```
**Purpose**: Idempotent execution - safe to run multiple times

#### Step 3: Structure Cloning
```sql
SELECT TOP (0) * INTO Dim.LeggeRiferimento FROM Dim.LeggeRiferimentoView;
```
**Purpose**: 
- Clone exact column structure from view
- No data copied (TOP 0)
- All columns initially nullable

#### Step 4: Primary Key Column Constraints
```sql
ALTER TABLE Dim.LeggeRiferimento ALTER COLUMN AziendaID CHAR(4) NOT NULL;
ALTER TABLE Dim.LeggeRiferimento ALTER COLUMN LeggeRiferimentoID INT NOT NULL;
```
**Purpose**: 
- Enforce NOT NULL on PK columns (required for PRIMARY KEY constraint)
- Preserve exact data types from view

#### Step 5: Primary Key Definition
```sql
ALTER TABLE Dim.LeggeRiferimento ADD CONSTRAINT PK_Dim_LeggeRiferimento 
    PRIMARY KEY CLUSTERED (AziendaID, LeggeRiferimentoID);
```
**Purpose**: 
- Enable efficient MERGE operations
- Enforce uniqueness
- Clustered index for optimal query performance

#### Step 6: Commented Attribute Constraints
```sql
--ALTER TABLE Dim.LeggeRiferimento ALTER COLUMN LeggeRiferimento VARCHAR(100) NOT NULL;
--ALTER TABLE Dim.LeggeRiferimento ALTER COLUMN DataLeggeRiferimento DATE NOT NULL;
```
**Purpose**: 
- **Commented out** to allow NULL values initially
- Can be uncommented after initial data load to enforce business rules
- Prevents merge failures when source data has NULLs

### B. Merge Stored Procedure

The merge procedure implements **four distinct scenarios**:

#### Scenario 1: Matched Records with Changed Data
```sql
WHEN MATCHED AND SRC.ChangeHashKey <> TGT.ChangeHashKey
  THEN UPDATE SET 
    TGT.ChangeHashKey = SRC.ChangeHashKey,
    TGT.UpdateDatetime = SRC.UpdateDatetime,
    TGT.IsDeleted = SRC.IsDeleted,
    TGT.LeggeRiferimento = SRC.LeggeRiferimento,
    TGT.DataLeggeRiferimento = SRC.DataLeggeRiferimento
```
**Conditions**: 
- Record exists in both view and table
- Hash differs (data changed)

**Actions**:
- Update ALL attribute columns
- Update metadata: `ChangeHashKey`, `UpdateDatetime`, `IsDeleted`
- Note: `InsertDatetime` is **never** updated (preserves original insertion time)

#### Scenario 2: Matched Records with Unchanged Data
**Conditions**: 
- Record exists in both view and table
- Hash matches (no changes)

**Actions**: 
- **No action** - MERGE automatically skips
- Performance optimization: avoid unnecessary writes

#### Scenario 3: New Records
```sql
WHEN NOT MATCHED BY TARGET
  THEN INSERT (AziendaID, LeggeRiferimentoID, ChangeHashKey, InsertDatetime, 
               UpdateDatetime, IsDeleted, LeggeRiferimento, DataLeggeRiferimento)
    VALUES (AziendaID, LeggeRiferimentoID, ChangeHashKey, InsertDatetime, 
            UpdateDatetime, IsDeleted, LeggeRiferimento, DataLeggeRiferimento)
```
**Conditions**: 
- Record exists in view
- Record does NOT exist in table

**Actions**: 
- Insert complete record with all columns
- Metadata set from view (typically: `InsertDatetime=CURRENT_TIMESTAMP`, `IsDeleted=0`)

#### Scenario 4: Soft Delete (Missing Records)
```sql
WHEN NOT MATCHED BY SOURCE AND TGT.IsDeleted = CAST(0 AS BIT)
  THEN UPDATE SET 
    TGT.ChangeHashKey = CONVERT(VARBINARY(32), 0),
    TGT.UpdateDatetime = CURRENT_TIMESTAMP,
    TGT.IsDeleted = CAST(1 AS BIT)
```
**Conditions**: 
- Record exists in table
- Record does NOT exist in view
- Record is currently active (`IsDeleted = 0`)

**Actions**: 
- Mark as deleted (`IsDeleted = 1`)
- Set `ChangeHashKey = 0` (sentinel value for deleted records)
- Update `UpdateDatetime` to track deletion time
- **Preserve** attribute data for historical reference

### C. Audit Logging via OUTPUT Clause

```sql
OUTPUT
    CURRENT_TIMESTAMP AS merge_datetime,
    CASE WHEN Inserted.IsDeleted = CAST(1 AS BIT) THEN N'DELETE' ELSE $action END AS merge_action,
    'Dim.LeggeRiferimento' AS full_olap_table_name,
    'AziendaID = ' + CAST(COALESCE(inserted.AziendaID, deleted.AziendaID) AS NVARCHAR)
        + ', LeggeRiferimentoID = ' + CAST(COALESCE(inserted.LeggeRiferimentoID, deleted.LeggeRiferimentoID) AS NVARCHAR) 
        AS primary_key_description
INTO audit.merge_log_details;
```

**Logged Information**:
- `merge_datetime`: Timestamp of operation
- `merge_action`: Operation type (`INSERT`, `UPDATE`, or `DELETE`)
  - Special logic: `IsDeleted=1` transitions logged as `DELETE` instead of `UPDATE`
- `full_olap_table_name`: Target table fully qualified name
- `primary_key_description`: Human-readable PK values for tracking affected records

**Audit Table Structure**:
```sql
CREATE TABLE audit.merge_log_details (
    merge_datetime           DATETIME NOT NULL DEFAULT(CURRENT_TIMESTAMP),
    merge_action             NVARCHAR(10) NOT NULL,
    full_olap_table_name     SYSNAME NOT NULL,
    primary_key_description  NVARCHAR(1000) NOT NULL
);
```

## Generator Stored Procedure Logic

### Input Parameters
- `@SourceSchema`: Schema name (e.g., `Dim`, `Fact`)
- `@SourceTable`: Table base name (e.g., `LeggeRiferimento`)

### Processing Steps

1. **Validate View Existence**
   ```sql
   -- View name: @SourceSchema.@SourceTable + 'View'
   -- Example: Dim.LeggeRiferimentoView
   IF NOT EXISTS (SELECT * FROM sys.views WHERE ...)
       RAISERROR('View not found', 16, 1);
   ```

2. **Retrieve View Column Metadata**
   ```sql
   SELECT 
       c.name AS column_name,
       t.name AS data_type,
       c.max_length,
       c.precision,
       c.scale,
       c.column_id
   FROM sys.columns c
   INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
   WHERE object_id = OBJECT_ID(@ViewName)
   ORDER BY c.column_id;
   ```

3. **Identify Column Categories**
   - Find position of first data-warehouse column
   - Columns before → Primary Keys
   - Data-warehouse columns → Metadata
   - Columns after → Attributes

4. **Generate DDL Script**
   - Build DROP statement (commented)
   - Build table creation block
   - Build ALTER COLUMN statements (PK columns NOT NULL, attribute columns commented)
   - Build PRIMARY KEY constraint

5. **Generate Merge Procedure**
   - Build MERGE statement with dynamic column lists
   - Build ON clause using all PK columns
   - Build UPDATE SET clause for attributes
   - Build INSERT column list and VALUES list
   - Build OUTPUT clause with concatenated PK description

6. **Output Complete Script**
   ```sql
   PRINT @GeneratedScript;
   ```

## Usage Example

```sql
EXEC dbo.usp_GenerateMergeTableFromView 
    @SourceSchema = 'Dim',
    @SourceTable = 'LeggeRiferimento';
```

**Output**: Complete T-SQL script ready to execute

## Benefits

✅ **Consistency**: All tables follow same structure pattern  
✅ **Automation**: Reduces manual coding errors  
✅ **Maintainability**: View changes automatically reflected in generated code  
✅ **Auditability**: Complete logging of all merge operations  
✅ **Idempotency**: Safe to regenerate and re-execute scripts  
✅ **Performance**: Optimized MERGE with hash-based change detection  

## Design Decisions

### Why Commented Attribute Constraints?
- Initial data loads may contain NULLs
- Allows gradual data quality improvement
- Can enforce constraints after data cleanup
- Prevents MERGE failures on incomplete data

### Why ChangeHashKey = 0 on Soft Delete?
- Sentinel value indicates "deleted" state
- Ensures hash comparison never matches (prevents resurrection)
- Distinguishes deleted records from active records with same hash

### Why Preserve Attribute Data on Delete?
- Historical analysis requirements
- Audit trail completeness
- Ability to "undelete" if needed
- Compliance with data retention policies

### Why Clustered Primary Key?
- Optimal for MERGE JOIN operations
- Physical ordering by business keys
- Efficient range scans
- Minimal fragmentation

## Limitations

- View MUST contain at least one data-warehouse column
- Data-warehouse columns must appear in specific order (or at least consistently)
- Primary key columns must appear before data-warehouse columns
- Attribute columns must appear after data-warehouse columns
- Column names cannot contain special characters that break dynamic SQL

## Extension Points

1. **Surrogate Key Support**: Add identity column generation
2. **Audit Columns**: Add CreatedBy/ModifiedBy user tracking
3. **Partitioning**: Generate partition scheme for large tables
4. **Indexes**: Auto-create indexes on frequently queried attributes
5. **Compression**: Apply row/page compression based on table size

---

**Version**: 1.0  
**Last Updated**: May 22, 2026  
**Pattern Type**: Code Generation / Metadata-Driven ETL
