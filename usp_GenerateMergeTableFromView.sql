/*******************************************************************************
 * PROCEDURE: dbo.usp_GenerateMergeTableFromView
 * 
 * PURPOSE:
 *   Generates T-SQL scripts for creating dimensional tables and their corresponding
 *   MERGE synchronization stored procedures from view definitions.
 *   
 *   This is a metadata-driven code generation approach that introspects view
 *   structure using SQL Server system catalogs and produces standardized DDL/DML
 *   scripts following data warehouse best practices.
 *
 * PATTERN:
 *   Convention-over-Configuration with Positional Column Categorization:
 *   - Columns BEFORE data-warehouse columns = Primary Key columns (PK)
 *   - Data-warehouse columns = Change tracking columns (DW)
 *   - Columns AFTER data-warehouse columns = Business attribute columns (ATTR)
 *
 * PARAMETERS:
 *   @SourceSchema           - Schema name containing the source view
 *   @SourceTable            - Base table name (view will be @SourceTable + 'View')
 *   @ChangeHashKeyColumn    - Name of the hash key column for change detection
 *                             (default: 'ChangeHashKey')
 *   @InsertDatetimeColumn   - Name of the insert timestamp column
 *                             (default: 'InsertDatetime')
 *   @UpdateDatetimeColumn   - Name of the update timestamp column
 *                             (default: 'UpdateDatetime')
 *   @IsDeletedColumn        - Name of the soft delete flag column
 *                             (default: 'IsDeleted')
 *
 * OUTPUTS:
 *   Prints generated T-SQL script containing:
 *   1. Table creation script (IF NOT EXISTS pattern for idempotency)
 *   2. Primary key constraint definition
 *   3. MERGE stored procedure with four-scenario logic:
 *      - INSERT new records (NOT MATCHED BY TARGET)
 *      - UPDATE changed records (MATCHED with different hash)
 *      - SOFT DELETE missing records (NOT MATCHED BY SOURCE)
 *      - NO-OP for unchanged records (MATCHED with same hash)
 *   4. Audit logging OUTPUT clause
 *   5. Procedure execution call
 *
 * EXAMPLE USAGE:
 *   EXEC dbo.usp_GenerateMergeTableFromView 
 *       @SourceSchema = 'Dim',
 *       @SourceTable = 'Customer';
 *   
 *   -- With custom DW column names:
 *   EXEC dbo.usp_GenerateMergeTableFromView 
 *       @SourceSchema = 'Fact',
 *       @SourceTable = 'Sales',
 *       @ChangeHashKeyColumn = 'RecordHash',
 *       @UpdateDatetimeColumn = 'ModifiedDate';
 *
 * DEPENDENCIES:
 *   - Source view must exist (e.g., Dim.CustomerView)
 *   - View must contain at least one data-warehouse column
 *   - View must have columns before data-warehouse columns (for PK)
 *   - audit.merge_log_details table must exist for generated procedures
 *
 * CONVENTIONS:
 *   - View naming: [Schema].[Table]View (e.g., Dim.CustomerView)
 *   - Table naming: [Schema].[Table] (e.g., Dim.Customer)
 *   - Procedure naming: [Schema].usp_Merge_[Table] (e.g., Dim.usp_Merge_Customer)
 *   - PK constraint: PK_[Schema]_[Table]
 *
 * GENERATED SCRIPT STRUCTURE:
 *   -- DROP TABLE (commented out for safety)
 *   IF OBJECT_ID(...) IS NULL
 *   BEGIN
 *       SELECT TOP (0) * INTO [Table] FROM [View];
 *       ALTER TABLE [Table] ALTER COLUMN [PKCol] [Type] NOT NULL;
 *       ...
 *       ALTER TABLE [Table] ADD CONSTRAINT [PKName] PRIMARY KEY CLUSTERED (...);
 *   END;
 *   GO
 *   
 *   CREATE OR ALTER PROCEDURE [Schema].usp_Merge_[Table]
 *   AS
 *   BEGIN
 *       MERGE INTO [Table] AS TGT
 *       USING [View] AS SRC ON (...)
 *       WHEN MATCHED ... THEN UPDATE ...
 *       WHEN NOT MATCHED BY TARGET THEN INSERT ...
 *       WHEN NOT MATCHED BY SOURCE ... THEN UPDATE ... (soft delete)
 *       OUTPUT ... INTO audit.merge_log_details;
 *   END;
 *   GO
 *
 * OPTIMIZATION NOTES:
 *   This is the BASELINE version. See DatabaseObjects_MergeOptimizations.sql
 *   for the fully optimized version with:
 *   - Cursor elimination (STRING_AGG)
 *   - Helper functions for data type building
 *   - Caching mechanism
 *   - Batch processing support
 *   - Comprehensive error handling
 *   - Performance monitoring
 *
 * VERSION: 1.1 (Enhanced with optional parameter support)
 * CREATED: Original date unknown
 * MODIFIED: 2026-05-22 - Added optional DW column name parameters
 * MODIFIED: 2026-05-23 - Added comprehensive inline documentation
 *
 * AUTHOR: Original author unknown
 * ENHANCED BY: GitHub Copilot
 *
 * REFERENCES:
 *   - README-merge_table_from_view.md - Pattern explanation
 *   - README-CommentsByClaude.md - Architectural analysis
 *   - README-merge_optimization.md - Optimization recommendations
 *   - DatabaseObjects_MergeOptimizations.sql - Optimized implementation
 *
 ******************************************************************************/
