# BIML Script Implementation - Requirements and Design

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Naming Conventions](#naming-conventions)
- [BIML Script Structure](#biml-script-structure)
- [Metadata Discovery Process](#metadata-discovery-process)
- [Script Parameters](#script-parameters)
- [Execution Flow](#execution-flow)
- [Generated Artifacts](#generated-artifacts)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)

## Overview

This implementation provides a **metadata-driven BIML framework** that automatically generates:
- Landing table DDL
- SSIS synchronization packages
- All required indexes and constraints

The framework consists of two BIML scripts:
1. **GenericTableSync.biml** - Template that generates artifacts for a single view
2. **MainGenerator.biml** - Orchestrator that discovers views and calls the generic template

### Design Goals

✅ **Convention over Configuration**: Use naming conventions to minimize parameters  
✅ **Metadata-Driven**: Automatically discover structure from views  
✅ **Consistent Output**: All packages follow the same pattern  
✅ **Maintainable**: Single template for all tables  
✅ **Scalable**: Handle hundreds of tables efficiently  

## Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│  MainGenerator.biml                                         │
│  - Query for views ending in "View"                         │
│  - For each view in schema(s):                              │
│    └─> Call GenericTableSync.biml with view name           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ (for each view)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  GenericTableSync.biml                                      │
│  - Extract metadata from view                               │
│  - Generate table DDL                                       │
│  - Generate SSIS package                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                    ┌─────────┐
                    │  Output │
                    ├─────────┤
                    │ Tables  │
                    │ Packages│
                    └─────────┘
```

### Component Interaction

```
MainGenerator.biml
    ↓
    Query: SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS 
           WHERE TABLE_NAME LIKE '%View'
    ↓
    Loop: foreach (view in views)
    ↓
    Include: GenericTableSync.biml with parameters
        - ViewSchema (e.g., "ERP")
        - ViewName (e.g., "CustomerView")
    ↓
GenericTableSync.biml
    ↓
    Derive:
        - LandingSchema = ViewSchema
        - LandingTable = ViewName without "View" suffix
    ↓
    Query metadata from view
    ↓
    Generate:
        - <Table> element (DDL)
        - <Package> element (SSIS)
```

## Naming Conventions

### View Naming Convention

**Rule**: All views that represent Landing table sources MUST end with "View"

**Pattern**: `{Schema}.{TableName}View`

**Examples**:
```
✅ ERP.CustomerView          → Landing table: ERP.Customer
✅ SALESFORCE.AccountView    → Landing table: SALESFORCE.Account
✅ MES.ProductionOrderView   → Landing table: MES.ProductionOrder

❌ ERP.Customer              → Won't be processed (doesn't end in "View")
❌ ERP.CustomerVw            → Won't be processed (wrong suffix)
```

### Landing Table Naming Convention

**Rule**: Landing table name = View name WITHOUT the "View" suffix

**Pattern**: `{Schema}.{TableName}`

**Derivation Logic**:
```csharp
// C# code in BimlScript
string viewName = "CustomerView";
string tableName = viewName.Replace("View", "");  // "Customer"
```

### Package Naming Convention

**Pattern**: `Load_{Schema}_{Table}.dtsx`

**Examples**:
```
View: ERP.CustomerView          → Package: Load_ERP_Customer.dtsx
View: SALESFORCE.AccountView    → Package: Load_SALESFORCE_Account.dtsx
```

### Object Naming Convention

| Object Type | Pattern | Example |
|-------------|---------|---------|
| Primary Key | `PK_{Schema}_{Table}` | `PK_ERP_Customer` |
| Hash Index | `IX_{Schema}_{Table}_ChangeHashKey` | `IX_ERP_Customer_ChangeHashKey` |
| Temporal Index | `IX_{Schema}_{Table}_Temporal` | `IX_ERP_Customer_Temporal` |
| Staging Table | `#Staging_{Schema}_{Table}` | `#Staging_ERP_Customer` |

## BIML Script Structure

### File Organization

```
BimlScripts/
├── MainGenerator.biml              (Orchestrator - Entry point)
├── GenericTableSync.biml           (Template - Called per view)
├── Connections/
│   ├── Source_ERP.biml             (Connection definitions)
│   ├── Source_Salesforce.biml
│   └── Landing.biml
└── Helpers/
    └── DataTypeMapper.biml         (Helper functions)
```

### BIML Tier Architecture

BIML uses a **multi-tier compilation** approach:

```
Tier 1: MainGenerator.biml
    ↓ (Queries metadata, generates tier 2)
Tier 2: GenericTableSync.biml (repeated per view)
    ↓ (Generates tables and packages)
Tier 3: Compiled SSIS packages (.dtsx)
```

**Tier Attributes**:
- `<#@ template tier="1" #>` - Executes first, can query databases
- `<#@ template tier="2" #>` - Executes second, uses tier 1 results
- No tier attribute = Final output (tables, packages)

## Metadata Discovery Process

### Step 1: Discover Views

**MainGenerator.biml** queries for all views ending in "View":

```sql
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_NAME LIKE '%View'
    AND TABLE_SCHEMA IN ('ERP', 'SALESFORCE', 'MES')
ORDER BY TABLE_SCHEMA, TABLE_NAME
```

**Result**:
```
TABLE_SCHEMA  TABLE_NAME
ERP           CustomerView
ERP           OrderView
ERP           ProductView
SALESFORCE    AccountView
SALESFORCE    OpportunityView
```

### Step 2: Extract View Metadata

For each view, **GenericTableSync.biml** queries column metadata:

```sql
-- Get all columns with their properties
SELECT 
    c.COLUMN_NAME,
    c.ORDINAL_POSITION,
    c.DATA_TYPE,
    c.CHARACTER_MAXIMUM_LENGTH,
    c.NUMERIC_PRECISION,
    c.NUMERIC_SCALE,
    c.IS_NULLABLE,
    CASE 
        WHEN c.COLUMN_NAME IN ('ChangeHashKey', 'InsertDatetime', 'UpdateDatetime', 'IsDeleted')
        THEN 1 ELSE 0
    END AS IsTechnical
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = @ViewSchema
    AND c.TABLE_NAME = @ViewName
ORDER BY c.ORDINAL_POSITION
```

### Step 3: Classify Columns

Columns are classified into three categories:

**1. Primary Key Columns**:
- All columns BEFORE the first technical column (ChangeHashKey)
- Used to identify records uniquely

**2. Technical Columns** (fixed structure):
- `ChangeHashKey` (BINARY(32))
- `InsertDatetime` (DATETIME)
- `UpdateDatetime` (DATETIME)
- `IsDeleted` (BIT)

**3. Business Columns**:
- All columns AFTER the technical columns
- Actual data from source system

**Classification Logic**:
```csharp
// Find position of ChangeHashKey
int changeHashPosition = columns
    .First(c => c["COLUMN_NAME"].ToString() == "ChangeHashKey")
    .Field<int>("ORDINAL_POSITION");

// Classify
var pkColumns = columns.Where(c => 
    c.Field<int>("ORDINAL_POSITION") < changeHashPosition);

var technicalColumns = columns.Where(c => 
    new[] {"ChangeHashKey", "InsertDatetime", "UpdateDatetime", "IsDeleted"}
        .Contains(c["COLUMN_NAME"].ToString()));

var businessColumns = columns.Where(c => 
    c.Field<int>("ORDINAL_POSITION") > changeHashPosition + 3);
```

### Step 4: Build Hash Calculation

Generate CONCAT expression for hash:

```csharp
// Build hash calculation from business columns only
var hashParts = new List<string>();
foreach (var col in businessColumns)
{
    string colName = col["COLUMN_NAME"].ToString();
    string dataType = col["DATA_TYPE"].ToString().ToLower();
    
    if (col["IS_NULLABLE"].ToString() == "YES")
    {
        // Nullable columns need ISNULL
        hashParts.Add($"ISNULL({colName}, '')");
    }
    else if (new[] {"int", "bigint", "decimal", "numeric"}.Contains(dataType))
    {
        // Numeric types need casting
        hashParts.Add($"CAST({colName} AS NVARCHAR(50))");
    }
    else if (new[] {"datetime", "date", "datetime2"}.Contains(dataType))
    {
        // Date types need consistent format
        hashParts.Add($"CONVERT(NVARCHAR(23), {colName}, 121)");
    }
    else
    {
        // String types can be used directly
        hashParts.Add(colName);
    }
}

string hashExpression = "CONCAT(" + string.Join(", '|', ", hashParts) + ")";
```

## Script Parameters

### MainGenerator.biml Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `LandingConnectionString` | String | Yes | Connection to Landing DB | `Data Source=...;Initial Catalog=Landing;...` |
| `SchemasToProcess` | String[] | Yes | Array of schemas to scan | `{"ERP", "SALESFORCE", "MES"}` |
| `SourceConnections` | Dictionary | Yes | Map schema → connection string | `{"ERP": "...", "SALESFORCE": "..."}` |

### GenericTableSync.biml Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `ViewSchema` | String | Yes | Schema containing the view | `"ERP"` |
| `ViewName` | String | Yes | View name (must end in "View") | `"CustomerView"` |
| `SourceConnectionString` | String | Yes | Connection to source DB | `"Data Source=ERP_SERVER;..."` |
| `LandingConnectionString` | String | Yes | Connection to Landing DB | `"Data Source=LANDING_SERVER;..."` |

**Parameter Validation**:
```csharp
// Validate view name ends with "View"
if (!ViewName.EndsWith("View"))
{
    throw new Exception($"View name '{ViewName}' must end with 'View'");
}

// Derive table name
string tableName = ViewName.Substring(0, ViewName.Length - 4); // Remove "View"
```

## Execution Flow

### Phase 1: Initialization (MainGenerator.biml - Tier 1)

```
1. Load configuration (connection strings, schemas)
2. For each schema in SchemasToProcess:
   a. Query INFORMATION_SCHEMA.VIEWS
   b. Filter WHERE TABLE_NAME LIKE '%View'
   c. Add to viewsList
3. Generate tier 2 code for each view
```

### Phase 2: Code Generation (GenericTableSync.biml - Tier 2)

```
For each view:
1. Extract metadata
   a. Query INFORMATION_SCHEMA.COLUMNS
   b. Classify into PK, Technical, Business columns
   c. Build hash calculation expression

2. Generate Table DDL
   a. Create <Table> element
   b. Add columns in order (PK, Technical, Business)
   c. Define primary key constraint
   d. Define indexes

3. Generate Package
   a. Create variables
   b. Create data flow
      - OLE DB Source (with hash)
      - Lookup transformation
      - Conditional split
      - Destinations (INSERT/UPDATE)
   c. Create soft delete task
   d. Create logging tasks
```

### Phase 3: Compilation (BimlStudio)

```
1. BimlStudio reads MainGenerator.biml
2. Executes tier 1 code
3. Generates tier 2 code for each view
4. Executes tier 2 code
5. Compiles to SSIS packages (.dtsx)
6. Optionally deploys to SSISDB
```

## Generated Artifacts

### Per View Generated Items

For each view `{Schema}.{Table}View`, the following are generated:

#### 1. Table DDL

```sql
CREATE TABLE [Landing].[{Schema}].[{Table}]
(
    -- PK columns (from view)
    {PrimaryKey1}    {DataType}    NOT NULL,
    {PrimaryKey2}    {DataType}    NOT NULL,
    
    -- Technical columns (standard)
    ChangeHashKey    BINARY(32)    NOT NULL,
    InsertDatetime   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted        BIT           NOT NULL DEFAULT 0,
    
    -- Business columns (from view)
    {Column1}        {DataType}    {NULL/NOT NULL},
    {Column2}        {DataType}    {NULL/NOT NULL},
    ...
    
    CONSTRAINT [PK_{Schema}_{Table}] PRIMARY KEY CLUSTERED ({PrimaryKeys})
);

CREATE NONCLUSTERED INDEX [IX_{Schema}_{Table}_ChangeHashKey] 
    ON [Landing].[{Schema}].[{Table}] ([ChangeHashKey]);

CREATE NONCLUSTERED INDEX [IX_{Schema}_{Table}_Temporal] 
    ON [Landing].[{Schema}].[{Table}] ([UpdateDatetime], [IsDeleted]);
```

#### 2. SSIS Package

```
Load_{Schema}_{Table}.dtsx
├── Variables (SourceServer, PKColumns, etc.)
├── Control Flow
│   ├── Set Execution Start
│   ├── Create Staging Table
│   ├── Data Flow Task
│   │   ├── OLE DB Source (with hash)
│   │   └── OLE DB Destination (staging)
│   ├── MERGE to Landing
│   ├── Log Execution
│   └── Error Handler
└── Connections
    ├── Source
    └── Landing
```

### Aggregate Output

After processing all views:

```
Generated/
├── Tables/
│   ├── ERP.Customer.sql
│   ├── ERP.Order.sql
│   ├── ERP.Product.sql
│   ├── SALESFORCE.Account.sql
│   └── ...
└── Packages/
    ├── Load_ERP_Customer.dtsx
    ├── Load_ERP_Order.dtsx
    ├── Load_ERP_Product.dtsx
    ├── Load_SALESFORCE_Account.dtsx
    └── ...
```

## Usage Examples

### Example 1: Process Single Schema

**Configuration in MainGenerator.biml**:
```xml
<#
    // Define schemas to process
    string[] schemasToProcess = new[] { "ERP" };
    
    // Define connection strings
    var sourceConnections = new Dictionary<string, string>
    {
        { "ERP", "Data Source=ERP_SERVER;Initial Catalog=ERP_Production;..." }
    };
    
    string landingConnection = "Data Source=LANDING_SERVER;Initial Catalog=Landing;...";
#>
```

**Execution**:
1. Open BimlStudio
2. Load MainGenerator.biml
3. Right-click project → Build
4. Result: All ERP views processed

**Output**:
```
Processing ERP schema...
  Found 15 views ending in 'View'
  Generating ERP.CustomerView → Load_ERP_Customer.dtsx ✓
  Generating ERP.OrderView → Load_ERP_Order.dtsx ✓
  Generating ERP.ProductView → Load_ERP_Product.dtsx ✓
  ...
  
Total: 15 tables, 15 packages generated
```

### Example 2: Process Multiple Schemas

**Configuration**:
```xml
<#
    string[] schemasToProcess = new[] { "ERP", "SALESFORCE", "MES" };
    
    var sourceConnections = new Dictionary<string, string>
    {
        { "ERP", "Data Source=ERP_SERVER;..." },
        { "SALESFORCE", "Data Source=CRM_SERVER;..." },
        { "MES", "Data Source=MES_SERVER;..." }
    };
#>
```

**Output**:
```
Processing ERP schema...
  15 views processed
  
Processing SALESFORCE schema...
  8 views processed
  
Processing MES schema...
  22 views processed
  
Total: 45 tables, 45 packages generated
```

### Example 3: Add New View

**Steps**:
1. Create view in Landing database:
```sql
CREATE VIEW [ERP].[SupplierView]
AS
SELECT
    SupplierId,
    CompanyId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    SupplierName,
    ContactEmail
FROM [Landing].[ERP].[Supplier]
WHERE IsDeleted = 0;
```

2. Re-run MainGenerator.biml
3. New package automatically generated: `Load_ERP_Supplier.dtsx`

**No code changes needed!** The framework discovers the new view automatically.

## Troubleshooting

### Issue 1: View Not Discovered

**Symptom**: View exists but package not generated

**Possible Causes**:
1. View name doesn't end with "View"
   - ✅ Fix: Rename view to include "View" suffix
   
2. View schema not in `schemasToProcess` array
   - ✅ Fix: Add schema to configuration
   
3. View in different database than Landing
   - ✅ Fix: Ensure view is in Landing database

**Verification Query**:
```sql
-- Check if view would be discovered
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_NAME LIKE '%View'
    AND TABLE_SCHEMA = 'ERP'  -- Your schema
```

### Issue 2: Missing Technical Columns

**Symptom**: Error during metadata extraction

**Error Message**: `"View is missing required technical columns"`

**Cause**: View doesn't contain all required technical columns

**Required Columns**:
- ChangeHashKey (BINARY(32))
- InsertDatetime (DATETIME)
- UpdateDatetime (DATETIME)
- IsDeleted (BIT)

**Fix**:
```sql
-- Ensure view includes all technical columns
CREATE OR ALTER VIEW [ERP].[CustomerView]
AS
SELECT
    -- PK
    CompanyId,
    CustomerId,
    -- Technical (REQUIRED)
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    -- Business
    CustomerName,
    VAT
FROM [Landing].[ERP].[Customer];
```

### Issue 3: Hash Calculation Error

**Symptom**: Package builds but fails at runtime

**Error**: `"Error calculating hash in source query"`

**Possible Causes**:
1. Column data type not handled
   - ✅ Fix: Add type mapping in GenericTableSync.biml
   
2. NULL handling issue
   - ✅ Fix: Ensure ISNULL() used for nullable columns

**Debug Steps**:
1. Check generated source query in package
2. Execute query manually in SSMS
3. Verify hash calculation syntax

### Issue 4: Package Compilation Fails

**Symptom**: BimlStudio shows compilation errors

**Common Errors**:

1. **"Connection not found"**
   - Fix: Ensure connection names match in configuration
   
2. **"Invalid data type mapping"**
   - Fix: Check DataTypeMapper helper function
   
3. **"Duplicate table name"**
   - Fix: Ensure unique table names across schemas

**Debug Mode**:
```xml
<!-- Add to MainGenerator.biml for debugging -->
<#
    // Enable verbose logging
    this.LogDebug = true;
    
    // Log each view processed
    foreach (var view in viewsList)
    {
        Console.WriteLine($"Processing {view.Schema}.{view.Name}");
    }
#>
```

### Issue 5: Performance - Too Many Views

**Symptom**: BimlStudio takes long time to compile

**Solution 1: Batch Processing**
```xml
<!-- Process schemas one at a time -->
<# string[] schemasToProcess = new[] { "ERP" }; // Just one schema #>
```

**Solution 2: Filter Views**
```sql
-- Only process specific views
WHERE TABLE_NAME LIKE '%View'
    AND TABLE_NAME IN ('CustomerView', 'OrderView')  -- Filter
```

**Solution 3: Parallel Execution**
```xml
<!-- Use BimlStudio's parallel compilation -->
<# this.CompilationOptions.Parallel = true; #>
```

## Best Practices

### 1. View Design

**DO**:
- ✅ Always end view names with "View"
- ✅ Include all required technical columns
- ✅ Order columns correctly (PK, Technical, Business)
- ✅ Document view purpose in comments

**DON'T**:
- ❌ Include calculated columns in hash
- ❌ Use SELECT * (be explicit)
- ❌ Include volatile columns (timestamps from source)

### 2. Metadata Management

**Create Metadata Tables**:
```sql
CREATE TABLE [dbo].[ViewRegistry]
(
    ViewSchema      NVARCHAR(50),
    ViewName        NVARCHAR(100),
    SourceServer    NVARCHAR(128),
    SourceDatabase  NVARCHAR(128),
    IsActive        BIT,
    LastGenerated   DATETIME
);
```

**Track Generation**:
```sql
INSERT INTO [dbo].[ViewRegistry]
VALUES ('ERP', 'CustomerView', 'ERP_SERVER', 'ERP_Production', 1, GETDATE());
```

### 3. Version Control

**Folder Structure**:
```
repo/
├── BimlScripts/
│   ├── MainGenerator.biml
│   ├── GenericTableSync.biml
│   └── Config/
│       └── connections.json
├── Generated/
│   └── .gitignore  (don't commit generated files)
└── Views/
    ├── ERP/
    │   ├── CustomerView.sql
    │   └── OrderView.sql
    └── SALESFORCE/
        └── AccountView.sql
```

**Commit Strategy**:
- ✅ Commit: BIML templates, view definitions
- ❌ Don't commit: Generated packages (regenerate on demand)

### 4. Testing

**Unit Test Each Generated Package**:
```sql
-- Test script template
-- 1. Create test view
CREATE VIEW [TEST].[MockView] AS SELECT ...;

-- 2. Generate package
-- (run MainGenerator.biml)

-- 3. Execute package
EXEC [SSISDB].[catalog].[create_execution] ...;

-- 4. Verify results
SELECT COUNT(*) FROM [Landing].[TEST].[Mock];

-- 5. Cleanup
DROP VIEW [TEST].[MockView];
DELETE FROM [Landing].[TEST].[Mock];
```

### 5. Documentation

**Auto-Generate Documentation**:
```xml
<!-- In GenericTableSync.biml -->
<#
    // Generate markdown documentation
    string doc = $@"
# Package: Load_{viewSchema}_{tableName}

## View
- Schema: {viewSchema}
- Name: {viewName}

## Landing Table
- Schema: {viewSchema}
- Name: {tableName}

## Columns
- Primary Keys: {string.Join(", ", pkColumns)}
- Business Columns: {businessColumns.Count}

## Generated
- Date: {DateTime.Now}
- Generator: GenericTableSync.biml v1.0
";

    File.WriteAllText($"Docs/Load_{viewSchema}_{tableName}.md", doc);
#>
```

---

## Summary

This BIML framework provides:

✅ **Automated Generation**: Discover views and generate packages automatically  
✅ **Convention-Based**: Minimal configuration through naming conventions  
✅ **Consistent Output**: All packages follow the same proven pattern  
✅ **Maintainable**: Single template for unlimited tables  
✅ **Scalable**: Process hundreds of views in minutes  
✅ **Reliable**: Metadata-driven ensures correctness  

**Next Steps**:
1. Review and customize connection strings in MainGenerator.biml
2. Create views following the naming convention
3. Run MainGenerator.biml to generate packages
4. Test a few packages manually
5. Deploy to SSISDB and schedule execution

---

**Document Version**: 1.0  
**Last Updated**: May 21, 2026  
**Technology Stack**: BIML 5.0+, BimlStudio, SQL Server 2016+  
**Audience**: Data Engineers, BI Developers, ETL Architects
