CREATE OR ALTER PROCEDURE dbo.usp_GenerateMergeTableFromView
    @SourceSchema SYSNAME,
    @SourceTable SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ViewName SYSNAME = @SourceSchema + '.' + @SourceTable + 'View';
    DECLARE @TableName SYSNAME = @SourceSchema + '.' + @SourceTable;
    DECLARE @ViewObjectId INT;
    DECLARE @ErrorMsg NVARCHAR(500);

    -- =============================================
    -- STEP 1: Validate view exists
    -- =============================================
    SET @ViewObjectId = OBJECT_ID(@ViewName, 'V');
    
    IF @ViewObjectId IS NULL
    BEGIN
        SET @ErrorMsg = 'View ' + @ViewName + ' does not exist.';
        RAISERROR(@ErrorMsg, 16, 1);
        RETURN;
    END;

    -- =============================================
    -- STEP 2: Get column metadata and identify categories
    -- =============================================
    DECLARE @Columns TABLE (
        column_id INT,
        column_name SYSNAME,
        data_type NVARCHAR(128),
        max_length INT,
        precision_value INT,
        scale_value INT,
        is_nullable BIT,
        column_category NVARCHAR(20) -- 'PK', 'DW', 'ATTR'
    );

    -- Insert all columns with metadata
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
    ORDER BY c.column_id;

    -- Identify data-warehouse columns boundaries
    DECLARE @FirstDWColumnId INT, @LastDWColumnId INT;

    SELECT @FirstDWColumnId = MIN(column_id)
    FROM @Columns
    WHERE column_name IN ('ChangeHashKey', 'InsertDatetime', 'UpdateDatetime', 'IsDeleted');

    SELECT @LastDWColumnId = MAX(column_id)
    FROM @Columns
    WHERE column_name IN ('ChangeHashKey', 'InsertDatetime', 'UpdateDatetime', 'IsDeleted');

    -- Validate at least one data-warehouse column exists
    IF @FirstDWColumnId IS NULL
    BEGIN
        SET @ErrorMsg = 'View ' + @ViewName + ' does not contain any data-warehouse columns (ChangeHashKey, InsertDatetime, UpdateDatetime, IsDeleted).';
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
    SET @Script = @Script + '    WHEN MATCHED AND SRC.ChangeHashKey <> TGT.ChangeHashKey' + @NewLine;
    SET @Script = @Script + '      THEN UPDATE SET TGT.ChangeHashKey = SRC.ChangeHashKey, ' +
        'TGT.UpdateDatetime = SRC.UpdateDatetime, TGT.IsDeleted = SRC.IsDeleted';
    
    IF LEN(@AttrColumnsUpdate) > 0
        SET @Script = @Script + ', ' + @NewLine + '        ' + @AttrColumnsUpdate;
    
    SET @Script = @Script + @NewLine + @NewLine;

    -- WHEN NOT MATCHED BY TARGET
    SET @Script = @Script + '    WHEN NOT MATCHED BY TARGET' + @NewLine;
    SET @Script = @Script + '      THEN INSERT (' + @AllColumns + ')' + @NewLine;
    SET @Script = @Script + '        VALUES (' + @AllColumnsValues + ')' + @NewLine + @NewLine;

    -- WHEN NOT MATCHED BY SOURCE
    SET @Script = @Script + '    WHEN NOT MATCHED BY SOURCE AND TGT.IsDeleted = CAST(0 AS BIT)' + @NewLine;
    SET @Script = @Script + '      THEN UPDATE SET TGT.ChangeHashKey = CONVERT(VARBINARY(32), 0),' + @NewLine;
    SET @Script = @Script + '        TGT.UpdateDatetime = CURRENT_TIMESTAMP,' + @NewLine;
    SET @Script = @Script + '        TGT.IsDeleted = CAST(1 AS BIT)' + @NewLine + @NewLine;

    -- OUTPUT clause
    SET @Script = @Script + '    OUTPUT' + @NewLine;
    SET @Script = @Script + '        CURRENT_TIMESTAMP AS merge_datetime,' + @NewLine;
    SET @Script = @Script + '        CASE WHEN Inserted.IsDeleted = CAST(1 AS BIT) THEN N''DELETE'' ELSE $action END AS merge_action,' + @NewLine;
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