CREATE OR ALTER PROCEDURE dbo.usp_GenerateMergeTableFromView
    @SourceSchema SYSNAME,
    @SourceTable SYSNAME,
    @ChangeHashKeyColumn SYSNAME = 'ChangeHashKey',
    @InsertDatetimeColumn SYSNAME = 'InsertDatetime',
    @UpdateDatetimeColumn SYSNAME = 'UpdateDatetime',
    @IsDeletedColumn SYSNAME = 'IsDeleted'
AS
BEGIN
    -- Suppress row count messages for cleaner output
    SET NOCOUNT ON;

    /***************************************************************************
     * STEP 1: INITIALIZE VARIABLES AND CONSTRUCT OBJECT NAMES
     *
     * NAMING CONVENTION:
     *   View:  [Schema].[Table]View  (e.g., Dim.CustomerView)
     *   Table: [Schema].[Table]      (e.g., Dim.Customer)
     *
     * This convention allows the procedure to automatically derive the view name
     * from the table name by appending 'View'. This is a CONVENTION that must be
     * consistently followed across the entire data warehouse.
     *
     * IMPORTANT: If your organization uses different naming patterns (e.g.,
     * vw_Customer, Customer_v), this procedure will NOT work without modification.
     ***************************************************************************/
    DECLARE @ViewName SYSNAME = @SourceSchema + '.' + @SourceTable + 'View';
    DECLARE @TableName SYSNAME = @SourceSchema + '.' + @SourceTable;
    DECLARE @ViewObjectId INT;  -- System object ID for metadata queries
    DECLARE @ErrorMsg NVARCHAR(500);  -- Reusable error message variable

    /***************************************************************************
     * STEP 2: VALIDATE VIEW EXISTENCE
     *
     * Using OBJECT_ID() with 'V' type parameter ensures we're looking specifically
     * for a VIEW object, not a table, procedure, or other database object.
     *
     * VALIDATION STRATEGY:
     *   - Fail-fast: If the view doesn't exist, there's no point continuing
     *   - Returns NULL if view not found (safe - no exception thrown)
     *   - Provides clear error message with the exact view name attempted
     *
     * LIMITATION: Does not validate view structure or column existence at this point.
     ***************************************************************************/
    SET @ViewObjectId = OBJECT_ID(@ViewName, 'V');
    
    -- Exit immediately if view doesn't exist - no point in continuing
    IF @ViewObjectId IS NULL
    BEGIN
        SET @ErrorMsg = 'View ' + @ViewName + ' does not exist.';
        RAISERROR(@ErrorMsg, 16, 1);  -- Severity 16 = user-correctable error
        RETURN;  -- Explicit return to prevent further execution
    END;

    /***************************************************************************
     * STEP 3: INTROSPECT VIEW METADATA USING SYSTEM CATALOGS
     *
     * METADATA-DRIVEN APPROACH:
     *   This is the core of the code generation strategy. Instead of requiring
     *   developers to maintain XML configs or metadata tables, we query SQL
     *   Server's system catalog views (sys.columns, sys.types) to discover
     *   the view structure at runtime.
     *
     * TABLE VARIABLE STRUCTURE:
     *   - column_id: Ordinal position (CRITICAL for positional categorization)
     *   - column_name: Used for generating column lists
     *   - data_type: Base type name (varchar, int, decimal, etc.)
     *   - max_length: Used for VARCHAR(n), NVARCHAR(n) - NOTE: nvarchar is 2x
     *   - precision_value: For DECIMAL(p,s), NUMERIC(p,s)
     *   - scale_value: For DECIMAL(p,s), NUMERIC(p,s), DATETIME2(s)
     *   - is_nullable: Currently captured but NOT used in generation (all PKs forced NOT NULL)
     *   - column_category: Will be populated in next step ('PK', 'DW', 'ATTR')
     *
     * OPTIMIZATION NOTE:
     *   In the optimized version (DatabaseObjects_MergeOptimizations.sql),
     *   this table variable has a PRIMARY KEY on column_id and an index on
     *   column_category for better query performance.
     ***************************************************************************/
    DECLARE @Columns TABLE (
        column_id INT,              -- Ordinal position in view (1-based)
        column_name SYSNAME,        -- Column name
        data_type NVARCHAR(128),    -- Base data type name
        max_length INT,             -- Max length for string/binary types
        precision_value INT,        -- Precision for numeric types
        scale_value INT,            -- Scale for numeric types
        is_nullable BIT,            -- NULL/NOT NULL (captured but not currently used)
        column_category NVARCHAR(20) -- Will be: 'PK', 'DW', or 'ATTR'
    );

    /***************************************************************************
     * QUERY SYSTEM CATALOG FOR COLUMN METADATA
     *
     * sys.columns contains one row per column for every table/view in the database.
     * We filter by object_id to get only columns from our target view.
     *
     * KEY FUNCTIONS:
     *   - TYPE_NAME(user_type_id): Converts type ID to readable name (varchar, int, etc.)
     *   - max_length: Returns storage size in bytes
     *     WARNING: For NVARCHAR/NCHAR, divide by 2 to get character count!
     *   - precision: Total digits for numeric types
     *   - scale: Digits after decimal for numeric types
     *
     * ORDER BY column_id: CRITICAL for positional categorization algorithm!
     ***************************************************************************/
    INSERT INTO @Columns (column_id, column_name, data_type, max_length, precision_value, scale_value, is_nullable)
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
    ORDER BY c.column_id;  -- MUST maintain ordinal order for categorization!

    /***************************************************************************
     * STEP 4: IDENTIFY DATA-WAREHOUSE COLUMN BOUNDARIES (POSITIONAL LOGIC)
     *
     * THE CORE CONVENTION:
     *   This procedure uses column POSITION to determine column PURPOSE.
     *
     *   Expected view structure:
     *   ┌─────────────────────────────────────────────────────────────┐
     *   │ Column Position │ Column Type     │ Category │ Example    │
     *   ├─────────────────────────────────────────────────────────────┤
     *   │ 1..N           │ Primary Keys    │ 'PK'     │ CustomerId │
     *   │ N+1..N+4       │ DW Columns      │ 'DW'     │ HashKey    │
     *   │ N+5..END       │ Attributes      │ 'ATTR'   │ FirstName  │
     *   └─────────────────────────────────────────────────────────────┘
     *
     * ALGORITHM:
     *   1. Find the FIRST occurrence of any DW column (MIN)
     *   2. Find the LAST occurrence of any DW column (MAX)
     *   3. Columns BEFORE first DW column = Primary Keys
     *   4. Columns BETWEEN first and last DW column = DW columns
     *   5. Columns AFTER last DW column = Attributes
     *
     * CRITICAL ASSUMPTION:
     *   All DW columns MUST be contiguous (no PK or ATTR columns in between)
     *   This is why we use MIN and MAX - if DW columns are scattered, the
     *   algorithm will incorrectly categorize columns between them as 'DW'.
     *
     * FRAGILITY WARNING (see README-CommentsByClaude.md Part II.1):
     *   Adding a column BEFORE the DW columns accidentally makes it a PK!
     *   Reordering SELECT columns in the view breaks the categorization!
     *   This is the single biggest architectural risk of this approach.
     *
     * WHY THIS APPROACH WAS CHOSEN:
     *   - No extended properties needed (metadata pollution)
     *   - No naming prefixes required (PK_CustomerId, ATTR_FirstName)
     *   - View definition is self-documenting
     *   - Simple O(n) algorithm
     *
     * ENHANCEMENT IMPLEMENTED (2026-05-22):
     *   Parameters allow custom DW column names instead of hardcoding.
     ***************************************************************************/
    DECLARE @FirstDWColumnId INT, @LastDWColumnId INT;

    -- Find the boundary of data-warehouse columns
    SELECT @FirstDWColumnId = MIN(column_id)
    FROM @Columns
    WHERE column_name IN (@ChangeHashKeyColumn, @InsertDatetimeColumn, @UpdateDatetimeColumn, @IsDeletedColumn);

    SELECT @LastDWColumnId = MAX(column_id)
    FROM @Columns
    WHERE column_name IN (@ChangeHashKeyColumn, @InsertDatetimeColumn, @UpdateDatetimeColumn, @IsDeletedColumn);

    -- Validate at least one data-warehouse column exists
    IF @FirstDWColumnId IS NULL
    BEGIN
        SET @ErrorMsg = 'View ' + @ViewName + ' does not contain any data-warehouse columns (' + @ChangeHashKeyColumn + ', ' + @InsertDatetimeColumn + ', ' + @UpdateDatetimeColumn + ', ' + @IsDeletedColumn + ').';
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
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
        SET @ErrorMsg = 'View ' + @ViewName + ' does not have any primary key columns before data-warehouse columns.';
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END;

    -- =============================================
    -- STEP 3: Build helper functions for column lists
    -- =============================================
    DECLARE @PKColumns NVARCHAR(MAX) = '';
    DECLARE @PKColumnsWithAlias NVARCHAR(MAX) = '';
    DECLARE @PKJoinCondition NVARCHAR(MAX) = '';
    DECLARE @PKDescription NVARCHAR(MAX) = '';
    DECLARE @AttrColumns NVARCHAR(MAX) = '';
    DECLARE @AttrColumnsUpdate NVARCHAR(MAX) = '';
    DECLARE @AllColumns NVARCHAR(MAX) = '';
    DECLARE @AllColumnsValues NVARCHAR(MAX) = '';

    -- Build PK columns list
    SELECT @PKColumns = @PKColumns + column_name + ', '
    FROM @Columns
    WHERE column_category = 'PK'
    ORDER BY column_id;
    SET @PKColumns = LEFT(@PKColumns, LEN(@PKColumns) - 1); -- Remove trailing comma

    -- Build PK JOIN condition
    SELECT @PKJoinCondition = @PKJoinCondition + 
        'SRC.' + column_name + ' = TGT.' + column_name + ' AND '
    FROM @Columns
    WHERE column_category = 'PK'
    ORDER BY column_id;
    SET @PKJoinCondition = LEFT(@PKJoinCondition, LEN(@PKJoinCondition) - 4); -- Remove trailing AND

    -- Build PK description for audit logging
    SELECT @PKDescription = @PKDescription + 
        CASE 
            WHEN column_id > (SELECT MIN(column_id) FROM @Columns WHERE column_category = 'PK')
            THEN ''' + '', ' 
            ELSE '''' 
        END +
        column_name + ' = '' + CAST(COALESCE(inserted.' + column_name + ', deleted.' + column_name + ') AS NVARCHAR)'
    FROM @Columns
    WHERE column_category = 'PK'
    ORDER BY column_id;

    -- Build attribute columns list
    SELECT @AttrColumns = @AttrColumns + column_name + ', '
    FROM @Columns
    WHERE column_category = 'ATTR'
    ORDER BY column_id;
    IF LEN(@AttrColumns) > 0
        SET @AttrColumns = LEFT(@AttrColumns, LEN(@AttrColumns) - 1);

    -- Build attribute update SET clause
    SELECT @AttrColumnsUpdate = @AttrColumnsUpdate + 
        'TGT.' + column_name + ' = SRC.' + column_name + ', '
    FROM @Columns
    WHERE column_category = 'ATTR'
    ORDER BY column_id;
    IF LEN(@AttrColumnsUpdate) > 0
        SET @AttrColumnsUpdate = LEFT(@AttrColumnsUpdate, LEN(@AttrColumnsUpdate) - 1);

    -- Build all columns list (for INSERT)
    SELECT @AllColumns = @AllColumns + column_name + ', '
    FROM @Columns
    WHERE column_category IN ('PK', 'DW', 'ATTR')
    ORDER BY column_id;
    SET @AllColumns = LEFT(@AllColumns, LEN(@AllColumns) - 1);

    -- Build all columns VALUES list (for INSERT)
    SET @AllColumnsValues = @AllColumns; -- Same as column names in this case

    -- =============================================
    -- STEP 4: Generate T-SQL script
    -- =============================================
    DECLARE @Script NVARCHAR(MAX) = '';
    DECLARE @NewLine NVARCHAR(2) = CHAR(13) + CHAR(10);

    -- A. Commented DROP statement
    SET @Script = @Script + '--DROP TABLE IF EXISTS ' + @TableName + ';' + @NewLine;
    SET @Script = @Script + 'GO' + @NewLine + @NewLine;

    -- B. Table creation block
    SET @Script = @Script + 'IF OBJECT_ID(''' + @TableName + ''', ''U'') IS NULL' + @NewLine;
    SET @Script = @Script + 'BEGIN' + @NewLine + @NewLine;

    -- B1. SELECT TOP 0 to create table structure
    SET @Script = @Script + CHAR(9) + 'SELECT TOP (0) * INTO ' + @TableName + ' FROM ' + @ViewName + ';' + @NewLine + @NewLine;

    -- B2. ALTER COLUMN for each PK column
    DECLARE @ColumnName SYSNAME, @DataType NVARCHAR(128), @MaxLength INT, @Precision INT, @Scale INT;
    DECLARE @DataTypeDefinition NVARCHAR(128);

    DECLARE pk_cursor CURSOR FOR
    SELECT column_name, data_type, max_length, precision_value, scale_value
    FROM @Columns
    WHERE column_category = 'PK'
    ORDER BY column_id;

    OPEN pk_cursor;
    FETCH NEXT FROM pk_cursor INTO @ColumnName, @DataType, @MaxLength, @Precision, @Scale;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Build data type definition
        SET @DataTypeDefinition = CASE
            WHEN @DataType IN ('char', 'varchar', 'binary', 'varbinary') THEN 
                @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength AS NVARCHAR) END + ')'
            WHEN @DataType IN ('nchar', 'nvarchar') THEN 
                @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength / 2 AS NVARCHAR) END + ')'
            WHEN @DataType IN ('decimal', 'numeric') THEN 
                @DataType + '(' + CAST(@Precision AS NVARCHAR) + ', ' + CAST(@Scale AS NVARCHAR) + ')'
            WHEN @DataType IN ('float') THEN 
                @DataType + '(' + CAST(@Precision AS NVARCHAR) + ')'
            WHEN @DataType IN ('datetime2', 'time', 'datetimeoffset') THEN 
                @DataType + '(' + CAST(@Scale AS NVARCHAR) + ')'
            ELSE @DataType
        END;

        SET @Script = @Script + CHAR(9) + 'ALTER TABLE ' + @TableName + ' ALTER COLUMN ' + 
            @ColumnName + ' ' + @DataTypeDefinition + ' NOT NULL;' + @NewLine;

        FETCH NEXT FROM pk_cursor INTO @ColumnName, @DataType, @MaxLength, @Precision, @Scale;
    END;

    CLOSE pk_cursor;
    DEALLOCATE pk_cursor;

    SET @Script = @Script + @NewLine;

    -- B3. Add PRIMARY KEY constraint
    DECLARE @PKConstraintName SYSNAME = 'PK_' + @SourceSchema + '_' + @SourceTable;
    SET @Script = @Script + CHAR(9) + 'ALTER TABLE ' + @TableName + ' ADD CONSTRAINT ' + @PKConstraintName + 
        ' PRIMARY KEY CLUSTERED (' + @PKColumns + ');' + @NewLine + @NewLine;

    -- B4. Commented ALTER COLUMN for each attribute
    IF EXISTS (SELECT 1 FROM @Columns WHERE column_category = 'ATTR')
    BEGIN
        DECLARE attr_cursor CURSOR FOR
        SELECT column_name, data_type, max_length, precision_value, scale_value
        FROM @Columns
        WHERE column_category = 'ATTR'
        ORDER BY column_id;

        OPEN attr_cursor;
        FETCH NEXT FROM attr_cursor INTO @ColumnName, @DataType, @MaxLength, @Precision, @Scale;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Build data type definition
            SET @DataTypeDefinition = CASE
                WHEN @DataType IN ('char', 'varchar', 'binary', 'varbinary') THEN 
                    @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength AS NVARCHAR) END + ')'
                WHEN @DataType IN ('nchar', 'nvarchar') THEN 
                    @DataType + '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength / 2 AS NVARCHAR) END + ')'
                WHEN @DataType IN ('decimal', 'numeric') THEN 
                    @DataType + '(' + CAST(@Precision AS NVARCHAR) + ', ' + CAST(@Scale AS NVARCHAR) + ')'
                WHEN @DataType IN ('float') THEN 
                    @DataType + '(' + CAST(@Precision AS NVARCHAR) + ')'
                WHEN @DataType IN ('datetime2', 'time', 'datetimeoffset') THEN 
                    @DataType + '(' + CAST(@Scale AS NVARCHAR) + ')'
                ELSE @DataType
            END;

            SET @Script = @Script + CHAR(9) + '--ALTER TABLE ' + @TableName + ' ALTER COLUMN ' + 
                @ColumnName + ' ' + @DataTypeDefinition + ' NOT NULL;' + @NewLine;

            FETCH NEXT FROM attr_cursor INTO @ColumnName, @DataType, @MaxLength, @Precision, @Scale;
        END;

        CLOSE attr_cursor;
        DEALLOCATE attr_cursor;

        SET @Script = @Script + @NewLine;
    END;

    SET @Script = @Script + 'END;' + @NewLine;
    SET @Script = @Script + 'GO' + @NewLine + @NewLine;

    -- C. Merge stored procedure
    DECLARE @ProcName SYSNAME = @SourceSchema + '.usp_Merge_' + @SourceTable;

    SET @Script = @Script + 'CREATE OR ALTER PROCEDURE ' + @ProcName + @NewLine;
    SET @Script = @Script + 'AS' + @NewLine;
    SET @Script = @Script + 'BEGIN' + @NewLine;
    SET @Script = @Script + '    SET NOCOUNT ON;' + @NewLine + @NewLine;

    -- MERGE statement
    SET @Script = @Script + '    MERGE INTO ' + @TableName + ' AS TGT' + @NewLine;
    SET @Script = @Script + '    USING ' + @ViewName + ' AS SRC ON (' + @NewLine;
    SET @Script = @Script + '         ' + @PKJoinCondition + @NewLine;
    SET @Script = @Script + '    )' + @NewLine + @NewLine;

    -- WHEN MATCHED AND hash differs
    SET @Script = @Script + '    WHEN MATCHED AND SRC.' + @ChangeHashKeyColumn + ' <> TGT.' + @ChangeHashKeyColumn + @NewLine;
    SET @Script = @Script + '      THEN UPDATE SET TGT.' + @ChangeHashKeyColumn + ' = SRC.' + @ChangeHashKeyColumn + ', ' +
        'TGT.' + @UpdateDatetimeColumn + ' = SRC.' + @UpdateDatetimeColumn + ', TGT.' + @IsDeletedColumn + ' = SRC.' + @IsDeletedColumn;
    
    IF LEN(@AttrColumnsUpdate) > 0
        SET @Script = @Script + ', ' + @NewLine + '        ' + @AttrColumnsUpdate;
    
    SET @Script = @Script + @NewLine + @NewLine;

    -- WHEN NOT MATCHED BY TARGET
    SET @Script = @Script + '    WHEN NOT MATCHED BY TARGET' + @NewLine;
    SET @Script = @Script + '      THEN INSERT (' + @AllColumns + ')' + @NewLine;
    SET @Script = @Script + '        VALUES (' + @AllColumnsValues + ')' + @NewLine + @NewLine;

    -- WHEN NOT MATCHED BY SOURCE
    SET @Script = @Script + '    WHEN NOT MATCHED BY SOURCE AND TGT.' + @IsDeletedColumn + ' = CAST(0 AS BIT)' + @NewLine;
    SET @Script = @Script + '      THEN UPDATE SET TGT.' + @ChangeHashKeyColumn + ' = CONVERT(VARBINARY(32), 0),' + @NewLine;
    SET @Script = @Script + '        TGT.' + @UpdateDatetimeColumn + ' = CURRENT_TIMESTAMP,' + @NewLine;
    SET @Script = @Script + '        TGT.' + @IsDeletedColumn + ' = CAST(1 AS BIT)' + @NewLine + @NewLine;

    -- OUTPUT clause
    SET @Script = @Script + '    OUTPUT' + @NewLine;
    SET @Script = @Script + '        CURRENT_TIMESTAMP AS merge_datetime,' + @NewLine;
    SET @Script = @Script + '        CASE WHEN Inserted.' + @IsDeletedColumn + ' = CAST(1 AS BIT) THEN N''DELETE'' ELSE $action END AS merge_action,' + @NewLine;
    SET @Script = @Script + '        ''' + @TableName + ''' AS full_olap_table_name,' + @NewLine;
    SET @Script = @Script + '        ' + @PKDescription + ' AS primary_key_description' + @NewLine;
    SET @Script = @Script + '    INTO audit.merge_log_details;' + @NewLine + @NewLine;

    SET @Script = @Script + 'END' + @NewLine;
    SET @Script = @Script + 'GO' + @NewLine + @NewLine;

    -- Add execution call
    SET @Script = @Script + 'EXEC ' + @ProcName + ';' + @NewLine;
    SET @Script = @Script + 'GO' + @NewLine;

    -- =============================================
    -- STEP 5: Output the generated script
    -- =============================================
    PRINT @Script;

END;
GO
