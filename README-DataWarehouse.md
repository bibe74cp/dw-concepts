# Data Warehouse - Design Pattern

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Schema Design](#schema-design)
- [Dimension Tables](#dimension-tables)
- [Fact Tables](#fact-tables)
- [Bridge Tables](#bridge-tables)
- [Application Views](#application-views)
- [Synchronization Pattern](#synchronization-pattern)
- [Benefits and Rationale](#benefits-and-rationale)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Overview

The **Data Warehouse** layer is the analytical core of the data platform where raw data from the Landing zone is transformed into a dimensional model optimized for business intelligence and reporting. This document describes a proven pattern for designing and managing a data warehouse using Microsoft SQL Server and Kimball-style dimensional modeling.

### Purpose of the Data Warehouse

The Data Warehouse layer serves several critical functions:
- **Dimensional Modeling**: Organizes data into facts and dimensions for intuitive querying
- **Data Integration**: Combines data from multiple source systems into unified business entities
- **Normalization**: Standardizes column names, data types, and business rules across sources
- **Performance**: Optimizes data structures for analytical queries and reporting
- **Business Logic**: Implements calculated measures, hierarchies, and business rules
- **Access Control**: Provides secure, application-specific views of analytical data

## Architecture

### Database Structure

```
DataWarehouse Database
├── Staging (schema)
│   ├── CustomerStaging (intermediate calculations)
│   ├── OrderEnrichment (partial transformations)
│   └── ... (other staging tables)
├── Dim (schema)
│   ├── Customer (dimension table)
│   ├── CustomerView (source view for synchronization)
│   ├── Product (dimension table)
│   ├── ProductView (source view for synchronization)
│   └── ... (other dimensions)
├── Fact (schema)
│   ├── Sales (fact table)
│   ├── SalesView (source view for synchronization)
│   ├── Production (fact table)
│   ├── ProductionView (source view for synchronization)
│   └── ... (other facts)
├── Bridge (schema)
│   ├── ProductCategory (many-to-many bridge)
│   ├── CustomerGroup (many-to-many bridge)
│   └── ... (other bridges)
├── vERP (schema - application views)
│   ├── ProductionOrders (view for ERP consumption)
│   ├── Customers (view for ERP consumption)
│   └── ... (other ERP views)
├── vPowerBI (schema - application views)
│   ├── SalesAnalysis (view for Power BI)
│   └── ... (other BI views)
└── ... (additional application schemas)
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Landing Database                         │
│         (ERP, SALESFORCE, MES schemas)                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   Staging Schema                            │
│        (Intermediate calculations & transformations)        │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌──────────────────┐           ┌──────────────────┐
│  Dim Schema      │           │  Fact Schema     │
│  (Dimensions)    │◄──────────┤  (Facts)         │
└────────┬─────────┘           └────────┬─────────┘
         │                              │
         └───────────┬──────────────────┘
                     │
                     ▼
         ┌────────────────────────┐
         │   Bridge Schema        │
         │  (Many-to-Many)        │
         └────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│              Application Views (vERP, vPowerBI)             │
│        (Secure, curated views for specific consumers)       │
└─────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Kimball Dimensional Modeling**: Star schema with facts and dimensions
2. **Separation of Concerns**: Staging, dimensions, facts, bridges, and application views in separate schemas
3. **View-Based Synchronization**: Source views define transformation logic; tables store materialized results
4. **Surrogate Keys**: Integer keys generated from sequences for all dimensions
5. **Special Members**: Standard handling of NULL and unknown foreign keys
6. **Referential Integrity**: Strict enforcement through special members and synchronization logic

## Key Concepts

### Kimball Dimensional Modeling

The **Kimball methodology** is a bottom-up approach to data warehouse design that focuses on:
- **Star Schema**: Fact tables at the center surrounded by dimension tables
- **Business Process Focus**: Model business processes (e.g., Sales, Production) as facts
- **Conformed Dimensions**: Shared dimensions across multiple fact tables
- **Grain Declaration**: Explicit definition of fact table granularity

**Benefits**:
- Intuitive for business users
- Optimized for query performance
- Flexible for ad-hoc analysis
- Incremental development approach

### Fact vs Dimension Tables

**Dimension Tables** (WHO, WHAT, WHERE, WHEN, WHY):
- Descriptive attributes about business entities
- Examples: Customer, Product, Date, Location
- Relatively small (thousands to millions of rows)
- Wide tables (many columns)
- Slowly changing over time

**Fact Tables** (METRICS, MEASUREMENTS):
- Numeric measurements of business events
- Examples: Sales transactions, Production orders, Web clicks
- Very large (millions to billions of rows)
- Narrow tables (foreign keys + measures)
- Append-only or periodic snapshots

### Surrogate Keys

A **surrogate key** is an artificial identifier that has no business meaning:
```sql
CustomerKey INT  -- Surrogate key (generated sequence)
vs
CustomerId INT   -- Natural/business key (from source system)
```

**Why Use Surrogate Keys?**
- **Independence**: Decouples warehouse from source system changes
- **Integration**: Combines data from multiple sources with different keys
- **Performance**: Integer keys are faster than composite or string keys
- **History**: Enables tracking dimension changes (SCD Type 2)
- **Simplicity**: Single-column foreign keys in fact tables

**Generation**: 
```sql
-- Using SQL Server SEQUENCE
CREATE SEQUENCE Dim.CustomerSequence START WITH 1 INCREMENT BY 1;
CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
```

### Special Members (Empty and Unknown)

Every dimension contains **two special records**:

**Empty Member (Key = -1)**:
- Represents NULL foreign keys in fact tables
- Used when the dimension is not applicable
- Example: OrderKey = -1 when Customer has no orders

**Unknown Member (Key = -101)**:
- Represents unmatched foreign keys in fact tables
- Used when business key exists but dimension record is missing or deleted
- Example: CustomerKey = -101 when OrderCustomerId = 999 but Customer 999 doesn't exist or IsDeleted = 1

**Benefits**:
- **Preserves Data**: Fact records load even with missing dimension references
- **Referential Integrity**: No NULL foreign keys; all facts reference valid dimensions
- **Auditing**: Can identify data quality issues (count of Unknown members)
- **Query Simplicity**: No need for outer joins or NULL handling in reports

### Slowly Changing Dimensions (SCD)

This pattern implements **SCD Type 1** (overwrite):
- Current value only (no history tracking)
- Dimension updates overwrite existing values
- Simple and efficient
- Suitable when historical dimension values aren't needed

**Alternative approaches** (not implemented in this pattern):
- **SCD Type 2**: Track full history with effective dates and current flags
- **SCD Type 3**: Track limited history (e.g., current and previous value)

### View-Based Synchronization

The synchronization pattern uses **views as sources** and **tables as targets**:

```
Landing Tables → Dimension View → Dimension Table
```

**Dimension View**: 
- Defines transformation logic (joins, calculations, normalization)
- Acts as "desired state" of the dimension

**Dimension Table**: 
- Materialized snapshot of the view
- Optimized with indexes for query performance
- Updated through same MERGE pattern as Landing

**Benefits**:
- Clear separation between logic (view) and storage (table)
- Views can be tested independently
- Tables provide consistent performance
- Same synchronization pattern throughout the warehouse

### LEFT JOIN Pattern for Facts

Fact views use **LEFT JOIN** to dimensions to ensure all facts load:

```sql
SELECT
    f.*,
    COALESCE(d.CustomerKey, -101) AS CustomerKey  -- Unknown if no match
FROM Landing.ERP.Order f
LEFT JOIN Dim.Customer d 
    ON f.CustomerId = d.CustomerId
    AND d.IsDeleted = 0
```

**Logic**:
- **Inner join match**: Use dimension's surrogate key
- **NULL foreign key**: Use -1 (empty member)
- **No match or deleted**: Use -101 (unknown member)

## Schema Design

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Database | PascalCase | `DataWarehouse` |
| Schema | PascalCase | `Dim`, `Fact`, `Bridge`, `Staging` |
| Application Schema | Lowercase prefix + PascalCase | `vERP`, `vPowerBI` |
| Dimension Table | Singular noun | `Customer`, `Product` |
| Dimension View | Table name + "View" | `CustomerView`, `ProductView` |
| Fact Table | Plural or process name | `Sales`, `ProductionOrders` |
| Fact View | Table name + "View" | `SalesView`, `ProductionOrdersView` |
| Surrogate Key | Dimension name + "Key" | `CustomerKey`, `ProductKey` |
| Natural Key | Match source | `CustomerId`, `ProductId` |
| Sequence | Schema + Table + "Sequence" | `DimCustomerSequence` |

### Schema Organization

**Staging Schema**:
- Purpose: Intermediate transformations, complex calculations
- Visibility: Internal to ETL processes only
- Lifecycle: Tables can be truncated/recreated frequently
- Examples: Complex joins, aggregations, business rule applications

**Dim Schema**:
- Purpose: Dimension tables and their source views
- Visibility: Consumed by fact views and application views
- Lifecycle: Persistent, synchronized with Landing changes

**Fact Schema**:
- Purpose: Fact tables and their source views
- Visibility: Consumed by application views
- Lifecycle: Append-only or periodic snapshots

**Bridge Schema**:
- Purpose: Many-to-many relationships between facts and dimensions
- Visibility: Consumed by application views
- Lifecycle: Synchronized with dimension changes

**Application Schemas (vERP, vPowerBI, etc.)**:
- Purpose: Curated views for specific applications or user groups
- Visibility: External to data warehouse (consumed by applications)
- Lifecycle: Stable interfaces (versioned if breaking changes)

## Dimension Tables

### Structure

Every dimension follows this pattern:

**Dimension View** (defines transformation):
```sql
CREATE VIEW Dim.CustomerView
AS
SELECT
    -- Surrogate Key (will be generated during synchronization)
    -- NEXT VALUE FOR Dim.CustomerSequence AS CustomerKey
    
    -- Natural Keys (from source)
    c.CompanyId,
    c.CustomerId,
    
    -- Technical Columns (from Landing)
    c.ChangeHashKey,
    c.InsertDatetime,
    c.UpdateDatetime,
    c.IsDeleted,
    
    -- Business Attributes (normalized)
    c.CustomerName AS Name,
    c.VAT AS TaxIdentifier,
    ct.CategoryName AS Category,
    cr.RegionName AS Region,
    
    -- Calculated Attributes
    CASE 
        WHEN c.CreditLimit > 100000 THEN 'High Value'
        WHEN c.CreditLimit > 10000 THEN 'Medium Value'
        ELSE 'Standard'
    END AS CustomerSegment
    
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
LEFT JOIN [Staging].[CustomerRegion] cr 
    ON c.RegionId = cr.RegionId
WHERE c.IsDeleted = 0  -- Only active records
```

**Dimension Table** (materialized storage):
```sql
CREATE TABLE Dim.Customer
(
    -- Surrogate Key
    CustomerKey         INT             NOT NULL,
    
    -- Natural Keys
    CompanyId           INT             NOT NULL,
    CustomerId          INT             NOT NULL,
    
    -- Technical Columns
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Business Attributes
    Name                NVARCHAR(100)   NOT NULL,
    TaxIdentifier       NVARCHAR(20)    NULL,
    Category            NVARCHAR(50)    NULL,
    Region              NVARCHAR(50)    NULL,
    CustomerSegment     NVARCHAR(20)    NULL,
    
    -- Primary Key on Surrogate
    CONSTRAINT PK_Dim_Customer PRIMARY KEY CLUSTERED (CustomerKey),
    
    -- Unique constraint on Natural Key
    CONSTRAINT UQ_Dim_Customer_NaturalKey UNIQUE (CompanyId, CustomerId)
);

-- Index for synchronization (natural key lookup)
CREATE NONCLUSTERED INDEX IX_Dim_Customer_NaturalKey 
    ON Dim.Customer (CompanyId, CustomerId);

-- Index for change detection
CREATE NONCLUSTERED INDEX IX_Dim_Customer_ChangeHash 
    ON Dim.Customer (ChangeHashKey);
```

**Sequence** (surrogate key generation):
```sql
CREATE SEQUENCE Dim.CustomerSequence 
    START WITH 1 
    INCREMENT BY 1;
```

### Special Members Initialization

Every dimension must be initialized with special members:

```sql
-- Initialize sequence past special member keys
ALTER SEQUENCE Dim.CustomerSequence RESTART WITH 1;

-- Insert Empty Member (Key = -1)
INSERT INTO Dim.Customer
(
    CustomerKey,
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    Name,
    TaxIdentifier,
    Category,
    Region,
    CustomerSegment
)
VALUES
(
    -1,                                  -- Empty member key
    -1,
    -1,
    0x00,                                -- Empty hash
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Never deleted
    '(Empty)',
    NULL,
    '(Empty)',
    '(Empty)',
    '(Empty)'
);

-- Insert Unknown Member (Key = -101)
INSERT INTO Dim.Customer
(
    CustomerKey,
    CompanyId,
    CustomerId,
    ChangeHashKey,
    InsertDatetime,
    UpdateDatetime,
    IsDeleted,
    Name,
    TaxIdentifier,
    Category,
    Region,
    CustomerSegment
)
VALUES
(
    -101,                                -- Unknown member key
    -101,
    -101,
    0x00,                                -- Empty hash
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,                                   -- Never deleted
    '(Unknown)',
    NULL,
    '(Unknown)',
    '(Unknown)',
    '(Unknown)'
);
```

### Dimension Column Types

**Surrogate Key (CustomerKey)**:
- Generated from sequence
- Never changes
- Primary key of dimension table
- Foreign key in fact tables

**Natural Keys (CompanyId, CustomerId)**:
- Business identifiers from source system
- Used for lookups during synchronization
- Unique constraint enforced

**Technical Columns (ChangeHashKey, InsertDatetime, UpdateDatetime, IsDeleted)**:
- Inherited from Landing layer
- Same purpose and usage
- Enable change detection and audit

**Business Attributes (Name, Category, Region, etc.)**:
- Descriptive columns for analysis
- Normalized names (e.g., CustomerName → Name)
- May combine data from multiple sources
- May include calculated/derived values

## Fact Tables

### Structure

Every fact table follows this pattern:

**Fact View** (defines transformation):
```sql
CREATE VIEW Fact.SalesView
AS
SELECT
    -- Natural Keys (from source)
    o.CompanyId,
    o.OrderId,
    o.LineNumber,
    
    -- Technical Columns (from Landing)
    o.ChangeHashKey,
    o.InsertDatetime,
    o.UpdateDatetime,
    o.IsDeleted,
    
    -- Dimension Foreign Keys (surrogate keys via LEFT JOIN)
    COALESCE(dc.CustomerKey, 
        CASE WHEN o.CustomerId IS NULL THEN -1 ELSE -101 END) AS CustomerKey,
    COALESCE(dp.ProductKey, 
        CASE WHEN o.ProductId IS NULL THEN -1 ELSE -101 END) AS ProductKey,
    COALESCE(dd.DateKey, -101) AS OrderDateKey,
    COALESCE(de.EmployeeKey, 
        CASE WHEN o.SalesPersonId IS NULL THEN -1 ELSE -101 END) AS SalesPersonKey,
    
    -- Degenerate Dimensions (high-cardinality attributes stored in fact)
    o.OrderNumber,
    o.InvoiceNumber,
    
    -- Measures (numeric facts)
    o.Quantity,
    o.UnitPrice,
    o.DiscountPercent,
    o.LineTotal,
    o.TaxAmount,
    
    -- Calculated Measures
    o.LineTotal - o.TaxAmount AS NetAmount,
    o.Quantity * o.UnitPrice - o.LineTotal AS DiscountAmount
    
FROM [Landing].[ERP].[OrderDetail] o
INNER JOIN [Landing].[ERP].[Order] oh 
    ON o.CompanyId = oh.CompanyId 
    AND o.OrderId = oh.OrderId
LEFT JOIN Dim.Customer dc 
    ON o.CompanyId = dc.CompanyId 
    AND o.CustomerId = dc.CustomerId
    AND dc.IsDeleted = 0
LEFT JOIN Dim.Product dp 
    ON o.ProductId = dp.ProductId
    AND dp.IsDeleted = 0
LEFT JOIN Dim.Date dd 
    ON CAST(oh.OrderDate AS DATE) = dd.DateValue
LEFT JOIN Dim.Employee de 
    ON o.SalesPersonId = de.EmployeeId
    AND de.IsDeleted = 0
WHERE o.IsDeleted = 0;
```

**Fact Table** (materialized storage):
```sql
CREATE TABLE Fact.Sales
(
    -- Natural Keys (grain definition)
    CompanyId           INT             NOT NULL,
    OrderId             INT             NOT NULL,
    LineNumber          INT             NOT NULL,
    
    -- Technical Columns
    ChangeHashKey       BINARY(32)      NOT NULL,
    InsertDatetime      DATETIME        NOT NULL,
    UpdateDatetime      DATETIME        NOT NULL,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Dimension Foreign Keys (surrogate keys)
    CustomerKey         INT             NOT NULL,
    ProductKey          INT             NOT NULL,
    OrderDateKey        INT             NOT NULL,
    SalesPersonKey      INT             NOT NULL,
    
    -- Degenerate Dimensions
    OrderNumber         NVARCHAR(50)    NOT NULL,
    InvoiceNumber       NVARCHAR(50)    NULL,
    
    -- Measures
    Quantity            DECIMAL(18,2)   NOT NULL,
    UnitPrice           DECIMAL(18,2)   NOT NULL,
    DiscountPercent     DECIMAL(5,2)    NOT NULL,
    LineTotal           DECIMAL(18,2)   NOT NULL,
    TaxAmount           DECIMAL(18,2)   NOT NULL,
    NetAmount           DECIMAL(18,2)   NOT NULL,
    DiscountAmount      DECIMAL(18,2)   NOT NULL,
    
    -- Primary Key (natural grain)
    CONSTRAINT PK_Fact_Sales PRIMARY KEY CLUSTERED 
        (CompanyId, OrderId, LineNumber),
    
    -- Foreign Keys to Dimensions
    CONSTRAINT FK_Fact_Sales_Customer 
        FOREIGN KEY (CustomerKey) REFERENCES Dim.Customer (CustomerKey),
    CONSTRAINT FK_Fact_Sales_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Fact_Sales_Date 
        FOREIGN KEY (OrderDateKey) REFERENCES Dim.Date (DateKey),
    CONSTRAINT FK_Fact_Sales_Employee 
        FOREIGN KEY (SalesPersonKey) REFERENCES Dim.Employee (EmployeeKey)
);

-- Indexes for common query patterns
CREATE NONCLUSTERED INDEX IX_Fact_Sales_Customer 
    ON Fact.Sales (CustomerKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Product 
    ON Fact.Sales (ProductKey) INCLUDE (LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Fact_Sales_Date 
    ON Fact.Sales (OrderDateKey) INCLUDE (LineTotal, Quantity);
```

### Fact Column Types

**Natural Keys (CompanyId, OrderId, LineNumber)**:
- Define the grain (level of detail) of the fact
- Primary key of fact table
- Used for synchronization and deduplication

**Dimension Foreign Keys (CustomerKey, ProductKey, etc.)**:
- Surrogate keys from dimension tables
- Always populated (never NULL) using special members
- Enable star schema joins

**Degenerate Dimensions (OrderNumber, InvoiceNumber)**:
- High-cardinality transaction identifiers
- Don't warrant separate dimension table
- Stored directly in fact table

**Measures (Quantity, UnitPrice, LineTotal, etc.)**:
- Numeric values to be aggregated
- Support SUM, AVG, MIN, MAX, COUNT operations
- Can be stored (from source) or calculated (derived)

**Additive vs Non-Additive Measures**:
- **Additive**: Can be summed across all dimensions (e.g., Quantity, LineTotal)
- **Semi-Additive**: Can be summed across some dimensions (e.g., Account Balance - not across time)
- **Non-Additive**: Cannot be summed (e.g., Unit Price, Ratios) - use AVG or calculated measures

## Bridge Tables

### Purpose

Bridge tables resolve **many-to-many relationships** between facts and dimensions:

**Scenarios**:
- Product belongs to multiple Categories
- Customer belongs to multiple Groups
- Employee reports to multiple Managers (matrix organization)
- Transaction tagged with multiple Hashtags

### Structure

```sql
-- Bridge Table
CREATE TABLE Bridge.ProductCategory
(
    ProductKey          INT             NOT NULL,
    CategoryKey         INT             NOT NULL,
    
    -- Optional weighting for allocation
    AllocationPercent   DECIMAL(5,2)    NULL,
    
    -- Technical Columns
    InsertDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdateDatetime      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsDeleted           BIT             NOT NULL DEFAULT 0,
    
    -- Primary Key
    CONSTRAINT PK_Bridge_ProductCategory 
        PRIMARY KEY CLUSTERED (ProductKey, CategoryKey),
    
    -- Foreign Keys
    CONSTRAINT FK_Bridge_ProductCategory_Product 
        FOREIGN KEY (ProductKey) REFERENCES Dim.Product (ProductKey),
    CONSTRAINT FK_Bridge_ProductCategory_Category 
        FOREIGN KEY (CategoryKey) REFERENCES Dim.Category (CategoryKey)
);

-- Indexes for both direction queries
CREATE NONCLUSTERED INDEX IX_Bridge_ProductCategory_Category 
    ON Bridge.ProductCategory (CategoryKey, ProductKey);
```

### Usage in Queries

```sql
-- Find all products in a category (one-to-many direction)
SELECT 
    c.CategoryName,
    p.ProductName,
    f.LineTotal
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
INNER JOIN Dim.Product p ON f.ProductKey = p.ProductKey
WHERE c.CategoryName = 'Electronics';

-- Allocate sales across multiple categories (many-to-many with weighting)
SELECT 
    c.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category c ON b.CategoryKey = c.CategoryKey
GROUP BY c.CategoryName;
```

## Application Views

### Purpose

Application-specific schemas provide **curated, secure views** for external consumption:

**Benefits**:
- **Security**: Each application has its own user with restricted permissions
- **Simplification**: Complex joins and logic hidden from consumers
- **Abstraction**: Schema changes don't break external dependencies
- **Versioning**: Can maintain multiple view versions during migrations
- **Performance**: Can include indexed views or materialized results

### Structure

**Application Schema** (e.g., vERP):
```sql
-- Create schema for ERP application
CREATE SCHEMA vERP;

-- Create dedicated user
CREATE USER dw_erp WITH PASSWORD = 'SecurePassword123!';

-- Grant read-only access to vERP schema only
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
DENY SELECT ON SCHEMA::Dim TO dw_erp;
DENY SELECT ON SCHEMA::Fact TO dw_erp;
DENY SELECT ON SCHEMA::Staging TO dw_erp;
```

**Application View**:
```sql
CREATE VIEW vERP.ProductionOrders
AS
SELECT
    -- Business Keys
    po.CompanyId,
    po.ProductionOrderId,
    
    -- Dimensions (business-friendly names)
    p.ProductCode,
    p.ProductName,
    w.WorkCenterCode,
    w.WorkCenterName,
    e.EmployeeName AS Operator,
    d.DateValue AS ProductionDate,
    
    -- Measures
    po.PlannedQuantity,
    po.ActualQuantity,
    po.ScrapQuantity,
    po.ActualQuantity - po.ScrapQuantity AS GoodQuantity,
    
    -- Calculated Metrics
    CASE 
        WHEN po.PlannedQuantity > 0 
        THEN (po.ActualQuantity * 100.0 / po.PlannedQuantity)
        ELSE 0 
    END AS EfficiencyPercent,
    
    -- Status
    CASE 
        WHEN po.ActualQuantity >= po.PlannedQuantity THEN 'Complete'
        WHEN po.ActualQuantity > 0 THEN 'In Progress'
        ELSE 'Planned'
    END AS Status
    
FROM Fact.ProductionOrders po
INNER JOIN Dim.Product p ON po.ProductKey = p.ProductKey
INNER JOIN Dim.WorkCenter w ON po.WorkCenterKey = w.WorkCenterKey
INNER JOIN Dim.Employee e ON po.OperatorKey = e.EmployeeKey
INNER JOIN Dim.Date d ON po.ProductionDateKey = d.DateKey
WHERE po.IsDeleted = 0
    AND p.IsDeleted = 0
    AND w.IsDeleted = 0;
```

**Usage by Application**:
```sql
-- ERP application connects as dw_erp user
-- Can only access vERP schema

SELECT 
    ProductionDate,
    ProductCode,
    SUM(ActualQuantity) AS TotalProduced
FROM vERP.ProductionOrders
WHERE ProductionDate >= '2026-05-01'
GROUP BY ProductionDate, ProductCode
ORDER BY ProductionDate, ProductCode;
```

## Synchronization Pattern

### Dimension Synchronization

The synchronization pattern for dimensions mirrors the Landing pattern:

```sql
-- Step 1: Create temporary staging from view
SELECT * 
INTO #DimCustomerStaging
FROM Dim.CustomerView;

-- Step 2: Generate surrogate keys for new records
UPDATE s
SET CustomerKey = NEXT VALUE FOR Dim.CustomerSequence
FROM #DimCustomerStaging s
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer t
    WHERE t.CompanyId = s.CompanyId 
    AND t.CustomerId = s.CustomerId
);

-- Step 3: MERGE into dimension table
MERGE Dim.Customer AS target
USING #DimCustomerStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.CustomerId = source.CustomerId

-- Scenario C: Update changed records (exclude special members)
WHEN MATCHED 
    AND target.ChangeHashKey <> source.ChangeHashKey 
    AND target.CustomerKey NOT IN (-1, -101) THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        Name = source.Name,
        TaxIdentifier = source.TaxIdentifier,
        Category = source.Category,
        Region = source.Region,
        CustomerSegment = source.CustomerSegment

-- Scenario A: Insert new records
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CustomerKey, CompanyId, CustomerId, ChangeHashKey, 
        InsertDatetime, UpdateDatetime, IsDeleted,
        Name, TaxIdentifier, Category, Region, CustomerSegment
    )
    VALUES (
        source.CustomerKey, source.CompanyId, source.CustomerId, 
        source.ChangeHashKey, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.Name, source.TaxIdentifier, source.Category, 
        source.Region, source.CustomerSegment
    )

-- Scenario D: Soft delete missing records (exclude special members)
WHEN NOT MATCHED BY SOURCE 
    AND target.IsDeleted = 0 
    AND target.CustomerKey NOT IN (-1, -101) THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

**Key Differences from Landing**:
1. **Surrogate Key Generation**: New records get keys from sequence before MERGE
2. **Special Members Protection**: MERGE excludes CustomerKey IN (-1, -101) to prevent modification
3. **View as Source**: #DimCustomerStaging populated from Dim.CustomerView

### Fact Synchronization

Fact table synchronization follows the same pattern:

```sql
-- Step 1: Create temporary staging from view
SELECT * 
INTO #FactSalesStaging
FROM Fact.SalesView;

-- Step 2: MERGE into fact table
MERGE Fact.Sales AS target
USING #FactSalesStaging AS source
    ON target.CompanyId = source.CompanyId 
    AND target.OrderId = source.OrderId 
    AND target.LineNumber = source.LineNumber

-- Scenario C: Update changed records
WHEN MATCHED AND target.ChangeHashKey <> source.ChangeHashKey THEN
    UPDATE SET
        ChangeHashKey = source.ChangeHashKey,
        UpdateDatetime = CURRENT_TIMESTAMP,
        CustomerKey = source.CustomerKey,
        ProductKey = source.ProductKey,
        OrderDateKey = source.OrderDateKey,
        SalesPersonKey = source.SalesPersonKey,
        OrderNumber = source.OrderNumber,
        InvoiceNumber = source.InvoiceNumber,
        Quantity = source.Quantity,
        UnitPrice = source.UnitPrice,
        DiscountPercent = source.DiscountPercent,
        LineTotal = source.LineTotal,
        TaxAmount = source.TaxAmount,
        NetAmount = source.NetAmount,
        DiscountAmount = source.DiscountAmount

-- Scenario A: Insert new records
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        CompanyId, OrderId, LineNumber, ChangeHashKey,
        InsertDatetime, UpdateDatetime, IsDeleted,
        CustomerKey, ProductKey, OrderDateKey, SalesPersonKey,
        OrderNumber, InvoiceNumber,
        Quantity, UnitPrice, DiscountPercent, 
        LineTotal, TaxAmount, NetAmount, DiscountAmount
    )
    VALUES (
        source.CompanyId, source.OrderId, source.LineNumber, 
        source.ChangeHashKey,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0,
        source.CustomerKey, source.ProductKey, source.OrderDateKey, 
        source.SalesPersonKey,
        source.OrderNumber, source.InvoiceNumber,
        source.Quantity, source.UnitPrice, source.DiscountPercent,
        source.LineTotal, source.TaxAmount, source.NetAmount, 
        source.DiscountAmount
    )

-- Scenario D: Soft delete missing records
WHEN NOT MATCHED BY SOURCE AND target.IsDeleted = 0 THEN
    UPDATE SET
        UpdateDatetime = CURRENT_TIMESTAMP,
        IsDeleted = 1;
```

### Synchronization Order

Execute synchronizations in **dependency order**:

```
1. Staging Tables (if needed)
   ↓
2. Dimensions (in dependency order)
   ↓
3. Bridge Tables (after dimensions)
   ↓
4. Fact Tables (after dimensions and bridges)
   ↓
5. Application Views (automatically reflect changes)
```

**Example**:
```sql
-- 1. Staging
EXEC Staging.UpdateCustomerRegion;

-- 2. Dimensions (independent first, then dependent)
EXEC Dim.SynchronizeCustomerCategory;
EXEC Dim.SynchronizeCustomer;  -- depends on CustomerCategory
EXEC Dim.SynchronizeProduct;
EXEC Dim.SynchronizeEmployee;
EXEC Dim.SynchronizeDate;

-- 3. Bridge Tables
EXEC Bridge.SynchronizeProductCategory;

-- 4. Fact Tables
EXEC Fact.SynchronizeSales;
```

## Benefits and Rationale

### Why Dimensional Modeling?

**Traditional Normalized Schema** (3NF):
```
Orders → Customers → CustomerTypes
      → OrderLines → Products → ProductCategories
                  → Suppliers → SupplierRegions
```
**Problems for Analytics**:
- Complex multi-table joins for simple questions
- Difficult for business users to understand
- Poor query performance for aggregations
- Hard to add new measures or attributes

**Dimensional Model** (Star Schema):
```
      Customer Dim ─┐
         Product Dim ┼─→ Sales Fact
            Date Dim ─┘
```
**Advantages for Analytics**:
- ✅ Intuitive structure (matches business thinking)
- ✅ Simple queries (minimal joins)
- ✅ Excellent performance (indexed foreign keys)
- ✅ Flexible (easy to add dimensions/measures)
- ✅ Consistent (conformed dimensions)

### Why Surrogate Keys?

**Natural Key Problems**:
- Change over time (customer ID reassignment)
- Composite keys (CustomerID + CompanyID)
- Different formats across sources (SAP vs Salesforce)
- String keys (poor performance)

**Surrogate Key Benefits**:
- ✅ Never change (stable fact references)
- ✅ Single integer (optimal performance)
- ✅ Source-independent (integration friendly)
- ✅ Enable history tracking (SCD Type 2)
- ✅ Smaller fact tables (compact foreign keys)

### Why Special Members?

**NULL Foreign Key Problems**:
```sql
-- Query without special members
SELECT 
    ISNULL(c.CustomerName, '(No Customer)') AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
LEFT JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Problems**:
- Outer joins in every query (complexity + performance)
- NULL handling in every aggregation
- Inconsistent display of NULL values
- No referential integrity constraint

**Special Members Solution**:
```sql
-- Query with special members
SELECT 
    c.CustomerName AS Customer,
    SUM(s.LineTotal) AS Sales
FROM Fact.Sales s
INNER JOIN Dim.Customer c ON s.CustomerKey = c.CustomerKey
GROUP BY c.CustomerName;
```
**Benefits**:
- ✅ Inner joins (simpler, faster)
- ✅ Referential integrity enforced
- ✅ Consistent NULL representation ('(Empty)', '(Unknown)')
- ✅ Auditing (count Unknown to find data quality issues)
- ✅ All facts load (missing dimensions don't block loading)

### Why View-Based Synchronization?

**Direct Table Updates**:
```sql
-- Transform logic embedded in procedure
UPDATE Dim.Customer SET Name = ...
```
**Problems**:
- Logic hidden in procedural code
- Hard to test transformations
- Difficult to verify "current state"
- Can't query transformation results before committing

**View-Based Approach**:
```sql
-- Logic in view (declarative SQL)
CREATE VIEW Dim.CustomerView AS ...
-- Materialize in table
MERGE Dim.Customer ... USING Dim.CustomerView
```
**Benefits**:
- ✅ Transformation logic visible (SELECT from view)
- ✅ Easy to test (compare view vs table)
- ✅ Consistent pattern (same as Landing)
- ✅ Can query view independently
- ✅ Clear separation of concerns

### Why Application Schemas?

**Direct Access to Core Tables**:
```sql
-- ERP queries Fact.ProductionOrders directly
GRANT SELECT ON Fact.ProductionOrders TO dw_erp;
```
**Problems**:
- Security risk (application sees all columns/tables)
- Tight coupling (schema changes break applications)
- No abstraction (can't change underlying model)
- Performance (applications may write inefficient queries)

**Application Schema Approach**:
```sql
-- ERP queries vERP.ProductionOrders (curated view)
GRANT SELECT ON SCHEMA::vERP TO dw_erp;
```
**Benefits**:
- ✅ Security (principle of least privilege)
- ✅ Abstraction (can refactor underlying tables)
- ✅ Simplification (complex logic hidden in views)
- ✅ Optimization (indexed views if needed)
- ✅ Versioning (maintain old view while migrating)

## Examples

### Example 1: Complete Dimension Implementation

**Landing Source**:
```sql
-- Landing.ERP.Customer
CompanyId | CustomerId | CustomerName   | VAT      | CategoryId
----------|------------|----------------|----------|------------
1         | 100        | Acme Corp      | IT12345  | 1
1         | 101        | Beta LLC       | IT67890  | 2
```

**Staging Enrichment**:
```sql
-- Staging.CustomerRegion (derived from postal code logic)
CREATE TABLE Staging.CustomerRegion
(
    CustomerId  INT,
    RegionId    INT,
    RegionName  NVARCHAR(50)
);
```

**Dimension View**:
```sql
CREATE VIEW Dim.CustomerView
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
    ct.CategoryName AS Category,
    cr.RegionName AS Region
FROM [Landing].[ERP].[Customer] c
LEFT JOIN [Landing].[ERP].[CustomerCategory] ct 
    ON c.CategoryId = ct.CategoryId
LEFT JOIN [Staging].[CustomerRegion] cr 
    ON c.CustomerId = cr.CustomerId
WHERE c.IsDeleted = 0;
```

**Dimension Table After Sync**:
```sql
-- Dim.Customer
CustomerKey | CompanyId | CustomerId | Name          | Category   | Region
------------|-----------|------------|---------------|------------|--------
-1          | -1        | -1         | (Empty)       | (Empty)    | (Empty)
-101        | -101      | -101       | (Unknown)     | (Unknown)  | (Unknown)
1           | 1         | 100        | Acme Corp     | Premium    | North
2           | 1         | 101        | Beta LLC      | Standard   | South
```

### Example 2: Complete Fact Implementation

**Landing Sources**:
```sql
-- Landing.ERP.Order
CompanyId | OrderId | CustomerId | OrderDate  | SalesPersonId
----------|---------|------------|------------|---------------
1         | 1001    | 100        | 2026-05-15 | 5
1         | 1002    | 999        | 2026-05-16 | NULL

-- Landing.ERP.OrderDetail
CompanyId | OrderId | LineNum | ProductId | Quantity | UnitPrice
----------|---------|---------|-----------|----------|----------
1         | 1001    | 1       | 200       | 10       | 50.00
1         | 1002    | 1       | 201       | 5        | 100.00
```

**Dimension Tables**:
```sql
-- Dim.Customer
CustomerKey | CustomerId
------------|------------
-1          | -1         (Empty)
-101        | -101       (Unknown)
1           | 100        (Acme Corp - exists)
-- Customer 999 doesn't exist

-- Dim.Employee
EmployeeKey | EmployeeId
------------|------------
-1          | -1         (Empty)
-101        | -101       (Unknown)
10          | 5          (John Doe - exists)
```

**Fact View**:
```sql
CREATE VIEW Fact.SalesView
AS
SELECT
    od.CompanyId,
    od.OrderId,
    od.LineNumber,
    od.ChangeHashKey,
    od.InsertDatetime,
    od.UpdateDatetime,
    od.IsDeleted,
    
    -- Dimension lookups with special member fallback
    COALESCE(dc.CustomerKey, 
        CASE WHEN o.CustomerId IS NULL THEN -1 ELSE -101 END) AS CustomerKey,
    COALESCE(dp.ProductKey, 
        CASE WHEN od.ProductId IS NULL THEN -1 ELSE -101 END) AS ProductKey,
    COALESCE(de.EmployeeKey, 
        CASE WHEN o.SalesPersonId IS NULL THEN -1 ELSE -101 END) AS SalesPersonKey,
    
    od.Quantity,
    od.UnitPrice,
    od.Quantity * od.UnitPrice AS LineTotal
    
FROM [Landing].[ERP].[OrderDetail] od
INNER JOIN [Landing].[ERP].[Order] o 
    ON od.CompanyId = o.CompanyId AND od.OrderId = o.OrderId
LEFT JOIN Dim.Customer dc 
    ON o.CustomerId = dc.CustomerId AND dc.IsDeleted = 0
LEFT JOIN Dim.Product dp 
    ON od.ProductId = dp.ProductId AND dp.IsDeleted = 0
LEFT JOIN Dim.Employee de 
    ON o.SalesPersonId = de.EmployeeId AND de.IsDeleted = 0
WHERE od.IsDeleted = 0;
```

**Fact Table After Sync**:
```sql
-- Fact.Sales
CompanyId | OrderId | LineNum | CustomerKey | SalesPersonKey | ProductKey | Quantity | LineTotal
----------|---------|---------|-------------|----------------|------------|----------|----------
1         | 1001    | 1       | 1           | 10             | 5          | 10       | 500.00
1         | 1002    | 1       | -101        | -1             | 6          | 5        | 500.00
          (Customer 999 → Unknown)  (NULL → Empty)
```

**Analysis Query**:
```sql
-- Sales by Customer (including Unknown and Empty)
SELECT 
    c.Name AS Customer,
    SUM(f.LineTotal) AS TotalSales,
    COUNT(*) AS OrderCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY c.Name;

-- Result:
-- Customer        TotalSales  OrderCount
-- Acme Corp       500.00      1
-- (Unknown)       500.00      1  ← Data quality issue: Customer 999 missing
```

### Example 3: Bridge Table for Many-to-Many

**Scenario**: Products can belong to multiple categories

**Landing Data**:
```sql
-- Landing.ERP.ProductCategoryMapping
ProductId | CategoryId
----------|------------
200       | 1          (Electronics)
200       | 3          (Accessories)
201       | 1          (Electronics)
```

**Bridge Table**:
```sql
-- Bridge.ProductCategory
ProductKey | CategoryKey | AllocationPercent
-----------|-------------|-------------------
5          | 10          | 50.00
5          | 12          | 50.00
6          | 10          | 100.00
```

**Query with Bridge**:
```sql
-- Sales by Category (with allocation)
SELECT 
    cat.CategoryName,
    SUM(f.LineTotal * b.AllocationPercent / 100) AS AllocatedSales
FROM Fact.Sales f
INNER JOIN Bridge.ProductCategory b ON f.ProductKey = b.ProductKey
INNER JOIN Dim.Category cat ON b.CategoryKey = cat.CategoryKey
GROUP BY cat.CategoryName;

-- Result:
-- CategoryName      AllocatedSales
-- Electronics       750.00  (500 * 50% + 500 * 100%)
-- Accessories       250.00  (500 * 50%)
```

## Best Practices

### 1. Dimension Design

**Keep Dimensions Denormalized**:
```sql
-- Good: Denormalized (star schema)
Dim.Customer: CustomerKey, Name, Category, Region, Segment

-- Bad: Normalized (snowflake schema)
Dim.Customer: CustomerKey, Name, CategoryKey
Dim.CustomerCategory: CategoryKey, CategoryName, RegionKey
Dim.Region: RegionKey, RegionName
```
**Why**: Snowflake schemas require more joins, reducing query performance and user-friendliness.

**Use Meaningful Special Member Labels**:
```sql
-- Good: Clear labeling
Name = '(Empty)'  or '(Not Applicable)'
Name = '(Unknown)' or '(Missing Reference)'

-- Bad: Ambiguous
Name = 'N/A'
Name = 'NULL'
Name = ''
```

**Add Row Count Attributes for Aggregation**:
```sql
-- Add to dimension table for easy counting
RowCount INT NOT NULL DEFAULT 1

-- Enables accurate counts in reports
SELECT Customer, SUM(RowCount) AS TransactionCount
FROM Fact.Sales f
INNER JOIN Dim.Customer c ON f.CustomerKey = c.CustomerKey
GROUP BY Customer;
```

### 2. Fact Table Design

**Declare Grain Explicitly**:
```sql
-- Document grain in comments
-- GRAIN: One row per order line (CompanyId, OrderId, LineNumber)
CREATE TABLE Fact.Sales (...);

-- Bad: Ambiguous grain
CREATE TABLE Fact.Sales (...);  -- No documentation
```

**Separate Transaction and Snapshot Facts**:
```sql
-- Transaction Fact (one row per event)
Fact.Sales: OrderId, LineNumber, Quantity, LineTotal

-- Snapshot Fact (one row per period)
Fact.InventorySnapshot: DateKey, ProductKey, QuantityOnHand, Value
```

**Include Audit Columns**:
```sql
-- Include technical columns for troubleshooting
ChangeHashKey BINARY(32),
InsertDatetime DATETIME,
UpdateDatetime DATETIME,
IsDeleted BIT
```

### 3. Surrogate Key Management

**Use Sequences (not IDENTITY)**:
```sql
-- Good: Sequence (allows pre-generation)
CREATE SEQUENCE Dim.CustomerSequence;
CustomerKey = NEXT VALUE FOR Dim.CustomerSequence

-- Bad: IDENTITY (can't control value before insert)
CustomerKey INT IDENTITY(1,1)
```

**Reserve Ranges for Special Members**:
```sql
-- Negative keys for special members
-1: Empty
-101: Unknown
-201, -202, etc.: Other special members (e.g., -201 = 'Not Yet Available')

-- Positive keys for data
1, 2, 3, ...: Actual dimension members
```

### 4. Performance Optimization

**Index Fact Table Foreign Keys**:
```sql
-- Create covering indexes for common queries
CREATE NONCLUSTERED INDEX IX_Sales_Customer 
    ON Fact.Sales (CustomerKey) 
    INCLUDE (OrderDateKey, LineTotal, Quantity);

CREATE NONCLUSTERED INDEX IX_Sales_Date 
    ON Fact.Sales (OrderDateKey) 
    INCLUDE (CustomerKey, ProductKey, LineTotal);
```

**Partition Large Fact Tables**:
```sql
-- Partition by date for large fact tables
CREATE PARTITION FUNCTION PF_SalesByYear (DATE)
AS RANGE RIGHT FOR VALUES 
    ('2024-01-01', '2025-01-01', '2026-01-01');

CREATE PARTITION SCHEME PS_SalesByYear
AS PARTITION PF_SalesByYear ALL TO ([PRIMARY]);

CREATE TABLE Fact.Sales (
    ...
    OrderDate DATE NOT NULL
) ON PS_SalesByYear(OrderDate);
```

**Use Columnstore Indexes for Large Facts**:
```sql
-- Columnstore for analytical workloads (100M+ rows)
CREATE CLUSTERED COLUMNSTORE INDEX CCI_Sales 
    ON Fact.Sales;

-- Or non-clustered columnstore with rowstore primary
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Sales 
    ON Fact.Sales (CustomerKey, ProductKey, OrderDateKey, LineTotal, Quantity);
```

### 5. Data Quality

**Monitor Unknown Members**:
```sql
-- Create view to identify data quality issues
CREATE VIEW Audit.UnknownMemberUsage
AS
SELECT 
    'Customer' AS Dimension,
    COUNT(*) AS UnknownCount,
    SUM(LineTotal) AS ImpactAmount
FROM Fact.Sales
WHERE CustomerKey = -101

UNION ALL

SELECT 
    'Product' AS Dimension,
    COUNT(*) AS UnknownCount,
    SUM(LineTotal) AS ImpactAmount
FROM Fact.Sales
WHERE ProductKey = -101;
```

**Validate Referential Integrity**:
```sql
-- Check for orphaned fact records (should never happen with FKs)
SELECT 'Orphaned Sales' AS Issue, COUNT(*) AS Count
FROM Fact.Sales f
WHERE NOT EXISTS (
    SELECT 1 FROM Dim.Customer c WHERE c.CustomerKey = f.CustomerKey
);
```

### 6. Testing and Validation

**Compare View vs Table Row Counts**:
```sql
-- Validate synchronization completeness
SELECT 
    'View' AS Source, 
    COUNT(*) AS RowCount,
    SUM(CAST(ChangeHashKey AS BIGINT)) AS HashSum
FROM Dim.CustomerView
WHERE IsDeleted = 0

UNION ALL

SELECT 
    'Table' AS Source, 
    COUNT(*) AS RowCount,
    SUM(CAST(ChangeHashKey AS BIGINT)) AS HashSum
FROM Dim.Customer
WHERE IsDeleted = 0
    AND CustomerKey NOT IN (-1, -101);  -- Exclude special members
```

**Test Special Member Handling**:
```sql
-- Verify special members exist and are never modified
SELECT 
    'Customer' AS Dimension,
    COUNT(*) AS SpecialMemberCount
FROM Dim.Customer
WHERE CustomerKey IN (-1, -101);

-- Should always return: Dimension = 'Customer', SpecialMemberCount = 2
```

### 7. Documentation

**Document Each Dimension and Fact**:
```sql
-- Add extended properties for documentation
EXEC sp_addextendedproperty 
    @name = N'Description',
    @value = N'Customer dimension containing all customer master data from ERP and Salesforce systems. Grain: One row per unique customer (CompanyId + CustomerId).',
    @level0type = N'SCHEMA', @level0name = 'Dim',
    @level1type = N'TABLE', @level1name = 'Customer';

-- Document columns
EXEC sp_addextendedproperty 
    @name = N'Description',
    @value = N'Surrogate key for Customer dimension. Generated from Dim.CustomerSequence.',
    @level0type = N'SCHEMA', @level0name = 'Dim',
    @level1type = N'TABLE', @level1name = 'Customer',
    @level2type = N'COLUMN', @level2name = 'CustomerKey';
```

**Maintain Data Dictionary**:
```sql
-- Create metadata table
CREATE TABLE Metadata.DataDictionary
(
    SchemaName      NVARCHAR(50),
    TableName       NVARCHAR(100),
    ColumnName      NVARCHAR(100),
    DataType        NVARCHAR(50),
    Description     NVARCHAR(500),
    SourceSystem    NVARCHAR(50),
    SourceTable     NVARCHAR(100),
    SourceColumn    NVARCHAR(100)
);
```

---

## Summary

This Data Warehouse design pattern provides:

✅ **Dimensional Modeling**: Star schema optimized for analytics  
✅ **Integration**: Combines multiple sources into unified business entities  
✅ **Performance**: Surrogate keys and proper indexing for fast queries  
✅ **Data Quality**: Special members ensure referential integrity  
✅ **Flexibility**: View-based synchronization allows easy schema evolution  
✅ **Security**: Application-specific schemas with principle of least privilege  
✅ **Consistency**: Same synchronization pattern as Landing layer  
✅ **Maintainability**: Clear separation between logic (views) and storage (tables)  

By following these principles, you create a robust, performant, and user-friendly data warehouse that serves as a reliable foundation for business intelligence, reporting, and analytics.

---

**Document Version**: 1.0  
**Last Updated**: May 20, 2026  
**Technology Stack**: Microsoft SQL Server 2016+  
**Methodology**: Kimball Dimensional Modeling
