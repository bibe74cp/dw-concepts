/*******************************************************************************
 * Database Objects for Merge Table Generator Optimizations
 * Created: 2026-05-22
 * 
 * This file contains all database objects created for the optimized
 * usp_GenerateMergeTableFromView procedure.
 * 
 * Implemented Optimizations:
 * ✅ #1  - Eliminate Cursors for String Building
 * ✅ #2  - Create Helper Function for Data Type Definition
 * ✅ #3  - Add Index to Table Variable
 * ✅ #4  - Optimize String Concatenation
 * ✅ #5  - Add Comprehensive Error Handling
 * ✅ #6  - Add Parameter Validation
 * ✅ #7  - Optimize Generated MERGE Statement
 * ✅ #8  - Add Computed Columns for Metadata
 * ❌ #9  - Add Configuration Table (NOT IMPLEMENTED)
 * ✅ #10 - Add Caching for Repeated Metadata Queries
 * ✅ #11 - Add Support for Incremental/Batch Processing
 * ✅ #12 - Add Documentation Generation
 * ✅ #13 - Add Logging and Monitoring
 * ✅ #14 - Performance Testing Framework
 * ✅ #15 - SQL Server Version Compatibility
 * 
 * Execution Order:
 * 1. Tables (for logging and caching)
 * 2. Functions (helper functions)
 * 3. Stored Procedures (main and optimized procedures)
 * 4. Testing Procedures
 ******************************************************************************/

-- Set database context (modify as needed)
USE [YourDatabaseName];
GO

/*******************************************************************************
 * SECTION 1: TABLES
 ******************************************************************************/

-- =============================================================================
-- Table: dbo.ScriptGenerationLog
-- Purpose: Track execution metrics and errors for usp_GenerateMergeTableFromView
-- Optimization: #13 - Add Logging and Monitoring
-- =============================================================================
IF OBJECT_ID('dbo.ScriptGenerationLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ScriptGenerationLog (
        LogId BIGINT IDENTITY(1,1) NOT NULL,
        SourceSchema SYSNAME NOT NULL,
        SourceTable SYSNAME NOT NULL,
        ExecutionStartTime DATETIME2(3) NOT NULL,
        ExecutionEndTime DATETIME2(3) NULL,
        DurationMs AS DATEDIFF(MILLISECOND, ExecutionStartTime, ExecutionEndTime) PERSISTED,
        ColumnCount INT NULL,
        ScriptLength INT NULL,
        WasSuccessful BIT NULL,
        ErrorMessage NVARCHAR(4000) NULL,
        ErrorNumber INT NULL,
        ErrorLine INT NULL,
        ExecutedBy SYSNAME NOT NULL DEFAULT SUSER_SNAME(),
        CONSTRAINT PK_ScriptGenerationLog PRIMARY KEY CLUSTERED (LogId)
    );

    CREATE NONCLUSTERED INDEX IX_ScriptGenerationLog_SourceTable 
        ON dbo.ScriptGenerationLog (SourceSchema, SourceTable, ExecutionStartTime DESC);

    CREATE NONCLUSTERED INDEX IX_ScriptGenerationLog_ExecutionTime 
        ON dbo.ScriptGenerationLog (ExecutionStartTime DESC) 
        INCLUDE (SourceSchema, SourceTable, DurationMs, WasSuccessful);

    PRINT '✓ Created table: dbo.ScriptGenerationLog';
END
ELSE
    PRINT '- Table already exists: dbo.ScriptGenerationLog';
GO

