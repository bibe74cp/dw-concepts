# Creating Table and Synchronization Flow from View Metadata - Requirements

## Table of Contents
- [Overview](#overview)
- [View Metadata Discovery](#view-metadata-discovery)
- [Landing Table Structure Conventions](#landing-table-structure-conventions)
- [BIML Architecture](#biml-architecture)
- [Metadata-to-BIML Mapping](#metadata-to-biml-mapping)
- [BIML Script Template](#biml-script-template)
- [Implementation Approach](#implementation-approach)
- [Complete Example](#complete-example)
- [Best Practices](#best-practices)

## Overview

This document describes the technical requirements and approach for generating **BIML (Business Intelligence Markup Language)** scripts that automate the creation of:
1. Landing table DDL (CREATE TABLE statements)
2. SSIS packages for synchronization flow

The automation leverages **view metadata** to discover the structure of source tables and generate consistent, standardized Landing tables and ETL packages.

### Goals

✅ **Eliminate Manual Coding**: Generate SSIS packages from metadata  
✅ **Ensure Consistency**: All tables follow the same structure and pattern  
✅ **Reduce Errors**: Automated generation prevents human mistakes  
✅ **Accelerate Development**: Create new landing tables in minutes, not hours  
✅ **Maintain Standards**: Enforce naming conventions and best practices  

### Prerequisites

- **SQL Server 2016+** with source and Landing databases
- **BIML Framework** (BimlStudio or BimlExpress)
- **SSIS 2016+** for package deployment
- **Source Views**: Views that represent the desired structure for Landing tables

### Approach Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Step 1: Query View Metadata                               │
│  - Primary keys                                             │
│  - Column names, types, nullability                        │
│  - Column order                                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 2: Classify Columns                                  │
│  - Primary Key columns (position 1..N)                     │
│  - DW Technical columns (ChangeHashKey, Insert/Update)     │
│  - Business columns (remaining)                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 3: Generate BIML                                     │
│  - Table DDL                                                │
│  - SSIS Package (Data Flow + Control Flow)                 │
│  - Package Variables and Parameters                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Step 4: Compile BIML → SSIS Package (.dtsx)               │
│  Deploy to SSISDB catalog                                  │
└─────────────────────────────────────────────────────────────┘
```

## View Metadata Discovery

### System Catalog Queries

SQL Server provides system views to interrogate database object metadata. Use these to discover view structure:

#### Query 1: Column Metadata

```sql
-- Get all columns from a view with their properties
SELECT 
    c.COLUMN_NAME,
    c.ORDINAL_POSITION,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.NUMERIC_PRECISION,
    c.NUMERIC_SCALE,
    c.IS_NULLABLE,
    c.COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'ERP'
    AND c.TABLE_NAME = 'CustomerView'
ORDER BY c.ORDINAL_POSITION;
```

**Result Example**:
```
COLUMN_NAME       ORDINAL_POSITION  DATA_TYPE    MAX_LENGTH  IS_NULLABLE
CompanyId         1                 int          NULL        NO
CustomerId        2                 int          NULL        NO
ChangeHashKey     3                 binary       32          NO
InsertDatetime    4                 datetime     NULL        NO
UpdateDatetime    5                 datetime     NULL        NO
IsDeleted         6                 bit          NULL        NO
CustomerName      7                 nvarchar     100         NO
VAT               8                 nvarchar     20          YES
```

#### Query 2: Primary Key Detection

```sql
-- Identify primary key columns from view's base table
-- Note: Views don't have PKs, but base tables do
SELECT 
    kcu.COLUMN_NAME,
    kcu.ORDINAL_POSITION
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
INNER JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
    ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
    AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
    AND tc.TABLE_NAME = kcu.TABLE_NAME
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
    AND tc.TABLE_SCHEMA = 'ERP'
    AND tc.TABLE_NAME = 'Customer'  -- Base table, not view
ORDER BY kcu.ORDINAL_POSITION;
```

**Result Example**:
```
COLUMN_NAME       ORDINAL_POSITION
CompanyId         1
CustomerId        2
```

#### Query 3: Comprehensive Metadata Query

```sql
-- Combined query for complete metadata
WITH ViewColumns AS (
    SELECT 
        c.COLUMN_NAME,
        c.ORDINAL_POSITION,
        c.DATA_TYPE,
        c.CHARACTER_MAXIMUM_LENGTH,
        c.NUMERIC_PRECISION,
        c.NUMERIC_SCALE,
        c.IS_NULLABLE
    FROM INFORMATION_SCHEMA.COLUMNS c
    WHERE c.TABLE_SCHEMA = @ViewSchema
        AND c.TABLE_NAME = @ViewName
),
PKColumns AS (
    -- Assume PK columns are detected by convention:
    -- Columns before ChangeHashKey are PK
    SELECT COLUMN_NAME
    FROM ViewColumns
    WHERE ORDINAL_POSITION < (
        SELECT MIN(ORDINAL_POSITION) 
        FROM ViewColumns 
        WHERE COLUMN_NAME = 'ChangeHashKey'
    )
)
SELECT 
    v.COLUMN_NAME,
    v.ORDINAL_POSITION,
    v.DATA_TYPE,
    v.CHARACTER_MAXIMUM_LENGTH,
    v.NUMERIC_PRECISION,
    v.NUMERIC_SCALE,
    v.IS_NULLABLE,
    CASE 
        WHEN p.COLUMN_NAME IS NOT NULL THEN 1
        ELSE 0
    END AS IsPrimaryKey,
    CASE 
        WHEN v.COLUMN_NAME IN ('ChangeHashKey', 'InsertDatetime', 'UpdateDatetime', 'IsDeleted')
        THEN 1
        ELSE 0
    END AS IsTechnicalColumn
FROM ViewColumns v
LEFT JOIN PKColumns p ON v.COLUMN_NAME = p.COLUMN_NAME
ORDER BY v.ORDINAL_POSITION;
```

### Metadata Discovery Result

The metadata query should return a dataset that can be consumed by the BIML generator:

```xml
<Columns>
    <Column Name="CompanyId" Ordinal="1" DataType="int" IsNullable="false" IsPK="true" IsTechnical="false" />
    <Column Name="CustomerId" Ordinal="2" DataType="int" IsNullable="false" IsPK="true" IsTechnical="false" />
    <Column Name="ChangeHashKey" Ordinal="3" DataType="binary" Length="32" IsNullable="false" IsPK="false" IsTechnical="true" />
    <Column Name="InsertDatetime" Ordinal="4" DataType="datetime" IsNullable="false" IsPK="false" IsTechnical="true" />
    <Column Name="UpdateDatetime" Ordinal="5" DataType="datetime" IsNullable="false" IsPK="false" IsTechnical="true" />
    <Column Name="IsDeleted" Ordinal="6" DataType="bit" IsNullable="false" IsPK="false" IsTechnical="true" />
    <Column Name="CustomerName" Ordinal="7" DataType="nvarchar" Length="100" IsNullable="false" IsPK="false" IsTechnical="false" />
    <Column Name="VAT" Ordinal="8" DataType="nvarchar" Length="20" IsNullable="true" IsPK="false" IsTechnical="false" />
</Columns>
```

## Landing Table Structure Conventions

### Column Ordering Rules

Every Landing table MUST follow this exact structure:

```
Position  Category           Columns                                Rules
───────────────────────────────────────────────────────────────────────────────
1..N      PRIMARY KEY        Business key columns                   NOT NULL
                             (e.g., CompanyId, CustomerId)          CLUSTERED PK

N+1       TECHNICAL          ChangeHashKey                          BINARY(32) NOT NULL
N+2       TECHNICAL          InsertDatetime                         DATETIME NOT NULL
N+3       TECHNICAL          UpdateDatetime                         DATETIME NOT NULL  
N+4       TECHNICAL          IsDeleted                              BIT NOT NULL

N+5..M    BUSINESS           Remaining business columns             Varies (nullable)
                             (e.g., CustomerName, VAT)
```

### Data Type Mapping

Map SQL Server data types from view to Landing table:

| View Type | Landing Type | Notes |
|-----------|--------------|-------|
| `int`, `bigint`, `smallint`, `tinyint` | Same | Exact numeric types preserved |
| `decimal(p,s)`, `numeric(p,s)` | Same | Precision and scale preserved |
| `varchar(n)`, `nvarchar(n)` | Same | Length preserved |
| `varchar(max)`, `nvarchar(max)` | Same | MAX preserved |
| `char(n)`, `nchar(n)` | `varchar(n)`, `nvarchar(n)` | Convert fixed to variable |
| `datetime`, `datetime2`, `date`, `time` | Same | Temporal types preserved |
| `bit` | `bit` | Boolean preserved |
| `uniqueidentifier` | Same | GUID preserved |
| `binary(n)`, `varbinary(n)` | Same | Binary preserved |

### Nullability Rules

| Column Category | Nullability Rule |
|-----------------|------------------|
| Primary Key | Always `NOT NULL` |
| ChangeHashKey | Always `NOT NULL` |
| InsertDatetime | Always `NOT NULL` |
| UpdateDatetime | Always `NOT NULL` |
| IsDeleted | Always `NOT NULL` (DEFAULT 0) |
| Business Columns | As defined in view metadata |

### Index Requirements

Every Landing table requires these indexes:

```sql
-- 1. Primary Key (Clustered)
CONSTRAINT [PK_{Schema}_{Table}] PRIMARY KEY CLUSTERED 
(
    {PrimaryKeyColumns}
)

-- 2. Hash Index (Non-Clustered)
CREATE NONCLUSTERED INDEX [IX_{Schema}_{Table}_ChangeHashKey] 
    ON [{LandingSchema}].[{Table}] ([ChangeHashKey]);

-- 3. Temporal Index (Non-Clustered)
CREATE NONCLUSTERED INDEX [IX_{Schema}_{Table}_Temporal] 
    ON [{LandingSchema}].[{Table}] ([UpdateDatetime], [IsDeleted]);
```

## BIML Architecture

### BIML Overview

**BIML (Business Intelligence Markup Language)** is an XML-based language for defining SSIS packages, tables, and other BI artifacts. BIML compiles to native SSIS `.dtsx` files.

### BIML Components for Synchronization

A complete synchronization solution requires these BIML components:

```xml
<Biml xmlns="http://schemas.varigence.com/biml.xsd">
    
    <!-- 1. Connections -->
    <Connections>
        <Connection Name="Source" ... />
        <Connection Name="Landing" ... />
    </Connections>
    
    <!-- 2. Tables -->
    <Tables>
        <Table Name="Customer" SchemaName="ERP" ConnectionName="Landing">
            <!-- Column definitions -->
        </Table>
    </Tables>
    
    <!-- 3. Packages -->
    <Packages>
        <Package Name="Load_ERP_Customer" ConstraintMode="Linear">
            <!-- Variables, tasks, data flows -->
        </Package>
    </Packages>
    
</Biml>
```

### BIML Compilation Process

```
BIML Script (.biml)
    ↓
BimlStudio/BimlExpress Compiler
    ↓
SSIS Package (.dtsx)
    ↓
SQL Server SSIS Catalog (SSISDB)
```

## Metadata-to-BIML Mapping

### Step 1: Generate Table DDL BIML

From view metadata, generate the `<Table>` element:

**Metadata Input**:
```json
{
    "Schema": "ERP",
    "Table": "Customer",
    "Columns": [
        {"Name": "CompanyId", "DataType": "int", "IsNullable": false, "IsPK": true},
        {"Name": "CustomerId", "DataType": "int", "IsNullable": false, "IsPK": true},
        {"Name": "ChangeHashKey", "DataType": "binary", "Length": 32, "IsNullable": false},
        {"Name": "InsertDatetime", "DataType": "datetime", "IsNullable": false},
        {"Name": "UpdateDatetime", "DataType": "datetime", "IsNullable": false},
        {"Name": "IsDeleted", "DataType": "bit", "IsNullable": false},
        {"Name": "CustomerName", "DataType": "nvarchar", "Length": 100, "IsNullable": false},
        {"Name": "VAT", "DataType": "nvarchar", "Length": 20, "IsNullable": true}
    ]
}
```

**BIML Output**:
```xml
<Table Name="Customer" SchemaName="ERP" ConnectionName="Landing">
    <Columns>
        <!-- Primary Key Columns -->
        <Column Name="CompanyId" DataType="Int32" IsNullable="false" />
        <Column Name="CustomerId" DataType="Int32" IsNullable="false" />
        
        <!-- Technical Columns -->
        <Column Name="ChangeHashKey" DataType="Binary" Length="32" IsNullable="false" />
        <Column Name="InsertDatetime" DataType="DateTime" IsNullable="false" 
                Default="CURRENT_TIMESTAMP" />
        <Column Name="UpdateDatetime" DataType="DateTime" IsNullable="false" 
                Default="CURRENT_TIMESTAMP" />
        <Column Name="IsDeleted" DataType="Boolean" IsNullable="false" Default="0" />
        
        <!-- Business Columns -->
        <Column Name="CustomerName" DataType="String" Length="100" IsNullable="false" />
        <Column Name="VAT" DataType="String" Length="20" IsNullable="true" />
    </Columns>
    
    <Keys>
        <PrimaryKey Name="PK_ERP_Customer">
            <Columns>
                <Column ColumnName="CompanyId" />
                <Column ColumnName="CustomerId" />
            </Columns>
        </PrimaryKey>
    </Keys>
    
    <Indexes>
        <Index Name="IX_ERP_Customer_ChangeHashKey">
            <Columns>
                <Column ColumnName="ChangeHashKey" />
            </Columns>
        </Index>
        <Index Name="IX_ERP_Customer_Temporal">
            <Columns>
                <Column ColumnName="UpdateDatetime" />
                <Column ColumnName="IsDeleted" />
            </Columns>
        </Index>
    </Indexes>
</Table>
```

### Step 2: Generate Package Variables BIML

Create package-level variables from metadata:

```xml
<Variables>
    <!-- Source Metadata -->
    <Variable Name="SourceServer" DataType="String" 
              EvaluateAsExpression="false">ERP_PROD_SERVER</Variable>
    <Variable Name="SourceDatabase" DataType="String" 
              EvaluateAsExpression="false">ERP_Production</Variable>
    <Variable Name="SourceSchema" DataType="String" 
              EvaluateAsExpression="false">dbo</Variable>
    <Variable Name="SourceTable" DataType="String" 
              EvaluateAsExpression="false">Customer</Variable>
    
    <!-- Landing Metadata -->
    <Variable Name="LandingSchema" DataType="String" 
              EvaluateAsExpression="false">ERP</Variable>
    <Variable Name="LandingTable" DataType="String" 
              EvaluateAsExpression="false">Customer</Variable>
    
    <!-- Column Lists (generated from metadata) -->
    <Variable Name="PKColumns" DataType="String" 
              EvaluateAsExpression="false">CompanyId,CustomerId</Variable>
    <Variable Name="HashColumns" DataType="String" 
              EvaluateAsExpression="false">CustomerName,VAT</Variable>
    
    <!-- Metrics -->
    <Variable Name="RecordsInserted" DataType="Int32">0</Variable>
    <Variable Name="RecordsUpdated" DataType="Int32">0</Variable>
    <Variable Name="RecordsDeleted" DataType="Int32">0</Variable>
    <Variable Name="ExecutionStart" DataType="DateTime">1/1/1900</Variable>
</Variables>
```

### Step 3: Generate Source Query BIML

Build the source extraction query with hash calculation:

**Logic**:
1. Include all PK columns
2. Calculate `HASHBYTES('SHA2_256', CONCAT(...))` for non-PK, non-technical columns
3. Include all business columns

**Generated SQL** (from metadata):
```sql
SELECT 
    -- PK Columns
    CompanyId,
    CustomerId,
    
    -- Hash Calculation (only business columns)
    HASHBYTES('SHA2_256', 
        CONCAT(
            CustomerName, '|',
            ISNULL(VAT, '')
        )
    ) AS ChangeHashKey,
    
    -- Business Columns
    CustomerName,
    VAT

FROM [ERP].[dbo].[Customer]
```

**BIML for OLE DB Source**:
```xml
<OleDbSource Name="Extract from Source" ConnectionName="Source">
    <DirectInput>
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
    </DirectInput>
</OleDbSource>
```

### Step 4: Generate Data Flow BIML

Complete data flow with lookup, conditional split, and destinations:

```xml
<Dataflow Name="Load Customer Data">
    <Transformations>
        
        <!-- Source -->
        <OleDbSource Name="Extract from Source" ConnectionName="Source">
            <DirectInput>{SourceQuery}</DirectInput>
        </OleDbSource>
        
        <!-- Lookup Existing Records -->
        <Lookup Name="Lookup Landing" 
                OleDbConnectionName="Landing"
                NoMatchBehavior="RedirectRowsToNoMatchOutput">
            <DirectInput>
                SELECT CompanyId, CustomerId, ChangeHashKey, IsDeleted
                FROM [Landing].[ERP].[Customer]
            </DirectInput>
            <Inputs>
                <Column SourceColumn="CompanyId" TargetColumn="CompanyId" />
                <Column SourceColumn="CustomerId" TargetColumn="CustomerId" />
            </Inputs>
            <Outputs>
                <Column SourceColumn="ChangeHashKey" TargetColumn="Landing_ChangeHashKey" />
            </Outputs>
        </Lookup>
        
        <!-- Split Changed vs Unchanged -->
        <ConditionalSplit Name="Check for Changes">
            <OutputPaths>
                <OutputPath Name="Changed">
                    <Expression>Source_ChangeHashKey != Landing_ChangeHashKey</Expression>
                </OutputPath>
            </OutputPaths>
        </ConditionalSplit>
        
        <!-- Insert New Records -->
        <OleDbDestination Name="Insert New" ConnectionName="Landing"
                          TableName="ERP.Customer">
            <InputPath OutputPathName="Lookup Landing.NoMatch" />
            <Columns>
                <Column SourceColumn="CompanyId" TargetColumn="CompanyId" />
                <Column SourceColumn="CustomerId" TargetColumn="CustomerId" />
                <Column SourceColumn="ChangeHashKey" TargetColumn="ChangeHashKey" />
                <Column SourceColumn="CustomerName" TargetColumn="CustomerName" />
                <Column SourceColumn="VAT" TargetColumn="VAT" />
            </Columns>
        </OleDbDestination>
        
        <!-- Update Changed Records -->
        <OleDbCommand Name="Update Changed" ConnectionName="Landing">
            <InputPath OutputPathName="Check for Changes.Changed" />
            <CommandText>
                UPDATE [Landing].[ERP].[Customer]
                SET ChangeHashKey = ?,
                    UpdateDatetime = CURRENT_TIMESTAMP,
                    CustomerName = ?,
                    VAT = ?
                WHERE CompanyId = ? AND CustomerId = ?
            </CommandText>
            <Parameters>
                <Parameter SourceColumn="ChangeHashKey" TargetColumn="Param_0" />
                <Parameter SourceColumn="CustomerName" TargetColumn="Param_1" />
                <Parameter SourceColumn="VAT" TargetColumn="Param_2" />
                <Parameter SourceColumn="CompanyId" TargetColumn="Param_3" />
                <Parameter SourceColumn="CustomerId" TargetColumn="Param_4" />
            </Parameters>
        </OleDbCommand>
        
    </Transformations>
</Dataflow>
```

### Step 5: Generate Soft Delete Task BIML

Execute SQL task for soft deletes:

```xml
<ExecuteSQL Name="Soft Delete Missing" ConnectionName="Landing">
    <DirectInput>
        UPDATE t
        SET UpdateDatetime = CURRENT_TIMESTAMP,
            IsDeleted = 1
        FROM [Landing].[ERP].[Customer] t
        WHERE t.IsDeleted = 0
            AND NOT EXISTS (
                SELECT 1 
                FROM #Staging_ERP_Customer s
                WHERE s.CompanyId = t.CompanyId 
                    AND s.CustomerId = t.CustomerId
            );
        
        SELECT @@ROWCOUNT AS DeletedCount;
    </DirectInput>
    <Results>
        <Result Name="0" VariableName="User.RecordsDeleted" />
    </Results>
</ExecuteSQL>
```

## BIML Script Template

### Complete BIML Package Template

This template uses **parameterized metadata** to generate packages:

```xml
<Biml xmlns="http://schemas.varigence.com/biml.xsd">
    
    <!-- ================================================================ -->
    <!-- METADATA PARAMETERS (Replace with actual values)                -->
    <!-- ================================================================ -->
    <!-- 
    @SourceServer       = ERP_PROD_SERVER
    @SourceDatabase     = ERP_Production
    @SourceSchema       = dbo
    @SourceTable        = Customer
    @LandingSchema      = ERP
    @LandingTable       = Customer
    @PKColumns          = CompanyId,CustomerId
    @BusinessColumns    = CustomerName,VAT
    @ViewSchema         = ERP
    @ViewName           = CustomerView
    -->
    
    <!-- ================================================================ -->
    <!-- CONNECTIONS                                                      -->
    <!-- ================================================================ -->
    <Connections>
        <Connection Name="Source" ConnectionString="Data Source=@SourceServer;Initial Catalog=@SourceDatabase;Provider=SQLNCLI11;Integrated Security=SSPI;" />
        <Connection Name="Landing" ConnectionString="Data Source=LANDING_SERVER;Initial Catalog=Landing;Provider=SQLNCLI11;Integrated Security=SSPI;" />
    </Connections>
    
    <!-- ================================================================ -->
    <!-- TABLES                                                           -->
    <!-- ================================================================ -->
    <Tables>
        <Table Name="@LandingTable" SchemaName="@LandingSchema" ConnectionName="Landing">
            <Columns>
                <!-- PRIMARY KEY COLUMNS (from metadata) -->
                <!-- REPEAT for each PK column -->
                <Column Name="CompanyId" DataType="Int32" IsNullable="false" />
                <Column Name="CustomerId" DataType="Int32" IsNullable="false" />
                
                <!-- TECHNICAL COLUMNS (fixed structure) -->
                <Column Name="ChangeHashKey" DataType="Binary" Length="32" IsNullable="false" />
                <Column Name="InsertDatetime" DataType="DateTime" IsNullable="false" Default="CURRENT_TIMESTAMP" />
                <Column Name="UpdateDatetime" DataType="DateTime" IsNullable="false" Default="CURRENT_TIMESTAMP" />
                <Column Name="IsDeleted" DataType="Boolean" IsNullable="false" Default="0" />
                
                <!-- BUSINESS COLUMNS (from metadata) -->
                <!-- REPEAT for each business column -->
                <Column Name="CustomerName" DataType="String" Length="100" IsNullable="false" />
                <Column Name="VAT" DataType="String" Length="20" IsNullable="true" />
            </Columns>
            
            <Keys>
                <PrimaryKey Name="PK_@LandingSchema_@LandingTable">
                    <Columns>
                        <!-- REPEAT for each PK column -->
                        <Column ColumnName="CompanyId" />
                        <Column ColumnName="CustomerId" />
                    </Columns>
                </PrimaryKey>
            </Keys>
            
            <Indexes>
                <Index Name="IX_@LandingSchema_@LandingTable_ChangeHashKey">
                    <Columns>
                        <Column ColumnName="ChangeHashKey" />
                    </Columns>
                </Index>
                <Index Name="IX_@LandingSchema_@LandingTable_Temporal">
                    <Columns>
                        <Column ColumnName="UpdateDatetime" />
                        <Column ColumnName="IsDeleted" />
                    </Columns>
                </Index>
            </Indexes>
        </Table>
    </Tables>
    
    <!-- ================================================================ -->
    <!-- PACKAGE                                                          -->
    <!-- ================================================================ -->
    <Packages>
        <Package Name="Load_@LandingSchema_@LandingTable" 
                 ConstraintMode="Linear"
                 ProtectionLevel="EncryptSensitiveWithUserKey">
            
            <!-- PACKAGE VARIABLES -->
            <Variables>
                <Variable Name="SourceServer" DataType="String">@SourceServer</Variable>
                <Variable Name="SourceDatabase" DataType="String">@SourceDatabase</Variable>
                <Variable Name="SourceSchema" DataType="String">@SourceSchema</Variable>
                <Variable Name="SourceTable" DataType="String">@SourceTable</Variable>
                <Variable Name="LandingSchema" DataType="String">@LandingSchema</Variable>
                <Variable Name="LandingTable" DataType="String">@LandingTable</Variable>
                <Variable Name="PKColumns" DataType="String">@PKColumns</Variable>
                <Variable Name="HashColumns" DataType="String">@BusinessColumns</Variable>
                <Variable Name="RecordsInserted" DataType="Int32">0</Variable>
                <Variable Name="RecordsUpdated" DataType="Int32">0</Variable>
                <Variable Name="RecordsDeleted" DataType="Int32">0</Variable>
                <Variable Name="ExecutionStart" DataType="DateTime">1/1/1900</Variable>
            </Variables>
            
            <!-- CONTROL FLOW TASKS -->
            <Tasks>
                
                <!-- Task 1: Set Execution Start -->
                <ExecuteSQL Name="Set Execution Start" ConnectionName="Landing">
                    <DirectInput>SELECT GETDATE()</DirectInput>
                    <Results>
                        <Result Name="0" VariableName="User.ExecutionStart" />
                    </Results>
                </ExecuteSQL>
                
                <!-- Task 2: Create/Truncate Staging -->
                <ExecuteSQL Name="Create Staging Table" ConnectionName="Landing">
                    <DirectInput><![CDATA[
                        IF OBJECT_ID('tempdb..#Staging_@LandingSchema_@LandingTable') IS NOT NULL
                            DROP TABLE #Staging_@LandingSchema_@LandingTable;
                        
                        CREATE TABLE #Staging_@LandingSchema_@LandingTable
                        (
                            -- PK Columns
                            CompanyId INT,
                            CustomerId INT,
                            -- Hash
                            ChangeHashKey BINARY(32),
                            -- Business Columns
                            CustomerName NVARCHAR(100),
                            VAT NVARCHAR(20)
                        );
                    ]]></DirectInput>
                </ExecuteSQL>
                
                <!-- Task 3: Data Flow - Extract and Load -->
                <Dataflow Name="Extract and Load to Staging">
                    <Transformations>
                        
                        <!-- Source with Hash Calculation -->
                        <OleDbSource Name="Extract from Source" ConnectionName="Source">
                            <DirectInput><![CDATA[
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
                                FROM [@SourceSchema].[@SourceTable]
                            ]]></DirectInput>
                        </OleDbSource>
                        
                        <!-- Destination: Staging Table -->
                        <OleDbDestination Name="Load to Staging" 
                                          ConnectionName="Landing"
                                          TableName="#Staging_@LandingSchema_@LandingTable"
                                          UseFastLoadIfAvailable="true">
                            <InputPath OutputPathName="Extract from Source.Output" />
                        </OleDbDestination>
                        
                    </Transformations>
                </Dataflow>
                
                <!-- Task 4: MERGE Staging to Landing -->
                <ExecuteSQL Name="Merge to Landing" ConnectionName="Landing">
                    <DirectInput><![CDATA[
                        MERGE [Landing].[@LandingSchema].[@LandingTable] AS target
                        USING #Staging_@LandingSchema_@LandingTable AS source
                            ON target.CompanyId = source.CompanyId 
                            AND target.CustomerId = source.CustomerId
                        
                        WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
                            UPDATE SET
                                ChangeHashKey = source.ChangeHashKey,
                                UpdateDatetime = CURRENT_TIMESTAMP,
                                CustomerName = source.CustomerName,
                                VAT = source.VAT
                        
                        WHEN NOT MATCHED BY TARGET THEN
                            INSERT (CompanyId, CustomerId, ChangeHashKey, 
                                    InsertDatetime, UpdateDatetime, IsDeleted,
                                    CustomerName, VAT)
                            VALUES (source.CompanyId, source.CustomerId, source.ChangeHashKey,
                                    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
                                    source.CustomerName, source.VAT)
                        
                        WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
                            UPDATE SET
                                UpdateDatetime = CURRENT_TIMESTAMP,
                                IsDeleted = 1;
                    ]]></DirectInput>
                </ExecuteSQL>
                
                <!-- Task 5: Log Execution -->
                <ExecuteSQL Name="Log Execution" ConnectionName="Landing">
                    <DirectInput><![CDATA[
                        INSERT INTO [audit].[ETLLog]
                        (PackageName, SourceSchema, SourceTable, ExecutionStart, Status)
                        VALUES (
                            'Load_@LandingSchema_@LandingTable',
                            '@SourceSchema',
                            '@SourceTable',
                            ?,
                            'Success'
                        );
                    ]]></DirectInput>
                    <Parameters>
                        <Parameter Name="0" VariableName="User.ExecutionStart" DataType="DateTime" />
                    </Parameters>
                </ExecuteSQL>
                
            </Tasks>
            
        </Package>
    </Packages>
    
</Biml>
```

## Implementation Approach

### Approach 1: BimlScript with C# (Recommended)

Use **BimlScript** to dynamically generate BIML from metadata queries:

```xml
<#@ template tier="1" #>
<#@ import namespace="System.Data" #>

<# 
    // Query view metadata
    var viewSchema = "ERP";
    var viewName = "CustomerView";
    
    var metadataQuery = string.Format(@"
        SELECT 
            c.COLUMN_NAME,
            c.ORDINAL_POSITION,
            c.DATA_TYPE,
            c.CHARACTER_MAXIMUM_LENGTH,
            c.IS_NULLABLE
        FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA = '{0}'
            AND c.TABLE_NAME = '{1}'
        ORDER BY c.ORDINAL_POSITION
    ", viewSchema, viewName);
    
    // Execute query against Landing database
    var dt = ExternalDataAccess.GetDataTable("Landing", metadataQuery);
    
    // Classify columns
    var pkColumns = new List<DataRow>();
    var technicalColumns = new List<DataRow>();
    var businessColumns = new List<DataRow>();
    
    foreach (DataRow row in dt.Rows)
    {
        var colName = row["COLUMN_NAME"].ToString();
        
        if (new[] {"ChangeHashKey", "InsertDatetime", "UpdateDatetime", "IsDeleted"}.Contains(colName))
        {
            technicalColumns.Add(row);
        }
        else if (row["ORDINAL_POSITION"] < /* first technical column position */)
        {
            pkColumns.Add(row);
        }
        else
        {
            businessColumns.Add(row);
        }
    }
#>

<Biml xmlns="http://schemas.varigence.com/biml.xsd">
    <Tables>
        <Table Name="<#= viewName.Replace("View", "") #>" SchemaName="<#= viewSchema #>">
            <Columns>
                <!-- PK Columns -->
                <# foreach (var col in pkColumns) { #>
                <Column Name="<#= col["COLUMN_NAME"] #>" 
                        DataType="<#= GetBimlDataType(col) #>" 
                        IsNullable="false" />
                <# } #>
                
                <!-- Technical Columns -->
                <# foreach (var col in technicalColumns) { #>
                <Column Name="<#= col["COLUMN_NAME"] #>" 
                        DataType="<#= GetBimlDataType(col) #>" 
                        IsNullable="false" />
                <# } #>
                
                <!-- Business Columns -->
                <# foreach (var col in businessColumns) { #>
                <Column Name="<#= col["COLUMN_NAME"] #>" 
                        DataType="<#= GetBimlDataType(col) #>" 
                        IsNullable="<#= col["IS_NULLABLE"].ToString().ToLower() #>" />
                <# } #>
            </Columns>
        </Table>
    </Tables>
</Biml>

<#+
    // Helper function to map SQL types to BIML types
    public string GetBimlDataType(DataRow col)
    {
        var sqlType = col["DATA_TYPE"].ToString().ToLower();
        var length = col["CHARACTER_MAXIMUM_LENGTH"];
        
        switch (sqlType)
        {
            case "int": return "Int32";
            case "bigint": return "Int64";
            case "smallint": return "Int16";
            case "tinyint": return "Byte";
            case "bit": return "Boolean";
            case "datetime": return "DateTime";
            case "binary": return $"Binary\" Length=\"{length}";
            case "nvarchar": return $"String\" Length=\"{length}";
            case "varchar": return $"AnsiString\" Length=\"{length}";
            default: return "String";
        }
    }
#>
```

### Approach 2: Metadata-Driven Configuration File

Create a **JSON/XML configuration file** listing all views to process:

```json
{
    "Tables": [
        {
            "SourceServer": "ERP_PROD_SERVER",
            "SourceDatabase": "ERP_Production",
            "SourceSchema": "dbo",
            "SourceTable": "Customer",
            "ViewSchema": "ERP",
            "ViewName": "CustomerView",
            "LandingSchema": "ERP",
            "LandingTable": "Customer"
        },
        {
            "SourceServer": "CRM_PROD_SERVER",
            "SourceDatabase": "Salesforce",
            "SourceSchema": "dbo",
            "SourceTable": "Account",
            "ViewSchema": "SALESFORCE",
            "ViewName": "AccountView",
            "LandingSchema": "SALESFORCE",
            "LandingTable": "Account"
        }
    ]
}
```

**BimlScript** iterates over configuration:

```xml
<#@ template tier="1" #>
<#@ import namespace="Newtonsoft.Json" #>
<#@ import namespace="System.IO" #>

<# 
    var configPath = @"C:\Projects\DW\Config\Tables.json";
    var json = File.ReadAllText(configPath);
    var config = JsonConvert.DeserializeObject<Configuration>(json);
#>

<Biml xmlns="http://schemas.varigence.com/biml.xsd">
    <Packages>
        <# foreach (var table in config.Tables) { #>
        
        <!-- Generate package for <#= table.LandingTable #> -->
        <Package Name="Load_<#= table.LandingSchema #>_<#= table.LandingTable #>">
            <!-- ... package content ... -->
        </Package>
        
        <# } #>
    </Packages>
</Biml>
```

### Approach 3: T-SQL Code Generator

Create a **stored procedure** that generates BIML as text:

```sql
CREATE PROCEDURE [dbo].[GenerateBIML]
    @ViewSchema NVARCHAR(50),
    @ViewName NVARCHAR(100)
AS
BEGIN
    DECLARE @BIML NVARCHAR(MAX) = '';
    
    -- Generate Table BIML
    SET @BIML = @BIML + '<Table Name="' + REPLACE(@ViewName, 'View', '') + '" SchemaName="' + @ViewSchema + '">' + CHAR(13);
    SET @BIML = @BIML + '  <Columns>' + CHAR(13);
    
    -- Loop through columns
    SELECT @BIML = @BIML + 
        '    <Column Name="' + COLUMN_NAME + '" ' +
        'DataType="' + dbo.GetBimlType(DATA_TYPE, CHARACTER_MAXIMUM_LENGTH) + '" ' +
        'IsNullable="' + LOWER(IS_NULLABLE) + '" />' + CHAR(13)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @ViewSchema
        AND TABLE_NAME = @ViewName
    ORDER BY ORDINAL_POSITION;
    
    SET @BIML = @BIML + '  </Columns>' + CHAR(13);
    SET @BIML = @BIML + '</Table>' + CHAR(13);
    
    -- Return BIML
    SELECT @BIML AS BimlXml;
END
```

## Complete Example

### Scenario: Generate Landing Table and Package for Customer

**Input: View Definition**

```sql
CREATE VIEW [ERP].[CustomerView]
AS
SELECT
    c.CompanyId,
    c.CustomerId,
    c.ChangeHashKey,
    c.InsertDatetime,
    c.UpdateDatetime,
    c.IsDeleted,
    c.CustomerName AS Name,
    c.VAT AS TaxIdentifier,
    ct.CategoryName AS Category
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
WHERE c.IsDeleted = 0;
```

**Step 1: Query Metadata**

```sql
EXEC [dbo].[GetViewMetadata] 
    @ViewSchema = 'ERP', 
    @ViewName = 'CustomerView';
```

**Result**:
```
COLUMN_NAME       ORDINAL  DATA_TYPE  LENGTH  IS_NULLABLE  IsPK  IsTechnical
CompanyId         1        int        NULL    NO           1     0
CustomerId        2        int        NULL    NO           1     0
ChangeHashKey     3        binary     32      NO           0     1
InsertDatetime    4        datetime   NULL    NO           0     1
UpdateDatetime    5        datetime   NULL    NO           0     1
IsDeleted         6        bit        NULL    NO           0     1
Name              7        nvarchar   100     NO           0     0
TaxIdentifier     8        nvarchar   20      YES          0     0
Category          9        nvarchar   50      YES          0     0
```

**Step 2: Generate Table BIML**

```xml
<Table Name="Customer" SchemaName="ERP" ConnectionName="Landing">
    <Columns>
        <!-- Primary Keys -->
        <Column Name="CompanyId" DataType="Int32" IsNullable="false" />
        <Column Name="CustomerId" DataType="Int32" IsNullable="false" />
        
        <!-- Technical -->
        <Column Name="ChangeHashKey" DataType="Binary" Length="32" IsNullable="false" />
        <Column Name="InsertDatetime" DataType="DateTime" IsNullable="false" />
        <Column Name="UpdateDatetime" DataType="DateTime" IsNullable="false" />
        <Column Name="IsDeleted" DataType="Boolean" IsNullable="false" />
        
        <!-- Business -->
        <Column Name="Name" DataType="String" Length="100" IsNullable="false" />
        <Column Name="TaxIdentifier" DataType="String" Length="20" IsNullable="true" />
        <Column Name="Category" DataType="String" Length="50" IsNullable="true" />
    </Columns>
    
    <Keys>
        <PrimaryKey Name="PK_ERP_Customer">
            <Columns>
                <Column ColumnName="CompanyId" />
                <Column ColumnName="CustomerId" />
            </Columns>
        </PrimaryKey>
    </Keys>
    
    <Indexes>
        <Index Name="IX_ERP_Customer_ChangeHashKey">
            <Columns>
                <Column ColumnName="ChangeHashKey" />
            </Columns>
        </Index>
        <Index Name="IX_ERP_Customer_Temporal">
            <Columns>
                <Column ColumnName="UpdateDatetime" />
                <Column ColumnName="IsDeleted" />
            </Columns>
        </Index>
    </Indexes>
</Table>
```

**Step 3: Generate Source Query**

```sql
SELECT 
    CompanyId,
    CustomerId,
    HASHBYTES('SHA2_256', 
        CONCAT(
            Name, '|',
            ISNULL(TaxIdentifier, ''), '|',
            ISNULL(Category, '')
        )
    ) AS ChangeHashKey,
    Name,
    TaxIdentifier,
    Category
FROM [ERP].[dbo].[Customer]
```

**Step 4: Compile BIML → SSIS**

- Open BimlStudio
- Load generated .biml file
- Right-click project → Build
- Deploys `Load_ERP_Customer.dtsx` to SSISDB

**Step 5: Execute Package**

```sql
-- Execute via T-SQL
EXEC [SSISDB].[catalog].[create_execution] 
    @package_name = 'Load_ERP_Customer.dtsx',
    @folder_name = 'Landing',
    @project_name = 'LandingETL',
    @execution_id = @exec_id OUTPUT;

EXEC [SSISDB].[catalog].[start_execution] @exec_id;
```

## Best Practices

### 1. Metadata Validation

Before generating BIML, validate view metadata:

```sql
-- Check 1: View exists
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.VIEWS
    WHERE TABLE_SCHEMA = @ViewSchema AND TABLE_NAME = @ViewName
)
    RAISERROR('View does not exist', 16, 1);

-- Check 2: Contains required technical columns
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @ViewSchema 
        AND TABLE_NAME = @ViewName
        AND COLUMN_NAME IN ('ChangeHashKey', 'InsertDatetime', 'UpdateDatetime', 'IsDeleted')
    HAVING COUNT(*) = 4
)
    RAISERROR('View missing required technical columns', 16, 1);

-- Check 3: PK columns are defined
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @ViewSchema 
        AND TABLE_NAME = @ViewName
        AND ORDINAL_POSITION < (
            SELECT MIN(ORDINAL_POSITION) 
            FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_SCHEMA = @ViewSchema 
                AND TABLE_NAME = @ViewName 
                AND COLUMN_NAME = 'ChangeHashKey'
        )
)
    RAISERROR('View has no primary key columns', 16, 1);
```

### 2. Version Control BIML

- Store BIML scripts in Git/TFS
- Tag with version numbers
- Include metadata query results for reference
- Document generation parameters

### 3. Template Reusability

Create **base templates** for common patterns:

```
Templates/
├── LandingTable.biml           (Table DDL template)
├── SyncPackage_Staging.biml    (Staging approach)
├── SyncPackage_Direct.biml     (Direct flow approach)
└── SyncPackage_Hybrid.biml     (Hybrid approach)
```

### 4. Error Handling in Generated Packages

Ensure all generated packages include:

- Transaction management
- Error logging to `audit.ETLError`
- Retry logic configuration
- Event handlers for failures

### 5. Performance Configuration

Generated packages should include optimized settings:

```xml
<!-- Data Flow optimizations -->
<Dataflow EngineThreads="10" 
          DefaultBufferMaxRows="10000"
          DefaultBufferSize="10485760">
    <!-- ... -->
</Dataflow>

<!-- OLE DB Destination fast load -->
<OleDbDestination UseFastLoadIfAvailable="true"
                  TableLock="true"
                  CheckConstraints="false">
    <!-- ... -->
</OleDbDestination>
```

### 6. Documentation Generation

Automatically generate documentation alongside BIML:

```markdown
# Package: Load_ERP_Customer

## Source
- Server: ERP_PROD_SERVER
- Database: ERP_Production
- Table: dbo.Customer

## Destination
- Database: Landing
- Schema: ERP
- Table: Customer

## Columns
- **Primary Key**: CompanyId, CustomerId
- **Hash Columns**: Name, TaxIdentifier, Category
- **Total Columns**: 9

## Generated
- Date: 2026-05-21
- BIML Version: 1.0
- Generator: MetadataToBIML v2.3
```

---

## Summary

This metadata-driven approach to BIML generation provides:

✅ **Automation**: Generate tables and packages from view metadata  
✅ **Consistency**: All artifacts follow the same pattern  
✅ **Efficiency**: Create 100+ tables in hours, not weeks  
✅ **Maintainability**: Single template for all tables  
✅ **Quality**: Fewer manual errors  
✅ **Scalability**: Easily add new tables as sources grow  

**Next Steps**:
1. Create view metadata query stored procedure
2. Develop BimlScript template with C# code
3. Test with 2-3 pilot tables
4. Validate generated packages
5. Document and deploy to production

---

**Document Version**: 1.0  
**Last Updated**: May 21, 2026  
**Technology Stack**: SQL Server 2016+, BIML 5.0+, BimlStudio/BimlExpress  
**Audience**: Data Engineers, ETL Architects, BI Developers