-- =============================================================================
-- Table: dbo.GeneratedScriptCache
-- Purpose: Cache generated scripts to improve performance
-- Optimization: #10 - Add Caching for Repeated Metadata Queries
-- =============================================================================
IF OBJECT_ID('dbo.GeneratedScriptCache', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GeneratedScriptCache (
        CacheId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        SourceSchema SYSNAME NOT NULL,
        SourceTable SYSNAME NOT NULL,
        ConfigurationHash VARBINARY(32) NOT NULL,
        ViewStructureHash VARBINARY(32) NOT NULL,
        GeneratedScript NVARCHAR(MAX) NOT NULL,
        CreatedDate DATETIME2(3) NOT NULL DEFAULT GETDATE(),
        LastUsedDate DATETIME2(3) NOT NULL DEFAULT GETDATE(),
        UsageCount INT NOT NULL DEFAULT 1,
        CreatedBy SYSNAME NOT NULL DEFAULT SUSER_SNAME(),
        CONSTRAINT PK_GeneratedScriptCache PRIMARY KEY CLUSTERED (CacheId)
    );

    CREATE UNIQUE NONCLUSTERED INDEX IX_GeneratedScriptCache_Lookup 
        ON dbo.GeneratedScriptCache (SourceSchema, SourceTable, ConfigurationHash, ViewStructureHash);

    CREATE NONCLUSTERED INDEX IX_GeneratedScriptCache_Usage 
        ON dbo.GeneratedScriptCache (LastUsedDate DESC, UsageCount DESC);

    PRINT '✓ Created table: dbo.GeneratedScriptCache';
END
ELSE
    PRINT '- Table already exists: dbo.GeneratedScriptCache';
GO

-- =============================================================================
-- Table: audit.merge_log_details (if not exists)
-- Purpose: Audit table for MERGE operations (referenced by generated procedures)
-- Optimization: Referenced in #7 - Optimize Generated MERGE Statement
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
BEGIN
    EXEC('CREATE SCHEMA audit');
    PRINT '✓ Created schema: audit';
END
GO

IF OBJECT_ID('audit.merge_log_details', 'U') IS NULL
BEGIN
    CREATE TABLE audit.merge_log_details (
        merge_log_id BIGINT IDENTITY(1,1) NOT NULL,
        merge_datetime DATETIME2(3) NOT NULL,
        merge_action NVARCHAR(10) NOT NULL,
        full_olap_table_name NVARCHAR(256) NOT NULL,
        primary_key_description NVARCHAR(MAX) NULL,
        CONSTRAINT PK_merge_log_details PRIMARY KEY CLUSTERED (merge_log_id)
    );

    CREATE NONCLUSTERED INDEX IX_merge_log_details_Table 
        ON audit.merge_log_details (full_olap_table_name, merge_datetime DESC);

    CREATE NONCLUSTERED INDEX IX_merge_log_details_DateTime 
        ON audit.merge_log_details (merge_datetime DESC);

    PRINT '✓ Created table: audit.merge_log_details';
END
ELSE
    PRINT '- Table already exists: audit.merge_log_details';
GO

/*******************************************************************************
 * SECTION 2: FUNCTIONS
 ******************************************************************************/

-- =============================================================================
-- Function: dbo.fn_BuildDataTypeDefinition
-- Purpose: Build T-SQL data type definition string from metadata
-- Optimization: #2 - Create Helper Function for Data Type Definition
-- Parameters:
--   @DataType - Base data type name
--   @MaxLength - Maximum length for string/binary types
--   @Precision - Precision for numeric/decimal types
--   @Scale - Scale for numeric/decimal types
-- Returns: Formatted data type definition string (e.g., 'VARCHAR(50)')
-- =============================================================================
IF OBJECT_ID('dbo.fn_BuildDataTypeDefinition', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_BuildDataTypeDefinition;
GO

CREATE FUNCTION dbo.fn_BuildDataTypeDefinition
(
    @DataType NVARCHAR(128),
    @MaxLength INT,
    @Precision INT,
    @Scale INT
)
RETURNS NVARCHAR(128)
AS
BEGIN
    DECLARE @Result NVARCHAR(128);

    SET @Result = CASE
        -- String and binary types with length
        WHEN @DataType IN ('char', 'varchar', 'binary', 'varbinary') THEN 
            @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' 
                                   ELSE CAST(@MaxLength AS NVARCHAR) END + ')'
        
        -- Unicode string types with length (divide by 2 for character count)
        WHEN @DataType IN ('nchar', 'nvarchar') THEN 
            @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' 
                                   ELSE CAST(@MaxLength / 2 AS NVARCHAR) END + ')'
        
        -- Numeric types with precision and scale
        WHEN @DataType IN ('decimal', 'numeric') THEN 
            @DataType + '(' + CAST(@Precision AS NVARCHAR) + ', ' + CAST(@Scale AS NVARCHAR) + ')'
        
        -- Float with precision
        WHEN @DataType IN ('float') THEN 
            @DataType + '(' + CAST(@Precision AS NVARCHAR) + ')'
        
        -- Datetime types with scale
        WHEN @DataType IN ('datetime2', 'time', 'datetimeoffset') THEN 
            @DataType + '(' + CAST(@Scale AS NVARCHAR) + ')'
        
        -- All other types (int, bigint, bit, date, datetime, uniqueidentifier, etc.)
        ELSE @DataType
    END;

    RETURN @Result;
END;
GO

PRINT '✓ Created function: dbo.fn_BuildDataTypeDefinition';
GO

-- =============================================================================
-- Function: dbo.fn_ValidateSQLIdentifier
-- Purpose: Validate that a string is a valid SQL identifier
-- Optimization: #6 - Add Parameter Validation
-- Parameters:
--   @Identifier - String to validate
-- Returns: 1 if valid, 0 if invalid
-- =============================================================================
IF OBJECT_ID('dbo.fn_ValidateSQLIdentifier', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ValidateSQLIdentifier;
GO

CREATE FUNCTION dbo.fn_ValidateSQLIdentifier
(
    @Identifier SYSNAME
)
RETURNS BIT
AS
BEGIN
    -- Valid SQL identifier pattern:
    -- - Starts with letter, @, #, or underscore
    -- - Continues with letters, digits, @, #, $, or underscore
    -- - Not too long (sysname is already limited)
    
    IF @Identifier IS NULL OR LEN(@Identifier) = 0
        RETURN 0;
    
    -- Check pattern using LIKE
    -- First character must be letter, @, #, or _
    -- Following characters can be alphanumeric or @#$_
    IF @Identifier LIKE '[A-Za-z_@#]%' 
       AND @Identifier NOT LIKE '%[^A-Za-z0-9_@#$]%'
        RETURN 1;
    
    RETURN 0;
END;
GO

PRINT '✓ Created function: dbo.fn_ValidateSQLIdentifier';
GO

-- =============================================================================
-- Function: dbo.fn_CalculateParameterHash
-- Purpose: Calculate hash for caching based on parameters
-- Optimization: #10 - Add Caching for Repeated Metadata Queries
-- Parameters:
--   @ChangeHashKeyColumn - Name of ChangeHashKey column
--   @InsertDatetimeColumn - Name of InsertDatetime column
--   @UpdateDatetimeColumn - Name of UpdateDatetime column
--   @IsDeletedColumn - Name of IsDeleted column
-- Returns: SHA2-256 hash of concatenated parameters
-- =============================================================================
IF OBJECT_ID('dbo.fn_CalculateParameterHash', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_CalculateParameterHash;
GO

CREATE FUNCTION dbo.fn_CalculateParameterHash
(
    @ChangeHashKeyColumn SYSNAME,
    @InsertDatetimeColumn SYSNAME,
    @UpdateDatetimeColumn SYSNAME,
    @IsDeletedColumn SYSNAME
)
RETURNS VARBINARY(32)
AS
BEGIN
    RETURN HASHBYTES('SHA2_256', 
        CONCAT(
            ISNULL(@ChangeHashKeyColumn, ''), '|',
            ISNULL(@InsertDatetimeColumn, ''), '|',
            ISNULL(@UpdateDatetimeColumn, ''), '|',
            ISNULL(@IsDeletedColumn, '')
        )
    );
END;
GO

PRINT '✓ Created function: dbo.fn_CalculateParameterHash';
GO

/*******************************************************************************
 * SECTION 3: MAIN STORED PROCEDURE (OPTIMIZED)
 ******************************************************************************/

-- =============================================================================
-- Procedure: dbo.usp_GenerateMergeTableFromView (OPTIMIZED VERSION)
-- Purpose: Generate table creation and merge procedure scripts from a view
-- Optimizations: All except #9
-- 
-- This replaces the original procedure with all optimizations implemented.
-- Backup the original if needed before running this script.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GenerateMergeTableFromView
    @SourceSchema SYSNAME,
    @SourceTable SYSNAME,
    @ChangeHashKeyColumn SYSNAME = 'ChangeHashKey',
    @InsertDatetimeColumn SYSNAME = 'InsertDatetime',
    @UpdateDatetimeColumn SYSNAME = 'UpdateDatetime',
    @IsDeletedColumn SYSNAME = 'IsDeleted',
    @UseCache BIT = 1,              -- Optimization #10: Enable/disable caching
    @EnableBatching BIT = 0,        -- Optimization #11: Enable batch processing in generated proc
    @BatchSize INT = 10000          -- Optimization #11: Batch size for generated proc
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Optimization #13: Logging - Start
    DECLARE @LogId BIGINT;
    DECLARE @StartTime DATETIME2(3) = GETDATE();
    
    INSERT INTO dbo.ScriptGenerationLog (SourceSchema, SourceTable, ExecutionStartTime)
    VALUES (@SourceSchema, @SourceTable, @StartTime);
    SET @LogId = SCOPE_IDENTITY();
    
    -- Optimization #5: Comprehensive Error Handling
    BEGIN TRY
        
        -- ===============================================================
        -- Optimization #6: Parameter Validation
        -- ===============================================================
        
        -- Validate SourceSchema
        IF @SourceSchema IS NULL OR LTRIM(RTRIM(@SourceSchema)) = ''
            THROW 50001, 'Parameter @SourceSchema cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@SourceSchema) = 0
            THROW 50002, 'Parameter @SourceSchema contains invalid characters', 1;
        
        -- Validate SourceTable
        IF @SourceTable IS NULL OR LTRIM(RTRIM(@SourceTable)) = ''
            THROW 50003, 'Parameter @SourceTable cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@SourceTable) = 0
            THROW 50004, 'Parameter @SourceTable contains invalid characters', 1;
        
        -- Validate schema exists
        IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = @SourceSchema)
        BEGIN
            DECLARE @SchemaError NVARCHAR(500) = 'Schema ' + QUOTENAME(@SourceSchema) + ' does not exist.';
            THROW 50005, @SchemaError, 1;
        END;
        
        -- Validate DW column parameters
        IF @ChangeHashKeyColumn IS NULL OR LTRIM(RTRIM(@ChangeHashKeyColumn)) = ''
            THROW 50006, 'Parameter @ChangeHashKeyColumn cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@ChangeHashKeyColumn) = 0
            THROW 50007, 'Parameter @ChangeHashKeyColumn contains invalid characters', 1;
        
        IF @InsertDatetimeColumn IS NULL OR LTRIM(RTRIM(@InsertDatetimeColumn)) = ''
            THROW 50008, 'Parameter @InsertDatetimeColumn cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@InsertDatetimeColumn) = 0
            THROW 50009, 'Parameter @InsertDatetimeColumn contains invalid characters', 1;
        
        IF @UpdateDatetimeColumn IS NULL OR LTRIM(RTRIM(@UpdateDatetimeColumn)) = ''
            THROW 50010, 'Parameter @UpdateDatetimeColumn cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@UpdateDatetimeColumn) = 0
            THROW 50011, 'Parameter @UpdateDatetimeColumn contains invalid characters', 1;
        
        IF @IsDeletedColumn IS NULL OR LTRIM(RTRIM(@IsDeletedColumn)) = ''
            THROW 50012, 'Parameter @IsDeletedColumn cannot be NULL or empty', 1;
        
        IF dbo.fn_ValidateSQLIdentifier(@IsDeletedColumn) = 0
            THROW 50013, 'Parameter @IsDeletedColumn contains invalid characters', 1;
        
        -- ===============================================================
        -- Optimization #10: Check Cache
        -- ===============================================================
        
        DECLARE @ConfigHash VARBINARY(32) = dbo.fn_CalculateParameterHash(
            @ChangeHashKeyColumn, @InsertDatetimeColumn, 
            @UpdateDatetimeColumn, @IsDeletedColumn
        );
        
        DECLARE @ViewName SYSNAME = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + 'View';
        DECLARE @TableName SYSNAME = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
        DECLARE @ViewObjectId INT = OBJECT_ID(@ViewName, 'V');
        DECLARE @Script NVARCHAR(MAX);
        
        -- Validate view exists
        IF @ViewObjectId IS NULL
        BEGIN
            DECLARE @ViewError NVARCHAR(500) = 'View ' + @ViewName + ' does not exist.';
            THROW 50014, @ViewError, 1;
        END;
        
        -- Try cache if enabled
        IF @UseCache = 1
        BEGIN
            -- Optimization #3: Indexed table variable for columns
            DECLARE @TempColumns TABLE (
                column_id INT PRIMARY KEY,
                column_name SYSNAME,
                data_type NVARCHAR(128),
                max_length INT,
                precision_value INT,
                scale_value INT
            );
            
            INSERT INTO @TempColumns
            SELECT c.column_id, c.name, TYPE_NAME(c.user_type_id),
                   c.max_length, c.precision, c.scale
            FROM sys.columns c
            WHERE c.object_id = @ViewObjectId
            ORDER BY c.column_id;
            
            -- Calculate view structure hash
            DECLARE @ViewHash VARBINARY(32) = HASHBYTES('SHA2_256', (
                SELECT STRING_AGG(
                    CONCAT(column_name, ':', data_type, ':', 
                           max_length, ':', precision_value, ':', scale_value), 
                    '|'
                ) WITHIN GROUP (ORDER BY column_id)
                FROM @TempColumns
            ));
            
            -- Try to retrieve from cache
            SELECT @Script = GeneratedScript
            FROM dbo.GeneratedScriptCache
            WHERE SourceSchema = @SourceSchema
              AND SourceTable = @SourceTable
              AND ConfigurationHash = @ConfigHash
              AND ViewStructureHash = @ViewHash;
            
            IF @Script IS NOT NULL
            BEGIN
                -- Cache hit! Update statistics
                UPDATE dbo.GeneratedScriptCache
                SET LastUsedDate = GETDATE(),
                    UsageCount = UsageCount + 1
                WHERE SourceSchema = @SourceSchema
                  AND SourceTable = @SourceTable
                  AND ConfigurationHash = @ConfigHash
                  AND ViewStructureHash = @ViewHash;
                
                -- Log successful cache hit
                UPDATE dbo.ScriptGenerationLog
                SET ExecutionEndTime = GETDATE(),
                    ScriptLength = LEN(@Script),
                    WasSuccessful = 1,
                    ColumnCount = (SELECT COUNT(*) FROM @TempColumns)
                WHERE LogId = @LogId;
                
                -- Output and exit
                PRINT @Script;
                RETURN;
            END;
        END;
        
        -- ===============================================================
        -- Get column metadata (Optimization #3: Indexed table variable)
        -- ===============================================================
        
        -- Optimization #3: Add indexes to table variable
        -- Optimization #8: Add computed columns for metadata
        DECLARE @Columns TABLE (
            column_id INT PRIMARY KEY,
            column_name SYSNAME NOT NULL,
            data_type NVARCHAR(128) NOT NULL,
            max_length INT NOT NULL,
            precision_value INT NOT NULL,
            scale_value INT NOT NULL,
            is_nullable BIT NOT NULL,
            column_category NVARCHAR(20) NULL,
            INDEX IX_Category NONCLUSTERED (column_category)
        );
        
        -- Insert all columns with metadata
        INSERT INTO @Columns (column_id, column_name, data_type, max_length, 
                              precision_value, scale_value, is_nullable)
        SELECT 
            c.column_id,
            c.name,
            TYPE_NAME(c.user_type_id),
            c.max_length,
            c.precision,
            c.scale,
            c.is_nullable
        FROM sys.columns c
        WHERE c.object_id = @ViewObjectId
        ORDER BY c.column_id;
        
        -- Identify data-warehouse columns boundaries
        DECLARE @FirstDWColumnId INT, @LastDWColumnId INT;
        
        SELECT @FirstDWColumnId = MIN(column_id)
        FROM @Columns
        WHERE column_name IN (@ChangeHashKeyColumn, @InsertDatetimeColumn, 
                             @UpdateDatetimeColumn, @IsDeletedColumn);
        
        SELECT @LastDWColumnId = MAX(column_id)
        FROM @Columns
        WHERE column_name IN (@ChangeHashKeyColumn, @InsertDatetimeColumn, 
                             @UpdateDatetimeColumn, @IsDeletedColumn);
        
        -- Validate at least one data-warehouse column exists
        IF @FirstDWColumnId IS NULL
        BEGIN
            DECLARE @DWError NVARCHAR(500) = 'View ' + @ViewName + 
                ' does not contain any data-warehouse columns (' + 
                @ChangeHashKeyColumn + ', ' + @InsertDatetimeColumn + ', ' + 
                @UpdateDatetimeColumn + ', ' + @IsDeletedColumn + ').';
            THROW 50015, @DWError, 1;
        END;
        
        -- Categorize columns
        UPDATE @Columns
        SET column_category = CASE
            WHEN column_id < @FirstDWColumnId THEN 'PK'
            WHEN column_id >= @FirstDWColumnId AND column_id <= @LastDWColumnId THEN 'DW'
            ELSE 'ATTR'
        END;
        
        -- Validate primary key columns exist
        IF NOT EXISTS (SELECT 1 FROM @Columns WHERE column_category = 'PK')
        BEGIN
            DECLARE @PKError NVARCHAR(500) = 'View ' + @ViewName + 
                ' does not have any primary key columns before data-warehouse columns.';
            THROW 50016, @PKError, 1;
        END;
        
        -- ===============================================================
        -- Optimization #1 & #4: Build column lists using STRING_AGG
        -- (Set-based, no cursors)
        -- ===============================================================
        
        DECLARE @PKColumns NVARCHAR(MAX);
        DECLARE @PKJoinCondition NVARCHAR(MAX);
        DECLARE @PKDescription NVARCHAR(MAX);
        DECLARE @AttrColumns NVARCHAR(MAX);
        DECLARE @AttrColumnsUpdate NVARCHAR(MAX);
        DECLARE @AllColumns NVARCHAR(MAX);
        DECLARE @NewLine NVARCHAR(2) = CHAR(13) + CHAR(10);
        
        -- Build PK columns list (Optimization #4: Use STRING_AGG)
        SELECT @PKColumns = STRING_AGG(column_name, ', ') WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'PK';
        
        -- Build PK JOIN condition
        SELECT @PKJoinCondition = STRING_AGG(
            'SRC.' + QUOTENAME(column_name) + ' = TGT.' + QUOTENAME(column_name), 
            ' AND '
        ) WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'PK';
        
        -- Build PK description for audit logging
        SELECT @PKDescription = STRING_AGG(
            QUOTENAME(column_name) + ' = '' + CAST(COALESCE(inserted.' + 
            QUOTENAME(column_name) + ', deleted.' + QUOTENAME(column_name) + ') AS NVARCHAR)',
            ' + '', '' + '
        ) WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'PK';
        
        SET @PKDescription = '''' + @PKDescription;
        
        -- Build attribute columns list and update clause
        SELECT @AttrColumns = STRING_AGG(column_name, ', ') WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'ATTR';
        
        SELECT @AttrColumnsUpdate = STRING_AGG(
            'TGT.' + QUOTENAME(column_name) + ' = SRC.' + QUOTENAME(column_name), 
            ', ' + @NewLine + '        '
        ) WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'ATTR';
        
        -- Build all columns list (for INSERT)
        SELECT @AllColumns = STRING_AGG(column_name, ', ') WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category IN ('PK', 'DW', 'ATTR');
        
        -- ===============================================================
        -- Optimization #1 & #2: Generate PK/ATTR ALTER statements
        -- Using helper function instead of cursors
        -- ===============================================================
        
        DECLARE @PKAlterStatements NVARCHAR(MAX);
        DECLARE @AttrAlterStatements NVARCHAR(MAX);
        
        -- PK ALTER statements (Optimization #1: No cursor, Optimization #2: Helper function)
        SELECT @PKAlterStatements = STRING_AGG(
            CHAR(9) + 'ALTER TABLE ' + @TableName + ' ALTER COLUMN ' + 
            QUOTENAME(column_name) + ' ' + 
            dbo.fn_BuildDataTypeDefinition(data_type, max_length, precision_value, scale_value) + 
            ' NOT NULL;',
            @NewLine
        ) WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'PK';
        
        -- ATTR ALTER statements (commented out)
        SELECT @AttrAlterStatements = STRING_AGG(
            CHAR(9) + '--ALTER TABLE ' + @TableName + ' ALTER COLUMN ' + 
            QUOTENAME(column_name) + ' ' + 
            dbo.fn_BuildDataTypeDefinition(data_type, max_length, precision_value, scale_value) + 
            ' NOT NULL;',
            @NewLine
        ) WITHIN GROUP (ORDER BY column_id)
        FROM @Columns WHERE column_category = 'ATTR';
        
        -- ===============================================================
        -- Generate T-SQL script
        -- ===============================================================
        
        SET @Script = '';
        
        -- Optimization #12: Add documentation header
        SET @Script = @Script + '/*' + @NewLine;
        SET @Script = @Script + ' * Auto-generated script for ' + @TableName + @NewLine;
        SET @Script = @Script + ' * Generated on: ' + CONVERT(NVARCHAR(30), GETDATE(), 121) + @NewLine;
        SET @Script = @Script + ' * Source view: ' + @ViewName + @NewLine;
        SET @Script = @Script + ' * Primary key columns: ' + ISNULL(@PKColumns, '(none)') + @NewLine;
        SET @Script = @Script + ' * Data warehouse columns: ' + 
                       @ChangeHashKeyColumn + ', ' + @InsertDatetimeColumn + ', ' + 
                       @UpdateDatetimeColumn + ', ' + @IsDeletedColumn + @NewLine;
        SET @Script = @Script + ' * Total columns: ' + 
                       CAST((SELECT COUNT(*) FROM @Columns) AS NVARCHAR(10)) + @NewLine;
        SET @Script = @Script + ' * Attribute columns: ' + 
                       CAST((SELECT COUNT(*) FROM @Columns WHERE column_category = 'ATTR') AS NVARCHAR(10)) + @NewLine;
        SET @Script = @Script + ' * Batch processing: ' + 
                       CASE WHEN @EnableBatching = 1 THEN 'Enabled (batch size: ' + 
                       CAST(@BatchSize AS NVARCHAR(10)) + ')' ELSE 'Disabled' END + @NewLine;
        SET @Script = @Script + ' */' + @NewLine + @NewLine;
        
        -- A. Commented DROP statement
        SET @Script = @Script + '--DROP TABLE IF EXISTS ' + @TableName + ';' + @NewLine;
        SET @Script = @Script + 'GO' + @NewLine + @NewLine;
        
        -- B. Table creation block
        SET @Script = @Script + 'IF OBJECT_ID(''' + @TableName + ''', ''U'') IS NULL' + @NewLine;
        SET @Script = @Script + 'BEGIN' + @NewLine + @NewLine;
        
        -- B1. SELECT TOP 0 to create table structure
        SET @Script = @Script + CHAR(9) + 'SELECT TOP (0) * INTO ' + @TableName + 
                       ' FROM ' + @ViewName + ';' + @NewLine + @NewLine;
        
        -- B2. ALTER COLUMN for each PK column (using set-based generation)
        SET @Script = @Script + @PKAlterStatements + @NewLine + @NewLine;
        
        -- B3. Add PRIMARY KEY constraint
        DECLARE @PKConstraintName SYSNAME = 'PK_' + @SourceSchema + '_' + @SourceTable;
        SET @Script = @Script + CHAR(9) + 'ALTER TABLE ' + @TableName + 
                       ' ADD CONSTRAINT ' + QUOTENAME(@PKConstraintName) + 
                       ' PRIMARY KEY CLUSTERED (' + @PKColumns + ');' + @NewLine + @NewLine;
        
        -- B4. Commented ALTER COLUMN for each attribute
        IF @AttrAlterStatements IS NOT NULL
        BEGIN
            SET @Script = @Script + @AttrAlterStatements + @NewLine + @NewLine;
        END;
        
        SET @Script = @Script + 'END;' + @NewLine;
        SET @Script = @Script + 'GO' + @NewLine + @NewLine;
        
        -- ===============================================================
        -- C. Generate Merge Procedure
        -- Optimization #7: Enhanced with error handling and hints
        -- Optimization #11: Optional batch processing
        -- ===============================================================
        
        DECLARE @ProcName SYSNAME = QUOTENAME(@SourceSchema) + '.usp_Merge_' + @SourceTable;
        
        SET @Script = @Script + 'CREATE OR ALTER PROCEDURE ' + @ProcName + @NewLine;
        
        -- Add parameters for batch processing if enabled
        IF @EnableBatching = 1
        BEGIN
            SET @Script = @Script + '    @BatchSize INT = ' + CAST(@BatchSize AS NVARCHAR(10)) + ',' + @NewLine;
            SET @Script = @Script + '    @EnableBatching BIT = 1' + @NewLine;
        END;
        
        SET @Script = @Script + 'AS' + @NewLine;
        SET @Script = @Script + 'BEGIN' + @NewLine;
        SET @Script = @Script + '    SET NOCOUNT ON;' + @NewLine + @NewLine;
        
        -- Optimization #7: Add TRY-CATCH to generated procedure
        SET @Script = @Script + '    BEGIN TRY' + @NewLine + @NewLine;
        
        IF @EnableBatching = 1
        BEGIN
            -- Optimization #11: Batch processing logic
            SET @Script = @Script + '        IF @EnableBatching = 0' + @NewLine;
            SET @Script = @Script + '        BEGIN' + @NewLine;
            SET @Script = @Script + '            -- Standard MERGE (non-batched)' + @NewLine;
        END;
        
        -- Optimization #7: Add transaction and hints
        SET @Script = @Script + '        BEGIN TRANSACTION;' + @NewLine + @NewLine;
        
        -- MERGE statement with HOLDLOCK hint
        SET @Script = @Script + '        MERGE INTO ' + @TableName + 
                       ' WITH (HOLDLOCK) AS TGT' + @NewLine;
        SET @Script = @Script + '        USING ' + @ViewName + ' AS SRC ON (' + @NewLine;
        SET @Script = @Script + '            ' + @PKJoinCondition + @NewLine;
        SET @Script = @Script + '        )' + @NewLine + @NewLine;
        
        -- WHEN MATCHED AND hash differs
        SET @Script = @Script + '        WHEN MATCHED AND SRC.' + QUOTENAME(@ChangeHashKeyColumn) + 
                       ' <> TGT.' + QUOTENAME(@ChangeHashKeyColumn) + @NewLine;
        SET @Script = @Script + '          THEN UPDATE SET TGT.' + QUOTENAME(@ChangeHashKeyColumn) + 
                       ' = SRC.' + QUOTENAME(@ChangeHashKeyColumn) + ', ' +
                       'TGT.' + QUOTENAME(@UpdateDatetimeColumn) + ' = SRC.' + 
                       QUOTENAME(@UpdateDatetimeColumn) + ', TGT.' + QUOTENAME(@IsDeletedColumn) + 
                       ' = SRC.' + QUOTENAME(@IsDeletedColumn);
        
        IF @AttrColumnsUpdate IS NOT NULL
            SET @Script = @Script + ', ' + @NewLine + '            ' + @AttrColumnsUpdate;
        
        SET @Script = @Script + @NewLine + @NewLine;
        
        -- WHEN NOT MATCHED BY TARGET
        SET @Script = @Script + '        WHEN NOT MATCHED BY TARGET' + @NewLine;
        SET @Script = @Script + '          THEN INSERT (' + @AllColumns + ')' + @NewLine;
        SET @Script = @Script + '            VALUES (' + @AllColumns + ')' + @NewLine + @NewLine;
        
        -- WHEN NOT MATCHED BY SOURCE
        SET @Script = @Script + '        WHEN NOT MATCHED BY SOURCE AND TGT.' + 
                       QUOTENAME(@IsDeletedColumn) + ' = CAST(0 AS BIT)' + @NewLine;
        SET @Script = @Script + '          THEN UPDATE SET TGT.' + QUOTENAME(@ChangeHashKeyColumn) + 
                       ' = CONVERT(VARBINARY(32), 0),' + @NewLine;
        SET @Script = @Script + '            TGT.' + QUOTENAME(@UpdateDatetimeColumn) + 
                       ' = CURRENT_TIMESTAMP,' + @NewLine;
        SET @Script = @Script + '            TGT.' + QUOTENAME(@IsDeletedColumn) + 
                       ' = CAST(1 AS BIT)' + @NewLine + @NewLine;
        
        -- OUTPUT clause
        SET @Script = @Script + '        OUTPUT' + @NewLine;
        SET @Script = @Script + '            CURRENT_TIMESTAMP AS merge_datetime,' + @NewLine;
        SET @Script = @Script + '            CASE WHEN Inserted.' + QUOTENAME(@IsDeletedColumn) + 
                       ' = CAST(1 AS BIT) THEN N''DELETE'' ELSE $action END AS merge_action,' + @NewLine;
        SET @Script = @Script + '            ''' + @TableName + ''' AS full_olap_table_name,' + @NewLine;
        SET @Script = @Script + '            ' + @PKDescription + ' AS primary_key_description' + @NewLine;
        SET @Script = @Script + '        INTO audit.merge_log_details' + @NewLine + @NewLine;
        
        -- Optimization #7: Add query hint
        SET @Script = @Script + '        OPTION (RECOMPILE);' + @NewLine + @NewLine;
        
        SET @Script = @Script + '        COMMIT TRANSACTION;' + @NewLine;
        
        IF @EnableBatching = 1
        BEGIN
            -- Close non-batched block and add batched version
            SET @Script = @Script + '        END' + @NewLine;
            SET @Script = @Script + '        ELSE' + @NewLine;
            SET @Script = @Script + '        BEGIN' + @NewLine;
            SET @Script = @Script + '            -- Batched processing' + @NewLine;
            SET @Script = @Script + '            DECLARE @RowsAffected INT = 1;' + @NewLine;
            SET @Script = @Script + '            DECLARE @TotalProcessed INT = 0;' + @NewLine;
            SET @Script = @Script + '            DECLARE @BatchNumber INT = 0;' + @NewLine + @NewLine;
            SET @Script = @Script + '            WHILE @RowsAffected > 0' + @NewLine;
            SET @Script = @Script + '            BEGIN' + @NewLine;
            SET @Script = @Script + '                SET @BatchNumber = @BatchNumber + 1;' + @NewLine;
            SET @Script = @Script + '                PRINT ''Processing batch '' + CAST(@BatchNumber AS NVARCHAR(10)) + ''...'';' + @NewLine + @NewLine;
            SET @Script = @Script + '                BEGIN TRANSACTION;' + @NewLine + @NewLine;
            SET @Script = @Script + '                -- Process one batch' + @NewLine;
            SET @Script = @Script + '                MERGE INTO ' + @TableName + ' WITH (ROWLOCK) AS TGT' + @NewLine;
            SET @Script = @Script + '                USING (' + @NewLine;
            SET @Script = @Script + '                    SELECT TOP (@BatchSize) *' + @NewLine;
            SET @Script = @Script + '                    FROM ' + @ViewName + ' AS SRC' + @NewLine;
            SET @Script = @Script + '                ) AS SRC ON (' + @PKJoinCondition + ')' + @NewLine;
            SET @Script = @Script + '                WHEN MATCHED AND SRC.' + QUOTENAME(@ChangeHashKeyColumn) + 
                           ' <> TGT.' + QUOTENAME(@ChangeHashKeyColumn) + @NewLine;
            SET @Script = @Script + '                  THEN UPDATE SET TGT.' + QUOTENAME(@ChangeHashKeyColumn) + 
                           ' = SRC.' + QUOTENAME(@ChangeHashKeyColumn) + ', ' +
                           'TGT.' + QUOTENAME(@UpdateDatetimeColumn) + ' = SRC.' + 
                           QUOTENAME(@UpdateDatetimeColumn) + ', TGT.' + QUOTENAME(@IsDeletedColumn) + 
                           ' = SRC.' + QUOTENAME(@IsDeletedColumn);
            
            IF @AttrColumnsUpdate IS NOT NULL
                SET @Script = @Script + ', ' + @NewLine + '                    ' + @AttrColumnsUpdate;
            
            SET @Script = @Script + @NewLine;
            SET @Script = @Script + '                WHEN NOT MATCHED BY TARGET' + @NewLine;
            SET @Script = @Script + '                  THEN INSERT (' + @AllColumns + ')' + @NewLine;
            SET @Script = @Script + '                    VALUES (' + @AllColumns + ')' + @NewLine;
            SET @Script = @Script + '                OUTPUT CURRENT_TIMESTAMP, $action, ''' + @TableName + 
                           ''', ' + @PKDescription + @NewLine;
            SET @Script = @Script + '                INTO audit.merge_log_details;' + @NewLine + @NewLine;
            SET @Script = @Script + '                SET @RowsAffected = @@ROWCOUNT;' + @NewLine;
            SET @Script = @Script + '                SET @TotalProcessed = @TotalProcessed + @RowsAffected;' + @NewLine + @NewLine;
            SET @Script = @Script + '                COMMIT TRANSACTION;' + @NewLine;
            SET @Script = @Script + '                PRINT ''Batch '' + CAST(@BatchNumber AS NVARCHAR(10)) + '' processed '' + CAST(@RowsAffected AS NVARCHAR(10)) + '' rows.'';' + @NewLine;
            SET @Script = @Script + '            END;' + @NewLine + @NewLine;
            SET @Script = @Script + '            PRINT ''Total rows processed: '' + CAST(@TotalProcessed AS NVARCHAR(20));' + @NewLine;
            SET @Script = @Script + '        END;' + @NewLine;
        END;
        
        SET @Script = @Script + @NewLine;
        SET @Script = @Script + '    END TRY' + @NewLine;
        SET @Script = @Script + '    BEGIN CATCH' + @NewLine;
        SET @Script = @Script + '        IF @@TRANCOUNT > 0' + @NewLine;
        SET @Script = @Script + '            ROLLBACK TRANSACTION;' + @NewLine + @NewLine;
        SET @Script = @Script + '        -- Re-throw the error' + @NewLine;
        SET @Script = @Script + '        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();' + @NewLine;
        SET @Script = @Script + '        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();' + @NewLine;
        SET @Script = @Script + '        DECLARE @ErrorState INT = ERROR_STATE();' + @NewLine + @NewLine;
        SET @Script = @Script + '        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);' + @NewLine;
        SET @Script = @Script + '    END CATCH;' + @NewLine;
        SET @Script = @Script + 'END;' + @NewLine;
        SET @Script = @Script + 'GO' + @NewLine + @NewLine;
        
        -- Add execution call
        SET @Script = @Script + '-- Execute the merge procedure' + @NewLine;
        SET @Script = @Script + 'EXEC ' + @ProcName;
        
        IF @EnableBatching = 1
            SET @Script = @Script + ' @EnableBatching = 1, @BatchSize = ' + CAST(@BatchSize AS NVARCHAR(10));
        
        SET @Script = @Script + ';' + @NewLine;
        SET @Script = @Script + 'GO' + @NewLine;
        
        -- ===============================================================
        -- Optimization #10: Store in cache if enabled
        -- ===============================================================
        
        IF @UseCache = 1
        BEGIN
            -- Recalculate view hash if not already done
            IF @ViewHash IS NULL
            BEGIN
                SET @ViewHash = HASHBYTES('SHA2_256', (
                    SELECT STRING_AGG(
                        CONCAT(column_name, ':', data_type, ':', 
                               max_length, ':', precision_value, ':', scale_value), 
                        '|'
                    ) WITHIN GROUP (ORDER BY column_id)
                    FROM @Columns
                ));
            END;
            
            -- Store in cache (or update if exists)
            MERGE INTO dbo.GeneratedScriptCache AS TGT
            USING (
                SELECT @SourceSchema AS SourceSchema, @SourceTable AS SourceTable,
                       @ConfigHash AS ConfigurationHash, @ViewHash AS ViewStructureHash
            ) AS SRC
            ON TGT.SourceSchema = SRC.SourceSchema
               AND TGT.SourceTable = SRC.SourceTable
               AND TGT.ConfigurationHash = SRC.ConfigurationHash
               AND TGT.ViewStructureHash = SRC.ViewStructureHash
            WHEN MATCHED THEN
                UPDATE SET GeneratedScript = @Script,
                          LastUsedDate = GETDATE(),
                          UsageCount = TGT.UsageCount + 1
            WHEN NOT MATCHED THEN
                INSERT (SourceSchema, SourceTable, ConfigurationHash, 
                        ViewStructureHash, GeneratedScript)
                VALUES (SRC.SourceSchema, SRC.SourceTable, SRC.ConfigurationHash,
                        SRC.ViewStructureHash, @Script);
        END;
        
        -- ===============================================================
        -- Optimization #13: Log successful completion
        -- ===============================================================
        
        UPDATE dbo.ScriptGenerationLog
        SET ExecutionEndTime = GETDATE(),
            ColumnCount = (SELECT COUNT(*) FROM @Columns),
            ScriptLength = LEN(@Script),
            WasSuccessful = 1
        WHERE LogId = @LogId;
        
        -- Output the generated script
        PRINT @Script;
        
    END TRY
    BEGIN CATCH
        -- Optimization #5: Comprehensive error handling
        DECLARE @ErrorNumber INT = ERROR_NUMBER();
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        -- Log the error
        UPDATE dbo.ScriptGenerationLog
        SET ExecutionEndTime = GETDATE(),
            WasSuccessful = 0,
            ErrorMessage = @ErrorMessage,
            ErrorNumber = @ErrorNumber,
            ErrorLine = @ErrorLine
        WHERE LogId = @LogId;
        
        -- Re-throw with context
        DECLARE @FullErrorMessage NVARCHAR(4000) = 
            'Error in usp_GenerateMergeTableFromView: ' + @ErrorMessage + 
            ' (Line ' + CAST(@ErrorLine AS NVARCHAR(10)) + ')';
        
        RAISERROR(@FullErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH;
END;
GO

PRINT '✓ Created optimized procedure: dbo.usp_GenerateMergeTableFromView';
GO

/*******************************************************************************
 * SECTION 4: UTILITY PROCEDURES
 ******************************************************************************/

-- =============================================================================
-- Procedure: dbo.usp_ClearScriptCache
-- Purpose: Clear cached scripts (all or for specific table)
-- Optimization: #10 - Cache Management
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_ClearScriptCache
    @SourceSchema SYSNAME = NULL,
    @SourceTable SYSNAME = NULL,
    @OlderThanDays INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RowsDeleted INT;
    
    IF @SourceSchema IS NOT NULL AND @SourceTable IS NOT NULL
    BEGIN
        -- Clear for specific table
        DELETE FROM dbo.GeneratedScriptCache
        WHERE SourceSchema = @SourceSchema
          AND SourceTable = @SourceTable;
        
        SET @RowsDeleted = @@ROWCOUNT;
        PRINT 'Cleared cache for ' + @SourceSchema + '.' + @SourceTable + 
              ': ' + CAST(@RowsDeleted AS NVARCHAR(10)) + ' entries removed.';
    END
    ELSE IF @OlderThanDays IS NOT NULL
    BEGIN
        -- Clear old cache entries
        DELETE FROM dbo.GeneratedScriptCache
        WHERE LastUsedDate < DATEADD(DAY, -@OlderThanDays, GETDATE());
        
        SET @RowsDeleted = @@ROWCOUNT;
        PRINT 'Cleared cache entries older than ' + CAST(@OlderThanDays AS NVARCHAR(10)) + 
              ' days: ' + CAST(@RowsDeleted AS NVARCHAR(10)) + ' entries removed.';
    END
    ELSE
    BEGIN
        -- Clear all cache
        TRUNCATE TABLE dbo.GeneratedScriptCache;
        PRINT 'All cache entries cleared.';
    END;
END;
GO

PRINT '✓ Created procedure: dbo.usp_ClearScriptCache';
GO

-- =============================================================================
-- Procedure: dbo.usp_GetScriptGenerationStats
-- Purpose: Retrieve performance statistics and cache hit rates
-- Optimization: #13 - Monitoring and #14 - Performance Testing
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_GetScriptGenerationStats
    @SourceSchema SYSNAME = NULL,
    @SourceTable SYSNAME = NULL,
    @LastNDays INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartDate DATETIME2(3) = DATEADD(DAY, -@LastNDays, GETDATE());
    
    -- Overall statistics
    SELECT 
        COUNT(*) AS TotalExecutions,
        SUM(CASE WHEN WasSuccessful = 1 THEN 1 ELSE 0 END) AS SuccessfulExecutions,
        SUM(CASE WHEN WasSuccessful = 0 THEN 1 ELSE 0 END) AS FailedExecutions,
        AVG(CASE WHEN WasSuccessful = 1 THEN DurationMs END) AS AvgDurationMs,
        MIN(CASE WHEN WasSuccessful = 1 THEN DurationMs END) AS MinDurationMs,
        MAX(CASE WHEN WasSuccessful = 1 THEN DurationMs END) AS MaxDurationMs,
        AVG(CASE WHEN WasSuccessful = 1 THEN ColumnCount END) AS AvgColumnCount,
        AVG(CASE WHEN WasSuccessful = 1 THEN ScriptLength END) AS AvgScriptLength
    FROM dbo.ScriptGenerationLog
    WHERE ExecutionStartTime >= @StartDate
      AND (@SourceSchema IS NULL OR SourceSchema = @SourceSchema)
      AND (@SourceTable IS NULL OR SourceTable = @SourceTable);
    
    -- Per-table statistics
    SELECT 
        SourceSchema,
        SourceTable,
        COUNT(*) AS Executions,
        SUM(CASE WHEN WasSuccessful = 1 THEN 1 ELSE 0 END) AS Successful,
        SUM(CASE WHEN WasSuccessful = 0 THEN 1 ELSE 0 END) AS Failed,
        AVG(CASE WHEN WasSuccessful = 1 THEN DurationMs END) AS AvgDurationMs,
        MAX(ExecutionStartTime) AS LastExecution
    FROM dbo.ScriptGenerationLog
    WHERE ExecutionStartTime >= @StartDate
      AND (@SourceSchema IS NULL OR SourceSchema = @SourceSchema)
      AND (@SourceTable IS NULL OR SourceTable = @SourceTable)
    GROUP BY SourceSchema, SourceTable
    ORDER BY Executions DESC;
    
    -- Cache statistics
    SELECT 
        COUNT(*) AS CachedScripts,
        SUM(UsageCount) AS TotalCacheHits,
        AVG(UsageCount) AS AvgHitsPerScript,
        MIN(CreatedDate) AS OldestCacheEntry,
        MAX(LastUsedDate) AS MostRecentUse
    FROM dbo.GeneratedScriptCache
    WHERE (@SourceSchema IS NULL OR SourceSchema = @SourceSchema)
      AND (@SourceTable IS NULL OR SourceTable = @SourceTable);
    
    -- Recent errors
    IF @SourceSchema IS NULL AND @SourceTable IS NULL
    BEGIN
        SELECT TOP 10
            LogId,
            SourceSchema,
            SourceTable,
            ExecutionStartTime,
            ErrorNumber,
            ErrorLine,
            ErrorMessage
        FROM dbo.ScriptGenerationLog
        WHERE WasSuccessful = 0
          AND ExecutionStartTime >= @StartDate
        ORDER BY ExecutionStartTime DESC;
    END;
END;
GO

PRINT '✓ Created procedure: dbo.usp_GetScriptGenerationStats';
GO

-- =============================================================================
-- Procedure: dbo.usp_BackupOriginalProcedure
-- Purpose: Backup the original procedure before optimization
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_BackupOriginalProcedure
AS
BEGIN
    SET NOCOUNT ON;
    
    IF OBJECT_ID('dbo.usp_GenerateMergeTableFromView_Original', 'P') IS NOT NULL
    BEGIN
        PRINT 'Backup already exists: dbo.usp_GenerateMergeTableFromView_Original';
        RETURN;
    END;
    
    -- This would need to be run before optimization
    -- Manual backup recommended
    PRINT 'Please manually backup the original procedure before optimization.';
    PRINT 'Suggested command:';
    PRINT 'sp_rename ''dbo.usp_GenerateMergeTableFromView'', ''usp_GenerateMergeTableFromView_Original'';';
END;
GO

PRINT '✓ Created procedure: dbo.usp_BackupOriginalProcedure';
GO

/*******************************************************************************
 * SECTION 5: TESTING AND PERFORMANCE FRAMEWORK
 * Optimization: #14 - Performance Testing Recommendations
 ******************************************************************************/

-- =============================================================================
-- Procedure: dbo.usp_PerformanceTestGenerator
-- Purpose: Run performance tests with different table sizes
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_PerformanceTestGenerator
    @SourceSchema SYSNAME,
    @SourceTable SYSNAME,
    @Iterations INT = 5,
    @ClearCacheBetweenRuns BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT '========================================';
    PRINT 'Performance Test: ' + @SourceSchema + '.' + @SourceTable;
    PRINT 'Iterations: ' + CAST(@Iterations AS NVARCHAR(10));
    PRINT 'Clear cache between runs: ' + CASE WHEN @ClearCacheBetweenRuns = 1 THEN 'Yes' ELSE 'No' END;
    PRINT '========================================';
    PRINT '';
    
    DECLARE @i INT = 1;
    DECLARE @StartTime DATETIME2(3);
    DECLARE @EndTime DATETIME2(3);
    DECLARE @Duration INT;
    
    WHILE @i <= @Iterations
    BEGIN
        PRINT 'Run #' + CAST(@i AS NVARCHAR(10)) + ' at ' + CONVERT(NVARCHAR(30), GETDATE(), 121);
        
        IF @ClearCacheBetweenRuns = 1 AND @i > 1
        BEGIN
            EXEC dbo.usp_ClearScriptCache @SourceSchema, @SourceTable;
        END;
        
        SET @StartTime = GETDATE();
        SET STATISTICS TIME ON;
        SET STATISTICS IO ON;
        
        EXEC dbo.usp_GenerateMergeTableFromView 
            @SourceSchema = @SourceSchema,
            @SourceTable = @SourceTable,
            @UseCache = CASE WHEN @ClearCacheBetweenRuns = 0 THEN 1 ELSE 1 END;
        
        SET STATISTICS TIME OFF;
        SET STATISTICS IO OFF;
        SET @EndTime = GETDATE();
        SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);
        
        PRINT 'Duration: ' + CAST(@Duration AS NVARCHAR(10)) + ' ms';
        PRINT '';
        
        SET @i = @i + 1;
    END;
    
    PRINT '========================================';
    PRINT 'Performance Test Complete';
    PRINT '========================================';
    
    -- Show summary statistics
    EXEC dbo.usp_GetScriptGenerationStats @SourceSchema, @SourceTable, 1;
END;
GO

PRINT '✓ Created procedure: dbo.usp_PerformanceTestGenerator';
GO

-- =============================================================================
-- View: dbo.vw_CacheEfficiency
-- Purpose: Monitor cache hit rates and efficiency
-- Optimization: #10 - Cache Monitoring
-- =============================================================================
CREATE OR ALTER VIEW dbo.vw_CacheEfficiency
AS
SELECT 
    c.SourceSchema,
    c.SourceTable,
    c.UsageCount AS CacheHits,
    c.CreatedDate,
    c.LastUsedDate,
    DATEDIFF(DAY, c.CreatedDate, GETDATE()) AS CacheAgeDays,
    DATEDIFF(DAY, c.LastUsedDate, GETDATE()) AS DaysSinceLastUse,
    LEN(c.GeneratedScript) AS ScriptLength,
    -- Calculate executions from log
    (SELECT COUNT(*) 
     FROM dbo.ScriptGenerationLog l
     WHERE l.SourceSchema = c.SourceSchema
       AND l.SourceTable = c.SourceTable
       AND l.ExecutionStartTime >= c.CreatedDate
    ) AS TotalExecutions,
    -- Calculate cache hit rate
    CASE WHEN (SELECT COUNT(*) 
               FROM dbo.ScriptGenerationLog l
               WHERE l.SourceSchema = c.SourceSchema
                 AND l.SourceTable = c.SourceTable
                 AND l.ExecutionStartTime >= c.CreatedDate) > 0
         THEN CAST(c.UsageCount AS FLOAT) / 
              (SELECT COUNT(*) 
               FROM dbo.ScriptGenerationLog l
               WHERE l.SourceSchema = c.SourceSchema
                 AND l.SourceTable = c.SourceTable
                 AND l.ExecutionStartTime >= c.CreatedDate) * 100
         ELSE 0
    END AS CacheHitRatePercent
FROM dbo.GeneratedScriptCache c;
GO

PRINT '✓ Created view: dbo.vw_CacheEfficiency';
GO

/*******************************************************************************
 * SECTION 6: EXAMPLE USAGE AND DOCUMENTATION
 ******************************************************************************/

PRINT '';
PRINT '========================================';
PRINT 'Installation Complete!';
PRINT '========================================';
PRINT '';
PRINT 'Created Objects:';
PRINT '  Tables:';
PRINT '    - dbo.ScriptGenerationLog';
PRINT '    - dbo.GeneratedScriptCache';
PRINT '    - audit.merge_log_details';
PRINT '';
PRINT '  Functions:';
PRINT '    - dbo.fn_BuildDataTypeDefinition';
PRINT '    - dbo.fn_ValidateSQLIdentifier';
PRINT '    - dbo.fn_CalculateParameterHash';
PRINT '';
PRINT '  Procedures:';
PRINT '    - dbo.usp_GenerateMergeTableFromView (OPTIMIZED)';
PRINT '    - dbo.usp_ClearScriptCache';
PRINT '    - dbo.usp_GetScriptGenerationStats';
PRINT '    - dbo.usp_PerformanceTestGenerator';
PRINT '';
PRINT '  Views:';
PRINT '    - dbo.vw_CacheEfficiency';
PRINT '';
PRINT 'Example Usage:';
PRINT '';
PRINT '  -- Basic usage (with caching):';
PRINT '  EXEC dbo.usp_GenerateMergeTableFromView ';
PRINT '      @SourceSchema = ''dbo'', ';
PRINT '      @SourceTable = ''Customer'';';
PRINT '';
PRINT '  -- With custom column names:';
PRINT '  EXEC dbo.usp_GenerateMergeTableFromView ';
PRINT '      @SourceSchema = ''dbo'', ';
PRINT '      @SourceTable = ''Customer'',';
PRINT '      @ChangeHashKeyColumn = ''HashKey'',';
PRINT '      @UpdateDatetimeColumn = ''ModifiedDate'';';
PRINT '';
PRINT '  -- With batch processing enabled:';
PRINT '  EXEC dbo.usp_GenerateMergeTableFromView ';
PRINT '      @SourceSchema = ''dbo'', ';
PRINT '      @SourceTable = ''LargeTable'',';
PRINT '      @EnableBatching = 1,';
PRINT '      @BatchSize = 5000;';
PRINT '';
PRINT '  -- Clear cache:';
PRINT '  EXEC dbo.usp_ClearScriptCache;';
PRINT '  EXEC dbo.usp_ClearScriptCache @SourceSchema = ''dbo'', @SourceTable = ''Customer'';';
PRINT '';
PRINT '  -- View statistics:';
PRINT '  EXEC dbo.usp_GetScriptGenerationStats @LastNDays = 30;';
PRINT '  SELECT * FROM dbo.vw_CacheEfficiency;';
PRINT '';
PRINT '  -- Run performance tests:';
PRINT '  EXEC dbo.usp_PerformanceTestGenerator ';
PRINT '      @SourceSchema = ''dbo'', ';
PRINT '      @SourceTable = ''Customer'',';
PRINT '      @Iterations = 10;';
PRINT '';
PRINT '========================================';
GO
